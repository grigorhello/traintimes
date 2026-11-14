// Feed replays (acceptance criterion 1): one initial alert, meaningful updates, recovery, cancellation, expiry and no
// duplicates, end to end through the API, the timetable import, the monitoring cycle and APNs, on the TT-131 sample
// feeds and the TT-130 sample timetable, with no Metrolinx key.

import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';
import { handleRequest } from '../src/api.ts';
import { MAX_SENDS, monitor } from '../src/monitor.ts';
import type { Feed } from '../src/realtime.ts';
import { at, call, FakeApns, INSTALLATION, memoryD1, sampleFeed, saveSampleTimetables, TOKEN } from './support.ts';

let db: D1Database;
let apns: FakeApns;
const api = (request: Request) => handleRequest(request, db, at('6:30'));

/** Registers the device and arms This-trip alerts, Oakville to Union, for trains on Monday Nov 9. */
async function setUp(trains: Record<string, string>, timeFormat = '12h', installation = INSTALLATION) {
  assert.equal((await call(api, 'PUT', `/v1/installations/${installation}`, { deviceToken: TOKEN, timeFormat })).status, 204);
  for (const [trip, departure] of Object.entries(trains)) {
    const response = await call(api, 'PUT', `/v1/installations/${installation}/rules/${trip}`, {
      kind: 'trip',
      tripId: `20261109-${trip}`,
      serviceDate: '20261109',
      line: 'LW',
      scheduledDeparture: new Date(at(departure)).toISOString(),
      origin: { id: 'OA', name: 'Oakville' },
      destination: { id: 'UN', name: 'Union' },
    });
    assert.equal(response.status, 200);
  }
}

/** One monitoring cycle at `time` reading `feed`; returns the notifications sent, as "title | body". */
async function cycle(time: string, feed: Feed | null): Promise<string[]> {
  const before = apns.pushes.length;
  await monitor({ db, apns, feed: async () => feed, now: at(time) });
  return apns.pushes.slice(before).map((push) => `${push.title} | ${push.body}`);
}

/** A feed with one trip's delay at Oakville, written at `time`. */
function delayFeed(time: string, trip: string, minutes: number): Feed {
  return {
    timestamp: at(time),
    tripUpdates: [
      { tripId: `20261109-${trip}`, startDate: '20261109', cancelled: false, stopTimeUpdates: [{ stopId: 'OA', relationship: 'scheduled', departure: { delay: minutes * 60 } }] },
    ],
  };
}

beforeEach(async () => {
  db = memoryD1();
  apns = new FakeApns();
  // As the daily upload of Nov 9 sends it: Nov 9 to 16, of which the sample has Nov 9 (D43).
  await saveSampleTimetables(db, ['20261109', '20261110', '20261111', '20261112', '20261113', '20261114', '20261115', '20261116']);
});

describe('feed replay', () => {
  test('sample feeds: initial delay, no update under 5 min, cancellation, recovery, skipped stop, no duplicates', async () => {
    // The 7:13 (1 min late), 7:21 (late, then recovers), 7:28 (cancelled) and 7:44 (skips Oakville) trains.
    await setUp({ 'LW-1256': '7:13', 'LW-1108': '7:21', 'LW-1858': '7:28', 'LW-1758': '7:44' });

    assert.deepEqual(await cycle('7:00:05', sampleFeed('0700')), [
      '7:21 AM train delayed 5 min | Oakville to Union. Now expected 7:26 AM, as reported at 7:00 AM.',
    ]);
    // 5 to 9 min is under the 5 min step: no update. The 7:28 is cancelled, reported at 7:00:40.
    assert.deepEqual(await cycle('7:01:05', sampleFeed('0701')), [
      '7:28 AM train cancelled | Oakville to Union. Cancelled, as reported at 7:00 AM. Open to see the next trains.',
    ]);
    // The 7:44 had no alert yet, so it goes before the 7:21's update.
    assert.deepEqual(await cycle('7:02:05', sampleFeed('0702')), [
      '7:44 AM train will skip Oakville | Skips Oakville, as reported at 7:02 AM. Open to see the next trains.',
      '7:21 AM train back on time | Oakville to Union. Expected 7:22 AM, as reported at 7:02 AM.',
    ]);
    // The same feed read again, and the same states in later feeds, send nothing.
    assert.deepEqual(await cycle('7:03:05', sampleFeed('0702')), []);
    assert.deepEqual(await cycle('7:04:05', { ...sampleFeed('0702'), timestamp: at('7:04') }), []);
  });

  test('meaningful updates, both ways, and recovery after a delay alert', async () => {
    await setUp({ 'LW-1308': '7:51' });
    assert.deepEqual(await cycle('7:04', delayFeed('7:04', 'LW-1308', 4)), [
      '7:51 AM train delayed 4 min | Oakville to Union. Now expected 7:55 AM, as reported at 7:04 AM.',
    ]);
    assert.deepEqual(await cycle('7:06', delayFeed('7:06', 'LW-1308', 10)), [
      '7:51 AM train now delayed 10 min | Oakville to Union. Now expected 8:01 AM, as reported at 7:06 AM.',
    ]);
    assert.deepEqual(await cycle('7:07', delayFeed('7:07', 'LW-1308', 13)), []);
    assert.deepEqual(await cycle('7:08', delayFeed('7:08', 'LW-1308', 5)), [
      '7:51 AM train now delayed 5 min | Oakville to Union. Now expected 7:56 AM, as reported at 7:08 AM.',
    ]);
    assert.deepEqual(await cycle('7:09', delayFeed('7:09', 'LW-1308', 2)), [
      '7:51 AM train back on time | Oakville to Union. Expected 7:53 AM, as reported at 7:09 AM.',
    ]);
    assert.deepEqual(await cycle('7:10', delayFeed('7:10', 'LW-1308', 0)), []);
  });

  test('a delay wobbling around 3 min sends one alert and one recovery', async () => {
    await setUp({ 'LW-1308': '7:51' });
    const wobble = (time: string, seconds: number): Feed => {
      const feed = delayFeed(time, 'LW-1308', 0);
      feed.tripUpdates[0].stopTimeUpdates[0].departure = { delay: seconds };
      return feed;
    };
    const sent = [];
    for (const [time, seconds] of [['7:10', 185], ['7:11', 170], ['7:12', 185], ['7:13', 170], ['7:14', 185], ['7:15', 175]] as const) {
      sent.push(...(await cycle(time, wobble(time, seconds))));
    }
    assert.deepEqual(sent, [
      '7:51 AM train delayed 3 min | Oakville to Union. Now expected 7:54 AM, as reported at 7:10 AM.',
      '7:51 AM train back on time | Oakville to Union. Expected 7:53 AM, as reported at 7:11 AM.',
    ]);
    // A real new delay after the recovery is still sent.
    assert.deepEqual(await cycle('7:16', delayFeed('7:16', 'LW-1308', 8)), [
      '7:51 AM train delayed 8 min | Oakville to Union. Now expected 7:59 AM, as reported at 7:16 AM.',
    ]);
  });

  test('rapid changes within 60 s coalesce into the latest status', async () => {
    await setUp({ 'LW-1308': '7:51' });
    await cycle('7:04', delayFeed('7:04', 'LW-1308', 4));
    assert.deepEqual(await cycle('7:04:30', delayFeed('7:04:30', 'LW-1308', 12)), []);
    assert.deepEqual(await cycle('7:05', delayFeed('7:05', 'LW-1308', 15)), [
      '7:51 AM train now delayed 15 min | Oakville to Union. Now expected 8:06 AM, as reported at 7:05 AM.',
    ]);
  });

  test('24-hour time format', async () => {
    await setUp({ 'LW-1108': '7:21' }, '24h');
    assert.deepEqual(await cycle('7:00:05', sampleFeed('0700')), [
      '07:21 train delayed 5 min | Oakville to Union. Now expected 07:26, as reported at 07:00.',
    ]);
  });

  test('expiry: APNs drops an alert after the trip window, and watching ends there', async () => {
    await setUp({ 'LW-1308': '7:51' });
    await cycle('7:04', delayFeed('7:04', 'LW-1308', 4));
    assert.equal(apns.pushes[0].expiration, at('9:51'));
    assert.deepEqual(apns.pushes[0].data, { tripId: '20261109-LW-1308', serviceDate: '20261109', originId: 'OA', destinationId: 'UN', kind: 'delay' });
    // Still not departed, so still watched long past the scheduled time...
    assert.equal((await cycle('9:40', delayFeed('9:40', 'LW-1308', 115))).length, 1);
    // ...but not after the window closes.
    assert.deepEqual(await cycle('9:52', delayFeed('9:52', 'LW-1308', 125)), []);
  });

  test('watching starts 60 min before the scheduled departure', async () => {
    await setUp({ 'LW-1308': '7:51' });
    assert.deepEqual(await cycle('6:50', delayFeed('6:50', 'LW-1308', 4)), []);
    assert.equal((await cycle('6:51', delayFeed('6:51', 'LW-1308', 4))).length, 1);
  });

  test('a reliable departure ends departure alerts', async () => {
    await setUp({ 'LW-1308': '7:51' });
    await cycle('7:04', delayFeed('7:04', 'LW-1308', 4));
    // The feed itself reports the departure, at 7:55, as past.
    assert.deepEqual(await cycle('7:56', delayFeed('7:56', 'LW-1308', 4)), []);
    assert.deepEqual(await cycle('7:58', delayFeed('7:58', 'LW-1308', 20)), []);
  });

  test("GO's real feed (D89): stops left drop out, which ends alerts; a cancelled trip skips every stop", async () => {
    await setUp({ 'LW-1308': '7:51', 'LW-1858': '7:28' });
    // Departures only, for the stops still ahead, Oakville's 7:51 first.
    const go = (time: string, minutes: number, stops: string[]): Feed => ({
      timestamp: at(time),
      tripUpdates: [
        { tripId: '20261109-LW-1308', startDate: '20261109', cancelled: false, timestamp: at(time), stopTimeUpdates: stops.map((stopId) => ({ stopId, relationship: 'scheduled' as const, departure: { delay: minutes * 60 } })) },
        { tripId: '20261109-LW-1858', startDate: '20261109', cancelled: true, timestamp: at('7:20'), stopTimeUpdates: ['OA', 'UN'].map((stopId) => ({ stopId, relationship: 'skipped' as const })) },
      ],
    });
    assert.deepEqual(await cycle('7:40', go('7:40', 4, ['OA', 'CL', 'UN'])), [
      '7:28 AM train cancelled | Oakville to Union. Cancelled, as reported at 7:20 AM. Open to see the next trains.',
      '7:51 AM train delayed 4 min | Oakville to Union. Now expected 7:55 AM, as reported at 7:40 AM.',
    ]);
    // Oakville is gone from the update: the train left, so the watch ends and a growing delay sends nothing.
    assert.deepEqual(await cycle('7:56', go('7:56', 5, ['CL', 'UN'])), []);
    const done = await db.prepare(`SELECT done FROM watches WHERE key LIKE '%LW-1308%'`).first<{ done: number }>();
    assert.equal(done!.done, 1);
    assert.deepEqual(await cycle('7:58', go('7:58', 12, ['CL', 'UN'])), []);
  });

  test('stale or missing live data sends nothing', async () => {
    await setUp({ 'LW-1308': '7:51' });
    assert.deepEqual(await cycle('7:10', delayFeed('7:06', 'LW-1308', 10)), []);
    assert.deepEqual(await cycle('7:11', null), []);
  });

  test('overlapping cycles send each alert once', async () => {
    await setUp({ 'LW-1108': '7:21' });
    const feed = sampleFeed('0700');
    await Promise.all([1, 2, 3].map(() => monitor({ db, apns, feed: async () => feed, now: at('7:00:05') })));
    assert.equal(apns.pushes.length, 1);
  });

  test('a This-trip and a Repeat rule for the same train send one message', async () => {
    await setUp({ 'LW-1108': '7:21' });
    await call(api, 'PUT', `/v1/installations/${INSTALLATION}/rules/repeat-1108`, {
      kind: 'repeat',
      tripId: '20261109-LW-1108',
      serviceDate: '20261109',
      line: 'LW',
      scheduledDeparture: new Date(at('7:21')).toISOString(),
      origin: { id: 'OA', name: 'Oakville' },
      destination: { id: 'UN', name: 'Union' },
      weekdays: [1, 2, 3, 4, 5],
    });
    assert.equal((await cycle('7:00:05', sampleFeed('0700'))).length, 1);
  });

  test(`at most ${MAX_SENDS} APNs calls a cycle (Workers Free plan); the rest go the next minute`, async () => {
    const riders = Array.from({ length: MAX_SENDS + 5 }, (_, i) => `6f1c2a9e-3b4d-4c5e-9f60-${String(i).padStart(12, '0')}`);
    for (const rider of riders) await setUp({ 'LW-1308': '7:51' }, '12h', rider);
    assert.equal((await cycle('7:04', delayFeed('7:04', 'LW-1308', 4))).length, MAX_SENDS);
    assert.equal((await cycle('7:05', delayFeed('7:05', 'LW-1308', 4))).length, 5);
    assert.equal((await cycle('7:06', delayFeed('7:06', 'LW-1308', 4))).length, 0);
  });

  test('past the cap, riders sent nothing yet go before updates', async () => {
    const riders = Array.from({ length: MAX_SENDS + 5 }, (_, i) => `6f1c2a9e-3b4d-4c5e-9f60-${String(i).padStart(12, '0')}`);
    for (const rider of riders) await setUp({ 'LW-1308': '7:51' }, '12h', rider);
    await cycle('7:04', delayFeed('7:04', 'LW-1308', 4));
    // The delay grows 5 min a minute: 45 updates are due, and 5 riders still have no alert.
    await cycle('7:05', delayFeed('7:05', 'LW-1308', 10));
    const alerted = await db.prepare('SELECT COUNT(*) AS n FROM watches WHERE sent_kind IS NOT NULL').first<{ n: number }>();
    assert.equal(alerted!.n, riders.length);
  });

  test('a late train is still watched after the service day changes at 3 AM', async () => {
    await call(api, 'PUT', `/v1/installations/${INSTALLATION}`, { deviceToken: TOKEN, timeFormat: '12h' });
    // Sunday Nov 8's 26:50 train (2:50 AM Monday), checked at 3:10 AM, when Monday's service day has begun.
    await call(api, 'PUT', `/v1/installations/${INSTALLATION}/rules/late`, {
      kind: 'trip',
      tripId: '20261108-LW-9999',
      serviceDate: '20261108',
      line: 'LW',
      scheduledDeparture: new Date(at('2:50')).toISOString(),
      origin: { id: 'OA', name: 'Oakville' },
      destination: { id: 'UN', name: 'Union' },
    });
    const late: Feed = {
      timestamp: at('3:10'),
      tripUpdates: [
        { tripId: '20261108-LW-9999', startDate: '20261108', cancelled: false, stopTimeUpdates: [{ stopId: 'OA', relationship: 'scheduled', departure: { delay: 1800 } }] },
      ],
    };
    assert.deepEqual(await cycle('3:10', late), [
      '2:50 AM train delayed 30 min | Oakville to Union. Now expected 3:20 AM, as reported at 3:10 AM.',
    ]);
  });

  test('a deleted or paused rule stops within one cycle', async () => {
    await setUp({ 'LW-1108': '7:21', 'LW-1858': '7:28' });
    await call(api, 'DELETE', `/v1/installations/${INSTALLATION}/rules/LW-1108`);
    assert.deepEqual(await cycle('7:00:05', sampleFeed('0700')), []);
    const rule = (await call(api, 'GET', `/v1/installations/${INSTALLATION}/rules`)).json.rules[0];
    await call(api, 'PUT', `/v1/installations/${INSTALLATION}/rules/LW-1858`, { ...rule, paused: true });
    assert.deepEqual(await cycle('7:01:05', sampleFeed('0701')), []);
  });
});

describe('APNs answers', () => {
  test('an expired token (410) removes the installation and its rules', async () => {
    await setUp({ 'LW-1108': '7:21', 'LW-1858': '7:28' });
    apns.result = 'unregistered';
    await cycle('7:01:05', sampleFeed('0701'));
    assert.equal(apns.pushes.length, 1, 'stops at the first rejection');
    assert.equal((await call(api, 'GET', `/v1/installations/${INSTALLATION}/rules`)).status, 404);
    assert.deepEqual(await cycle('7:02:05', sampleFeed('0702')), []);
  });

  test('a bad token is cleared until the app registers again, then the alert goes out', async () => {
    await setUp({ 'LW-1108': '7:21' });
    apns.answers = ['badToken'];
    await cycle('7:00:05', sampleFeed('0700'));
    assert.equal(apns.pushes.length, 1);
    assert.deepEqual(await cycle('7:01:05', sampleFeed('0701')), [], 'no token, nothing sent');
    assert.equal((await call(api, 'PUT', `/v1/installations/${INSTALLATION}`, { deviceToken: 'b'.repeat(64), timeFormat: '12h' })).status, 204);
    assert.deepEqual(await cycle('7:02:05', { ...sampleFeed('0701'), timestamp: at('7:02') }), [
      '7:21 AM train delayed 9 min | Oakville to Union. Now expected 7:30 AM, as reported at 7:02 AM.',
    ]);
    assert.equal(apns.pushes.at(-1)!.token, 'b'.repeat(64));
  });

  test('a temporary failure is tried again on the next cycle', async () => {
    await setUp({ 'LW-1108': '7:21' });
    apns.answers = ['retry'];
    await cycle('7:00:05', sampleFeed('0700'));
    const retried = await cycle('7:01:05', { ...sampleFeed('0700'), timestamp: at('7:01') });
    assert.deepEqual(retried, ['7:21 AM train delayed 5 min | Oakville to Union. Now expected 7:26 AM, as reported at 7:01 AM.']);
  });
});
