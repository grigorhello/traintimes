import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  downloadNextService,
  downloadUnionDepartures,
  handlePlatforms,
  parseNextService,
  parseUnionDepartures,
  platformFor,
  platformName,
  PlatformRelay,
  withUnionPlatforms,
} from '../src/platforms.ts';

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
    { trip: '1713', line: 'LW', departure: '2026-11-18 14:17:00', platform: '11/12' },
    { trip: '1715', line: 'LW', departure: '2026-11-18 14:17:00', platform: '7' },
    { trip: '1717', line: 'LW', departure: '2026-11-18 14:17:00', platform: null },
  ]);
});

test('one train comes as an object, none as null', () => {
  assert.equal(parseNextService({ NextService: { Lines: line('1713', '3', '') } })[0]?.platform, '3');
  assert.deepEqual(parseNextService({ NextService: { Lines: null } }), []);
  assert.deepEqual(parseNextService({ NextService: null }), []);
});

test('a train’s platform is found by GO’s trip number, the last part of its trip id, as the app finds it (TT-233)', () => {
  const board = { fetchedAt: 0, trips: parseNextService({ NextService: { Lines: [line('1713', '3', ''), line('1715', '', ''), line('1713', '', '11 & 12')] } }) };
  assert.equal(platformFor(board, '20261118-LW-1713'), '11/12', 'the last posting wins');
  assert.equal(platformFor(board, '20261118-LW-1715'), null, 'on the board with no platform yet');
  assert.equal(platformFor(board, '20261118-LW-1717'), null, 'not on the board');
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

// Union's pair (TT-245, D122): GO's per-stop board gives one number at Union, its Union departures list the pair.

const departure = (TripNumber: string, Platform: string, extra: Record<string, unknown> = {}) => ({
  TripNumber, Platform, Service: 'Lakeshore West', ServiceType: 'T', Time: '2026-11-26 08:47:00', Info: '', Stops: [{ Name: 'Clarkson', Code: 'CL' }], ...extra,
});

test('a platform is written one way: the numbers joined by "/"', () => {
  assert.equal(platformName('7 & 8'), '7/8');
  assert.equal(platformName('12, 13'), '12/13');
  assert.equal(platformName('7/8'), '7/8');
  assert.equal(platformName(' 7 and 8 '), '7/8');
  assert.equal(platformName('12;13'), '12/13');
  assert.equal(platformName('8'), '8');
  assert.equal(platformName(3), '3');
  assert.equal(platformName('-'), undefined);
  assert.equal(platformName(' '), undefined);
  assert.equal(platformName(null), undefined);
});

test('the Union list: trains with a platform posted, as a pair; buses and "-" left out; one train as an object', () => {
  const trips = parseUnionDepartures({
    AllDepartures: {
      Trip: [departure('1609', '7 & 8'), departure('1611', '-'), departure('3011', '12, 13'), departure('2001', '25', { ServiceType: 'B' }), departure('', '3')],
    },
  });
  assert.deepEqual(trips, [
    { trip: '1609', departure: '2026-11-26 08:47:00', platform: '7/8' },
    { trip: '3011', departure: '2026-11-26 08:47:00', platform: '12/13' },
  ]);
  assert.deepEqual(parseUnionDepartures({ AllDepartures: { Trip: departure('1609', '5 & 6') } }), [{ trip: '1609', departure: '2026-11-26 08:47:00', platform: '5/6' }]);
  assert.deepEqual(parseUnionDepartures({ AllDepartures: null }), []);
  assert.deepEqual(parseUnionDepartures(null), []);
});

test('Union’s board takes the Union list’s pair, keeps NextService’s number where the list posts none, and adds a train only the list has', () => {
  const next = parseNextService({ NextService: { Lines: [line('1609', '', '8'), line('3209', '', '13'), line('1611', '', '')] } });
  const union = parseUnionDepartures({ AllDepartures: { Trip: [departure('1609', '7 & 8'), departure('3209', '-'), departure('9208', '12 & 13')] } });
  assert.deepEqual(
    withUnionPlatforms(next, union).map(({ trip, platform }) => ({ trip, platform })),
    [
      { trip: '1609', platform: '7/8' },
      { trip: '3209', platform: '13' },
      { trip: '1611', platform: null },
      { trip: '9208', platform: '12/13' },
    ],
  );
});

test('the Union list is asked next to the feeds, with the key', async () => {
  const urls: string[] = [];
  const fetcher = (async (url: URL) => {
    urls.push(url.toString());
    return Response.json({ AllDepartures: { Trip: [] } });
  }) as unknown as typeof fetch;
  const base = 'https://api.openmetrolinx.com/OpenDataAPI/api/V1/Gtfs/Feed/';
  assert.equal(await downloadUnionDepartures(fetcher, base, undefined), null);
  assert.deepEqual(await downloadUnionDepartures(fetcher, base, 'k'), { AllDepartures: { Trip: [] } });
  assert.deepEqual(urls, ['https://api.openmetrolinx.com/OpenDataAPI/api/V1/ServiceUpdate/UnionDepartures/All?key=k']);
});

test('the relay reads the Union list for Union only, once per 30 s with its board, and gets by with either one', async () => {
  let now = Date.UTC(2026, 10, 26, 13, 32);
  const calls: string[] = [];
  let next: unknown = { NextService: { Lines: [line('1609', '', '8')] } };
  let union: unknown = { AllDepartures: { Trip: [departure('1609', '7 & 8')] } };
  const relay = new PlatformRelay({
    download: async (stop) => (calls.push(stop), next),
    union: async () => (calls.push('Union list'), union),
    now: () => now,
  });
  assert.equal(platformFor((await relay.get('UN'))!, '20261126-LW-1609'), '7/8');
  await relay.get('UN');
  await relay.get('CL');
  assert.deepEqual(calls, ['UN', 'Union list', 'CL'], 'Clarkson reads its own board only');

  now += 31_000;
  union = null;
  assert.equal(platformFor((await relay.get('UN'))!, '20261126-LW-1609'), '8', 'The list failing: NextService’s number');
  now += 31_000;
  union = { AllDepartures: { Trip: [departure('1609', '7 & 8')] } };
  next = null;
  assert.equal(platformFor((await relay.get('UN'))!, '20261126-LW-1609'), '7/8', 'NextService failing: the list’s pair');
  now += 31_000;
  union = null;
  assert.equal(await relay.get('UN'), null, 'Both failing: no board');
});
