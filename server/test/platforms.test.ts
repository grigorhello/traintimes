import assert from 'node:assert/strict';
import { test } from 'node:test';
import { downloadNextService, handlePlatforms, parseNextService, PlatformRelay } from '../src/platforms.ts';

const line = (trip: string, scheduled: string, actual: string, extra: Record<string, unknown> = {}) => ({
  StopCode: 'UN', LineCode: 'LW', ServiceType: 'T', TripNumber: trip,
  ScheduledDepartureTime: '2026-11-18 14:17:00', ScheduledPlatform: scheduled, ActualPlatform: actual, ...extra,
});

test('a posted platform wins over the planned one; buses and trains without a number are left out', () => {
  const trips = parseNextService({
    NextService: {
      Lines: [
        line('1713', '9 & 10', '11 & 12'),
        line('1715', '7', ''),
        line('1717', '', ' '),
        line('2001', '', '', { ServiceType: 'B' }),
        { ...line('', '3', '') },
      ],
    },
  });
  assert.deepEqual(trips, [
    { trip: '1713', line: 'LW', departure: '2026-11-18 14:17:00', platform: '11 & 12' },
    { trip: '1715', line: 'LW', departure: '2026-11-18 14:17:00', platform: '7' },
    { trip: '1717', line: 'LW', departure: '2026-11-18 14:17:00', platform: null },
  ]);
});

test('one train comes as an object, none as null', () => {
  assert.equal(parseNextService({ NextService: { Lines: line('1713', '3', '') } })[0]?.platform, '3');
  assert.deepEqual(parseNextService({ NextService: { Lines: null } }), []);
  assert.deepEqual(parseNextService({ NextService: null }), []);
});

test('the download asks GO for the station next to the feeds, with the key, and never without it', async () => {
  const urls: string[] = [];
  const fetcher = (async (url: URL) => {
    urls.push(url.toString());
    return new Response(JSON.stringify({ NextService: { Lines: [] } }));
  }) as unknown as typeof fetch;
  const base = 'https://api.openmetrolinx.com/OpenDataAPI/api/V1/Gtfs/Feed/';
  assert.equal(await downloadNextService(fetcher, base, undefined, 'UN'), null);
  assert.deepEqual(await downloadNextService(fetcher, base, 'k', 'UN'), { NextService: { Lines: [] } });
  assert.deepEqual(urls, ['https://api.openmetrolinx.com/OpenDataAPI/api/V1/Stop/NextService/UN?key=k']);
});

test('a station is fetched from GO at most once per 30 s, failures too', async () => {
  let now = Date.UTC(2026, 10, 18, 19, 14);
  const calls: string[] = [];
  let answer: unknown = { NextService: { Lines: [line('1713', '3', '')] } };
  const relay = new PlatformRelay({ download: async (stop) => (calls.push(stop), answer), now: () => now });
  assert.equal((await relay.get('UN'))?.trips[0]?.platform, '3');
  await relay.get('UN');
  assert.deepEqual(calls, ['UN']);
  await relay.get('CL');
  assert.deepEqual(calls, ['UN', 'CL']);
  now += 31_000;
  answer = null;
  assert.equal(await relay.get('UN'), null);
  assert.equal(await relay.get('UN'), null);
  assert.deepEqual(calls, ['UN', 'CL', 'UN']);
});

test('the endpoint answers JSON, 400 for a bad station and 503 while GO fails', async () => {
  let answer: unknown = { NextService: { Lines: [line('1713', '3', '')] } };
  const relay = () => new PlatformRelay({ download: async () => answer, now: () => Date.UTC(2026, 10, 18, 19, 14) });
  const get = (path: string, r = relay()) => handlePlatforms(new Request(`https://alerts.traintimes.ca${path}`), r);
  assert.equal(await get('/v1/trains'), null);
  const ok = await get('/v1/live/platforms?stop=un');
  assert.equal(ok?.status, 200);
  assert.deepEqual(await ok?.json(), {
    fetchedAt: Date.UTC(2026, 10, 18, 19, 14) / 1000,
    trips: [{ trip: '1713', line: 'LW', departure: '2026-11-18 14:17:00', platform: '3' }],
  });
  assert.equal((await get('/v1/live/platforms?stop=../x'))?.status, 400);
  answer = null;
  assert.equal((await get('/v1/live/platforms?stop=UN'))?.status, 503);
});
