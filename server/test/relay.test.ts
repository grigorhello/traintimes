import assert from 'node:assert/strict';
import { test } from 'node:test';
import { decodeVehicles } from '../src/realtime.ts';
import { FeedRelay, handleLive, type FeedName } from '../src/relay.ts';
import { at, repoFile } from './support.ts';

// A small protobuf writer for a VehiclePosition sample (the TT-131 samples have no positions).
const varint = (n: number): number[] => {
  const out: number[] = [];
  while (n > 0x7f) {
    out.push((n % 128) | 0x80);
    n = Math.floor(n / 128);
  }
  out.push(n);
  return out;
};
const bytesField = (number: number, value: number[] | string) => {
  const data = typeof value === 'string' ? [...new TextEncoder().encode(value)] : value;
  return [...varint((number << 3) | 2), ...varint(data.length), ...data];
};
const varintField = (number: number, value: number) => [...varint(number << 3), ...varint(value)];
const floatField = (number: number, value: number) => {
  const view = new DataView(new ArrayBuffer(4));
  view.setFloat32(0, value, true);
  return [...varint((number << 3) | 5), ...new Uint8Array(view.buffer)];
};

function vehicle(id: string, trip: string, route: string, lat: number, lon: number, status: number | null, time: number) {
  const descriptor = [...bytesField(1, trip), ...bytesField(3, '20261109'), ...bytesField(5, route)];
  const position = [...floatField(1, lat), ...floatField(2, lon), ...floatField(3, 90)];
  const vp = [
    ...bytesField(1, descriptor),
    ...bytesField(2, position),
    ...(status === null ? [] : varintField(4, status)),
    ...varintField(5, time / 1000),
    ...bytesField(8, [...bytesField(1, 'V1')]),
  ];
  return bytesField(2, [...bytesField(1, id), ...bytesField(4, vp)]);
}

/** Two Lakeshore West trains (one stopped at a station) and one Kitchener train at 7:00 AM on Nov 9. */
const sample = new Uint8Array([
  ...bytesField(1, [...bytesField(1, '2.0'), ...varintField(3, at('7:00') / 1000)]),
  ...vehicle('1', '20261109-LW-1713', '09261126-LW', 43.4467, -79.6668, 1, at('6:59:50')),
  ...vehicle('2', '20261109-LW-1015', '09261126-LW', 43.6, -79.5, null, at('6:59:40')),
  ...vehicle('3', '20261109-GT-3531', '09261126-GT', 43.7, -79.6, 2, at('6:59:30')),
]);

function rig(feeds: Partial<Record<FeedName, Uint8Array | null>>) {
  let now = at('7:00');
  const calls: FeedName[] = [];
  const store = new Map<string, Response>();
  const cache = {
    match: async (key: RequestInfo | URL) => store.get(String(key))?.clone(),
    put: async (key: RequestInfo | URL, response: Response) => void store.set(String(key), response),
  } as unknown as Pick<Cache, 'match' | 'put'>;
  const make = () =>
    new FeedRelay({
      download: async (feed) => {
        calls.push(feed);
        return feeds[feed] ?? null;
      },
      cache,
      now: () => now,
    });
  return { relay: make(), make, calls, advance: (s: number) => (now += s * 1000) };
}

interface TrainsBody {
  timestamp: number;
  trains: { tripId: string; stopped: boolean; timestamp: number }[];
}

const get = (relay: FeedRelay, path: string) => handleLive(new Request(`https://alerts.traintimes.ca${path}`), relay);

test('decodes trains with their trip, position, stopped flag and time', () => {
  const { timestamp, trains } = decodeVehicles(sample);
  assert.equal(timestamp, at('7:00'));
  assert.equal(trains.length, 3);
  assert.equal(trains[0].tripId, '20261109-LW-1713');
  assert.equal(trains[0].startDate, '20261109');
  assert.ok(Math.abs(trains[0].latitude - 43.4467) < 1e-4);
  assert.ok(Math.abs(trains[0].longitude + 79.6668) < 1e-4);
  assert.equal(trains[0].stopped, true);
  assert.equal(trains[1].stopped, false, 'no status reads IN_TRANSIT_TO');
  assert.equal(trains[2].timestamp, at('6:59:30'));
});

test('GET /v1/trains returns the trains of a line, and a second request within 30 s does not fetch again', async () => {
  const { relay, calls, advance } = rig({ VehiclePosition: sample });
  const response = (await get(relay, '/v1/trains?line=LW'))!;
  assert.equal(response.status, 200);
  const body = (await response.json()) as TrainsBody;
  assert.equal(body.timestamp, at('7:00') / 1000);
  assert.deepEqual(body.trains.map((t) => t.tripId), ['20261109-LW-1713', '20261109-LW-1015']);
  assert.equal(body.trains[0].stopped, true);
  assert.equal(body.trains[0].timestamp, at('6:59:50') / 1000);

  advance(29);
  const all = (await (await get(relay, '/v1/trains'))!.json()) as TrainsBody;
  assert.equal(all.trains.length, 3);
  assert.deepEqual(calls, ['VehiclePosition']);

  advance(1);
  await get(relay, '/v1/trains');
  assert.deepEqual(calls, ['VehiclePosition', 'VehiclePosition']);
});

test('relays TripUpdates and Alerts as GO sent them', async () => {
  const tripUpdates = repoFile('Tests/UnitTests/Core/Realtime/tripupdates-0700.pb');
  const alerts = repoFile('Tests/UnitTests/Core/Realtime/alerts-0702.pb');
  const { relay } = rig({ TripUpdates: tripUpdates, Alerts: alerts });
  const response = (await get(relay, '/v1/live/trip-updates'))!;
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('content-type'), 'application/x-protobuf');
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), tripUpdates);
  assert.deepEqual(new Uint8Array(await (await get(relay, '/v1/live/alerts'))!.arrayBuffer()), alerts);
  assert.equal(await get(relay, '/v1/installations'), null, 'other paths go to the API');
  assert.equal((await handleLive(new Request('https://alerts.traintimes.ca/v1/trains', { method: 'POST' }), relay))!.status, 405);
});

test('another isolate in the same data centre takes the cached copy', async () => {
  const { relay, make, calls, advance } = rig({ TripUpdates: new Uint8Array([1, 2, 3]) });
  await relay.get('TripUpdates');
  advance(10);
  const other = await make().get('TripUpdates');
  assert.deepEqual(other?.bytes, new Uint8Array([1, 2, 3]));
  assert.equal(other?.fetchedAt, at('7:00'));
  assert.deepEqual(calls, ['TripUpdates']);
});

test('a failed GO call answers 503 and is not retried for 30 s, by any isolate', async () => {
  const { relay, make, calls, advance } = rig({});
  assert.equal((await get(relay, '/v1/live/trip-updates'))!.status, 503);
  advance(20);
  assert.equal(await relay.get('TripUpdates'), null);
  assert.equal(await make().get('TripUpdates'), null);
  assert.deepEqual(calls, ['TripUpdates']);
  advance(10);
  await relay.get('TripUpdates');
  assert.deepEqual(calls, ['TripUpdates', 'TripUpdates']);
});

test('requests at the same time share one GO call', async () => {
  const { relay, calls } = rig({ Alerts: new Uint8Array([9]) });
  await Promise.all([relay.get('Alerts'), relay.get('Alerts'), relay.get('Alerts')]);
  assert.deepEqual(calls, ['Alerts']);
});
