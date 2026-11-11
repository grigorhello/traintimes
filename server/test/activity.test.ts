// The before-departure Live Activity (TT-178, acceptance criterion 1): start, update and end payloads at the right times,
// within the send budget, end to end through the API, the timetable and the minute cycle, on the TT-130 sample timetable.

import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';
import { contentState, phaseAt, signature, type Departure } from '../src/activity.ts';
import { handleRequest } from '../src/api.ts';
import { ApnsClient } from '../src/apns.ts';
import { MAX_SENDS, monitor } from '../src/monitor.ts';
import type { Feed } from '../src/realtime.ts';
import { at, call, FakeApns, INSTALLATION, memoryD1, saveSampleTimetables, TOKEN } from './support.ts';

const START_TOKEN = 'b'.repeat(160);
const ACTIVITY_TOKEN = 'c'.repeat(160);

let db: D1Database;
let apns: FakeApns;
const api = (request: Request) => handleRequest(request, db, at('6:30'));

/** Registers with a push-to-start token and arms a This-trip alert on the 7:13 AM from Oakville to Union (LW-1256). */
async function setUp(installation = INSTALLATION, startToken: string | null = START_TOKEN, timeFormat = '12h') {
  const registration = { deviceToken: TOKEN, timeFormat, startToken: startToken ?? undefined };
  assert.equal((await call(api, 'PUT', `/v1/installations/${installation}`, registration)).status, 204);
  const rule = await call(api, 'PUT', `/v1/installations/${installation}/rules/r1`, {
    kind: 'trip',
    tripId: '20261109-LW-1256',
    serviceDate: '20261109',
    line: 'LW',
    scheduledDeparture: new Date(at('7:13')).toISOString(),
    origin: { id: 'OA', name: 'Oakville GO' },
    destination: { id: 'UN', name: 'Union Station GO' },
  });
  assert.equal(rule.status, 200);
}

/** The app reports the activity's update token, or that its ride took the activity over. */
function report(body: Record<string, unknown>, installation = INSTALLATION) {
  return call(api, 'PUT', `/v1/installations/${installation}/activities`, {
    tripId: '20261109-LW-1256',
    serviceDate: '20261109',
    originId: 'OA',
    destinationId: 'UN',
    ...body,
  });
}

/** One cycle at `time`; returns the Live Activity pushes sent, as their `aps`. */
async function cycle(time: string, feed: Feed | null = null): Promise<any[]> {
  const before = apns.activityPushes.length;
  await monitor({ db, apns, feed: async () => feed, now: at(time) });
  return apns.activityPushes.slice(before).map((push) => (push.payload as { aps: unknown }).aps);
}

/** The 7:13 running `minutes` late at Oakville, written at `time`. */
function delayFeed(time: string, minutes: number): Feed {
  return {
    timestamp: at(time),
    tripUpdates: [
      { tripId: '20261109-LW-1256', startDate: '20261109', cancelled: false, stopTimeUpdates: [{ stopId: 'OA', relationship: 'scheduled', departure: { delay: minutes * 60 } }] },
    ],
  };
}

beforeEach(async () => {
  db = memoryD1();
  apns = new FakeApns();
  await saveSampleTimetables(db, ['20261109']);
});

describe('the activity, at the right times', () => {
  test('starts once at T−30 with the alert, updates on a change, ends 2 min after the train left', async () => {
    await setUp();
    assert.deepEqual(await cycle('6:42:30'), [], 'Not before its window');

    const [start] = await cycle('6:43:00');
    assert.equal(start.event, 'start');
    assert.equal(start['attributes-type'], 'RideActivityAttributes');
    assert.deepEqual(start.attributes, {
      tripId: '20261109-LW-1256',
      serviceDate: 20261109,
      originId: 'OA',
      destinationId: 'UN',
      lineCode: 'LW',
      lineColorHex: '#8B1A31',
      destinationName: 'Union Station',
      stopCount: 3,
    });
    assert.deepEqual(start.alert, { title: 'Your 7:13 AM train is live', body: 'Oakville GO to Union Station GO', sound: 'default' });
    assert.deepEqual(start['content-state'], {
      phase: 'countingDown',
      title: '7:13 AM to Union Station',
      detail: 'Check the board · Scheduled',
      countdownEnd: at('7:13') / 1000,
      now: '',
      time: 'departs',
      departure: 'Oakville 7:13 AM',
      arrival: 'Union Station 7:47 AM',
      arrives: 'Arrives Union Station 7:47 AM',
      position: 0,
      button: 'I’m on board',
      updated: 'Updated 6:43 AM',
      platform: 'Check the board',
      pill: false,
      late: false,
    });
    assert.equal(start['stale-date'], at('7:15') / 1000, 'Stale, and ended by the app, 2 min after it left');
    assert.equal(start.timestamp, at('6:43') / 1000);
    assert.equal(apns.activityPushes[0].token, START_TOKEN);
    assert.equal(apns.pushes.length, 0, 'No alert notification for an on-time train');

    assert.deepEqual(await cycle('6:44:00'), [], 'Sent once');
    // Until the app reports the activity's update token, nothing can reach it.
    assert.deepEqual(await cycle('6:50:00', delayFeed('6:50', 4)), []);
    assert.equal((await report({ token: ACTIVITY_TOKEN })).status, 204);

    const [delayed] = await cycle('6:51:00', delayFeed('6:51', 4));
    assert.equal(delayed.event, 'update');
    assert.equal(apns.activityPushes.at(-1)!.token, ACTIVITY_TOKEN);
    assert.equal(delayed['content-state'].detail, 'Check the board · Delayed 4 min');
    assert.equal(delayed['content-state'].late, true);
    assert.equal(delayed['content-state'].countdownEnd, at('7:17') / 1000);
    assert.equal(delayed['content-state'].departure, 'Oakville 7:17 AM');
    assert.equal(delayed['content-state'].arrival, 'Union Station 7:51 AM');
    assert.equal(delayed['stale-date'], at('7:19') / 1000);
    assert.deepEqual(await cycle('6:52:00', delayFeed('6:52', 4)), [], 'The same look sends nothing');

    const [boarding] = await cycle('7:15:30', delayFeed('7:15', 4));
    assert.equal(boarding['content-state'].phase, 'boarding');
    assert.equal(boarding['content-state'].detail, 'Check the board · Boarding now');
    assert.equal(boarding['content-state'].late, false);

    const [departed] = await cycle('7:17:30', delayFeed('7:17', 4));
    assert.equal(departed['content-state'].phase, 'departed');
    assert.equal(departed['content-state'].detail, 'Check the board · Departed 7:17 AM');
    assert.equal(departed['content-state'].countdownEnd, undefined);
    assert.equal(departed['content-state'].time, '');

    assert.deepEqual(await cycle('7:18:30', delayFeed('7:18', 4)), []);
    const [end] = await cycle('7:19:00', delayFeed('7:19', 4));
    assert.equal(end.event, 'end');
    assert.equal(end['dismissal-date'], at('7:19') / 1000);
    assert.deepEqual(await cycle('7:20:00', delayFeed('7:20', 4)), [], 'Ended once');
  });

  test('the app’s ride took it over: nothing more is sent', async () => {
    await setUp();
    await cycle('6:43:00');
    await report({ token: ACTIVITY_TOKEN });
    assert.equal((await report({ handedOff: true })).status, 204);
    assert.deepEqual(await cycle('7:11:30'), [], 'No Boarding now');
    assert.deepEqual(await cycle('7:15:30'), [], 'No end');
    const row = await db.prepare('SELECT token, state FROM activities').first();
    assert.deepEqual(row, { token: ACTIVITY_TOKEN, state: 'handedOff' }, 'Reporting the hand-off keeps the token');
  });

  test('an activity the app started is not started again; its updates follow once the token is in', async () => {
    await setUp();
    assert.equal((await report({})).status, 204, 'The app in front started it at T−30');
    assert.deepEqual(await cycle('6:43:00'), []);
    await report({ token: ACTIVITY_TOKEN });
    const [first] = await cycle('6:44:00');
    assert.equal(first.event, 'update', 'Its first look from the server');
    assert.deepEqual(await cycle('6:45:00'), []);
  });

  test('no push-to-start token (iOS 17.0 and 17.1, or not yet sent): nothing starts', async () => {
    await setUp(INSTALLATION, null);
    assert.deepEqual(await cycle('6:43:00'), []);
    assert.equal((await db.prepare('SELECT COUNT(*) AS n FROM activities').first<{ n: number }>())!.n, 0);
  });

  test('a cancelled train never starts, and a started one ends at once', async () => {
    await setUp();
    const cancelled: Feed = { timestamp: at('6:43'), tripUpdates: [{ tripId: '20261109-LW-1256', startDate: '20261109', cancelled: true, stopTimeUpdates: [] }] };
    assert.deepEqual(await cycle('6:43:00', cancelled), []);
    await cycle('6:44:00');
    await report({ token: ACTIVITY_TOKEN });
    const [end] = await cycle('6:50:00', { ...cancelled, timestamp: at('6:50') });
    assert.equal(end.event, 'end');
  });

  test('a start that fails for a while is tried again; a dead push-to-start token is dropped', async () => {
    await setUp();
    apns.answers.push('retry');
    await cycle('6:43:00');
    const [again] = await cycle('6:44:00');
    assert.equal(again.event, 'start');

    db = memoryD1();
    await saveSampleTimetables(db, ['20261109']);
    await setUp();
    apns.answers.push('badToken');
    await cycle('6:43:00');
    assert.equal(await db.prepare('SELECT token FROM start_tokens').first(), null);
    assert.deepEqual(await cycle('6:44:00'), []);
  });

  test('stays inside the cycle’s APNs calls: the rest start the next minute', async () => {
    const riders = Array.from({ length: MAX_SENDS + 5 }, (_, i) => `6f1c2a9e-3b4d-4c5e-9f60-${String(i).padStart(12, '0')}`);
    for (const rider of riders) await setUp(rider);
    assert.equal((await cycle('6:43:00')).length, MAX_SENDS);
    assert.equal((await cycle('6:44:00')).length, 5);
    assert.equal((await cycle('6:45:00')).length, 0);
  });

  test('times in 24-hour format when the app uses it', async () => {
    await setUp(INSTALLATION, START_TOKEN, '24h');
    const [start] = await cycle('6:43:00');
    assert.equal(start.alert.title, 'Your 07:13 train is live');
    assert.equal(start['content-state'].title, '07:13 to Union Station');
  });
});

describe('the rules', () => {
  const train: Departure = { scheduled: at('7:13'), scheduledArrival: at('7:47'), status: null, origin: 'Oakville GO', destination: 'Union Station GO' };

  test('the window: 30 min before, Boarding now for the last 2, Departed for 2 after', () => {
    assert.equal(phaseAt(train, at('6:42:59')), 'before');
    assert.equal(phaseAt(train, at('6:43')), 'countingDown');
    assert.equal(phaseAt(train, at('7:10:59')), 'countingDown');
    assert.equal(phaseAt(train, at('7:11')), 'boarding');
    assert.equal(phaseAt(train, at('7:13')), 'departed');
    assert.equal(phaseAt(train, at('7:14:59')), 'departed');
    assert.equal(phaseAt(train, at('7:15')), 'over');
    const late = { ...train, status: { kind: 'running' as const, delayMin: 4, expected: at('7:17'), reportedAt: at('7:00') } };
    assert.equal(phaseAt(late, at('6:46:30')), 'before', 'From the expected departure');
    assert.equal(phaseAt(late, at('6:47')), 'countingDown');
    assert.equal(phaseAt({ ...train, status: { kind: 'skipped', stop: 'destination', reportedAt: at('7:00') } }, at('7:00')), 'over');
  });

  test('on time with live data, a small lateness, and the update time does not count as a change', () => {
    const onTime = { ...train, status: { kind: 'running' as const, delayMin: 1, expected: at('7:14'), reportedAt: at('7:00') } };
    const state = contentState(onTime, 'countingDown', at('7:00'), '12h');
    assert.equal(state.detail, 'Check the board · On time');
    assert.equal(state.late, false);
    assert.equal(state.countdownEnd, at('7:14') / 1000);
    assert.equal(signature(state), signature(contentState(onTime, 'countingDown', at('7:01'), '12h')));
    // The expected time moving by a few seconds sends nothing; by a minute it does.
    const seconds = (ms: number) => ({ ...onTime, status: { ...onTime.status, expected: at('7:14') + ms } });
    assert.equal(signature(state), signature(contentState(seconds(8_000), 'countingDown', at('7:00'), '12h')));
    assert.notEqual(signature(state), signature(contentState(seconds(60_000), 'countingDown', at('7:00'), '12h')));
  });

  test('APNs gets the live activity push type, its topic and priority 10', async () => {
    const requests: { url: string; init: RequestInit }[] = [];
    const keys = (await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign'])) as CryptoKeyPair;
    const pkcs8 = new Uint8Array((await crypto.subtle.exportKey('pkcs8', keys.privateKey)) as ArrayBuffer);
    const key = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8))}\n-----END PRIVATE KEY-----\n`;
    const client = new ApnsClient({ key, keyId: 'ABC123DEFG', teamId: 'TEAM123456', topic: 'ca.traintimes.TrainTimes' }, async (url, init) => {
      requests.push({ url: String(url), init: init! });
      return new Response(null, { status: 200 });
    });
    const result = await client.sendLiveActivity({ token: START_TOKEN, environment: 'production', payload: { aps: { event: 'start' } }, expiration: at('7:15') }, at('6:43'));
    assert.equal(result, 'sent');
    assert.equal(requests[0].url, `https://api.push.apple.com/3/device/${START_TOKEN}`);
    const headers = requests[0].init.headers as Record<string, string>;
    assert.equal(headers['apns-push-type'], 'liveactivity');
    assert.equal(headers['apns-topic'], 'ca.traintimes.TrainTimes.push-type.liveactivity');
    assert.equal(headers['apns-priority'], '10');
    assert.equal(headers['apns-expiration'], String(at('7:15') / 1000));
    assert.equal(requests[0].init.body, JSON.stringify({ aps: { event: 'start' } }));
  });
});

describe('the API', () => {
  test('stores the push-to-start token with the registration, and keeps it when left out', async () => {
    const base = `/v1/installations/${INSTALLATION}`;
    assert.equal((await call(api, 'PUT', base, { deviceToken: TOKEN, timeFormat: '12h', startToken: START_TOKEN.toUpperCase() })).status, 204);
    assert.equal((await call(api, 'PUT', base, { deviceToken: TOKEN, timeFormat: '24h' })).status, 204);
    assert.deepEqual(await db.prepare('SELECT * FROM start_tokens').first(), { installation_id: INSTALLATION, token: START_TOKEN });
    assert.deepEqual(await call(api, 'PUT', base, { deviceToken: TOKEN, timeFormat: '12h', startToken: 'xyz' }), { status: 400, json: { error: 'invalid', field: 'startToken' } });
  });

  test('an activity report needs a registered installation and good fields', async () => {
    assert.deepEqual(await report({ token: ACTIVITY_TOKEN }), { status: 404, json: { error: 'unknownInstallation' } });
    await setUp();
    assert.deepEqual(await report({ token: 'no' }), { status: 400, json: { error: 'invalid', field: 'token' } });
    assert.deepEqual(await report({ serviceDate: 'today' }), { status: 400, json: { error: 'invalid', field: 'serviceDate' } });
    assert.deepEqual(await report({ handedOff: 'yes' }), { status: 400, json: { error: 'invalid', field: 'handedOff' } });
    assert.equal((await call(api, 'GET', `/v1/installations/${INSTALLATION}/activities`)).status, 405);
  });

  test('deleting the installation deletes its tokens and activities', async () => {
    await setUp();
    await report({ token: ACTIVITY_TOKEN });
    assert.equal((await call(api, 'DELETE', `/v1/installations/${INSTALLATION}`)).status, 204);
    assert.equal(await db.prepare('SELECT * FROM start_tokens').first(), null);
    assert.equal(await db.prepare('SELECT * FROM activities').first(), null);
  });
});
