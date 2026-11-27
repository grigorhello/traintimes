import assert from 'node:assert/strict';
import { test } from 'node:test';
import { decodeVehicles } from '../src/realtime.ts';
import { downloadFeed, FeedRelay, handleLive, vehiclesOf, type FeedName } from '../src/relay.ts';
import { at, feedMessage, repoFile, vehicle } from './support.ts';

/** Two Lakeshore West trains (one stopped at a station) and one Kitchener train at 7:00 AM on Nov 9. */
const sample = feedMessage(at('7:00'), [
  vehicle('1', '20261109-LW-1713', '09261126-LW', 43.4467, -79.6668, 1, at('6:59:50')),
  vehicle('2', '20261109-LW-1015', '09261126-LW', 43.6, -79.5, null, at('6:59:40')),
  vehicle('3', '20261109-GT-3531', '09261126-GT', 43.7, -79.6, 2, at('6:59:30')),
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

test('GET /v1/trains?fresh=15 is served from a copy at most 15 s old; any other value, and none, 30 s (TT-251)', async () => {
  const { relay, calls, advance } = rig({ VehiclePosition: sample });
  await get(relay, '/v1/trains');
  advance(14);
  const fast = (await get(relay, '/v1/trains?fresh=15'))!;
  assert.equal(fast.status, 200);
  assert.equal(fast.headers.get('cache-control'), 'max-age=7');
  assert.deepEqual(calls, ['VehiclePosition'], 'a copy 14 s old serves the fast form');

  advance(1);
  await get(relay, '/v1/trains?fresh=15&line=LW');
  assert.deepEqual(calls, ['VehiclePosition', 'VehiclePosition'], '15 s old is too old for it');

  advance(20);
  await get(relay, '/v1/trains?fresh=5');
  await get(relay, '/v1/trains?fresh=abc');
  const plain = (await get(relay, '/v1/trains'))!;
  assert.equal(plain.headers.get('cache-control'), 'max-age=15');
  assert.equal(calls.length, 2, 'only 15 is honoured: a copy 20 s old serves the rest');
  advance(10);
  await get(relay, '/v1/trains?fresh=5');
  assert.equal(calls.length, 3, '30 s as before');
});

test('the fast form takes no older copy from the data centre, and leaves the other feeds and failures at 30 s', async () => {
  const { relay, make, calls, advance } = rig({ VehiclePosition: sample, TripUpdates: new Uint8Array([1]) });
  await relay.get('VehiclePosition');
  await relay.get('TripUpdates');
  advance(20);
  await get(make(), '/v1/trains');
  assert.deepEqual(calls, ['VehiclePosition', 'TripUpdates'], 'another isolate takes the 20 s copy at 30 s');
  await get(make(), '/v1/trains?fresh=15');
  assert.deepEqual(calls, ['VehiclePosition', 'TripUpdates', 'VehiclePosition'], 'but not for the fast form');
  await get(relay, '/v1/live/trip-updates?fresh=15');
  assert.equal(calls.length, 3, 'the parameter is the train feed\'s only');

  const failing = rig({});
  assert.equal((await get(failing.relay, '/v1/trains?fresh=15'))!.status, 503);
  failing.advance(20);
  assert.equal((await get(failing.relay, '/v1/trains?fresh=15'))!.status, 503);
  assert.deepEqual(failing.calls, ['VehiclePosition'], 'a failure is kept 30 s for the fast form too');
  failing.advance(10);
  await get(failing.relay, '/v1/trains?fresh=15');
  assert.equal(failing.calls.length, 2);
});

test('a fast request that meets a slower load in flight gets a copy young enough', async () => {
  const { relay, make, calls, advance } = rig({ VehiclePosition: sample });
  await relay.get('VehiclePosition');
  advance(20);
  const other = make();
  const [slow, fast] = await Promise.all([other.get('VehiclePosition'), other.get('VehiclePosition', 15_000)]);
  assert.equal(slow?.fetchedAt, at('7:00'), 'the 30 s request took the cached copy');
  assert.equal(fast?.fetchedAt, at('7:00') + 20_000, 'the fast one loaded its own');
  assert.equal(calls.length, 2);
});

test('a snapshot is decoded once for GET /v1/trains and the minute cycle (TT-233)', async () => {
  const { relay, advance } = rig({ VehiclePosition: sample });
  const snapshot = (await relay.get('VehiclePosition'))!;
  const vehicles = vehiclesOf(snapshot);
  assert.equal(vehicles.trains.length, 3);
  assert.equal(vehicles.timestamp, at('7:00'));
  assert.equal(vehiclesOf(snapshot), vehicles, 'the same decode, not a second one');
  // The endpoint serves that decode: a train changed in it shows in the answer.
  vehicles.trains[0].stopped = false;
  const body = (await (await get(relay, '/v1/trains'))!.json()) as TrainsBody;
  assert.equal(body.trains[0].stopped, false);
  advance(30);
  assert.notEqual(vehiclesOf((await relay.get('VehiclePosition'))!), vehicles, 'a new snapshot is decoded anew');
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

test('asks GO for protobuf and turns down anything else', async () => {
  const seen: { url: string; accept: string | null }[] = [];
  const answer = (body: BodyInit, type: string, status = 200) => (async (input: RequestInfo | URL, init?: RequestInit) => {
    seen.push({ url: String(input), accept: new Headers(init?.headers).get('accept') });
    return new Response(body, { status, headers: { 'content-type': type } });
  }) as typeof fetch;
  const base = 'https://go.example/Gtfs/Feed/';
  assert.deepEqual(await downloadFeed(answer(sample, 'application/x-protobuf'), base, 'k', 'VehiclePosition'), sample);
  assert.deepEqual(seen[0], { url: 'https://go.example/Gtfs/Feed/VehiclePosition?key=k', accept: 'application/x-protobuf' });
  assert.equal(await downloadFeed(answer('{ "header": {} }', 'application/json'), base, 'k', 'TripUpdates'), null);
  assert.equal(await downloadFeed(answer('', 'text/plain', 429), base, 'k', 'Alerts'), null);
  assert.equal(await downloadFeed(answer(sample, 'application/x-protobuf'), base, undefined, 'Alerts'), null);
  assert.equal(seen.length, 3, 'no call without the key');
});
