// Feed replays (acceptance criterion 1): one initial alert, meaningful updates, recovery, cancellation, expiry and no
// duplicates, end to end through the API, the timetable import, the monitoring cycle and APNs, on the TT-131 sample
// feeds and the TT-130 sample timetable, with no Metrolinx key.

import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';
import { handleRequest } from '../src/api.ts';
import { monitor, refreshTimetables } from '../src/monitor.ts';
import type { Feed } from '../src/realtime.ts';
import { at, call, FakeApns, INSTALLATION, memoryD1, sampleFeed, sampleGTFS, TOKEN } from './support.ts';

let db: D1Database;
let apns: FakeApns;
const api = (request: Request) => handleRequest(request, db, at('6:30'));

/** Registers the device and arms This-trip alerts, Oakville to Union, for trains on Monday Nov 9. */
async function setUp(trains: Record<string, string>, timeFormat = '12h') {
  assert.equal((await call(api, 'PUT', `/v1/installations/${INSTALLATION}`, { deviceToken: TOKEN, timeFormat })).status, 204);
  for (const [trip, departure] of Object.entries(trains)) {
    const response = await call(api, 'PUT', `/v1/installations/${INSTALLATION}/rules/${trip}`, {
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
  assert.equal(await refreshTimetables(db, async () => sampleGTFS(), at('3:30')), 1);
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
    assert.deepEqual(await cycle('7:02:05', sampleFeed('0702')), [
      '7:21 AM train back on time | Oakville to Union. Expected 7:22 AM, as reported at 7:02 AM.',
      '7:44 AM train will skip Oakville | Skips Oakville, as reported at 7:02 AM. Open to see the next trains.',
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
    assert.deepEqual(apns.pushes[0].data, { tripId: '20261109-LW-1308', serviceDate: '20261109' });
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
