// The before-departure Live Activity (TT-178, acceptance criterion 1; TT-205's one card): start, update and end payloads at the right times,
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
  assert.equal((await saveRule({}, 'r1', installation)).status, 200);
}

/** Saves the alert on the 7:13 as the app does; `changes` make it paused or repeating. */
function saveRule(changes: Record<string, unknown> = {}, id = 'r1', installation = INSTALLATION) {
  return call(api, 'PUT', `/v1/installations/${installation}/rules/${id}`, {
    kind: 'trip',
    tripId: '20261109-LW-1256',
    serviceDate: '20261109',
    line: 'LW',
    scheduledDeparture: new Date(at('7:13')).toISOString(),
    origin: { id: 'OA', name: 'Oakville GO' },
    destination: { id: 'UN', name: 'Union Station GO' },
    ...changes,
  });
}

/** The bell turned off, or Remove alert. */
const deleteRule = (id = 'r1', installation = INSTALLATION) => call(api, 'DELETE', `/v1/installations/${installation}/rules/${id}`);

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
  test('starts once at T−30 with the alert, updates on a change, asks once the train left, ends 10 min later', async () => {
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
    assert.deepEqual(start.alert, { title: '7:13 AM departs in 30 min', body: '', sound: 'default' });
    assert.deepEqual(start['content-state'], {
      phase: 'countingDown',
      title: '7:13 AM departs in',
      countdownEnd: at('7:13') / 1000,
      minutes: '30 min',
      now: '',
      label: 'Platform',
      late: false,
      position: 0,
      isClose: false,
      updated: 'Updated 6:43 AM',
    });
    assert.equal(start['stale-date'], at('7:23') / 1000, 'Stale, and ended by the app, 10 min after it left');
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
    assert.equal(delayed['content-state'].title, '7:17 AM departs in', 'The expected time');
    assert.equal(delayed['content-state'].delay, '4 min late');
    assert.equal(delayed['content-state'].late, true);
    assert.equal(delayed['content-state'].countdownEnd, at('7:17') / 1000);
    assert.equal(delayed['content-state'].minutes, '26 min');
    assert.equal(delayed['stale-date'], at('7:27') / 1000);
    // Whole minutes, no seconds (TT-219): each new minute sends an update, the same look nothing.
    const [minute] = await cycle('6:52:00', delayFeed('6:52', 4));
    assert.equal(minute.event, 'update');
    assert.equal(minute['content-state'].minutes, '25 min');
    assert.deepEqual(await cycle('6:52:00', delayFeed('6:52', 4)), [], 'The same look sends nothing');

    const [boarding] = await cycle('7:15:30', delayFeed('7:15', 4));
    assert.equal(boarding['content-state'].phase, 'boarding');
    assert.equal(boarding['content-state'].title, '7:17 AM boarding now');
    assert.equal(boarding['content-state'].isClose, true);
    assert.equal(boarding['content-state'].delay, '4 min late');
    assert.equal(boarding['content-state'].minutes, '1 min');

    // TT-231: the train has left, so the card asks "On board?", with an alert; no notification as well.
    const [asking] = await cycle('7:17:30', delayFeed('7:17', 4));
    assert.equal(asking.event, 'update');
    assert.equal(asking['content-state'].phase, 'departed', 'A phase every app build reads');
    assert.equal(asking['content-state'].asks, true);
    assert.equal(asking['content-state'].title, '7:17 AM departed');
    assert.equal(asking['content-state'].label, '', 'Nothing at the right');
    assert.equal(asking['content-state'].countdownEnd, undefined);
    assert.equal(asking['content-state'].minutes, undefined);
    assert.equal(asking['content-state'].delay, undefined);
    assert.equal(asking['content-state'].late, false);
    assert.deepEqual(asking.alert, { title: 'On the 7:13 AM train?', body: '', sound: 'default' }, 'Lights the screen, one buzz');
    assert.equal(asking['stale-date'], at('7:27') / 1000);
    assert.equal(apns.pushes.filter((push) => push.category === 'depart.question').length, 0, 'With a card, no notification');

    assert.deepEqual(await cycle('7:20:00', delayFeed('7:20', 4)), [], 'Asked once');
    const [end] = await cycle('7:27:00', delayFeed('7:27', 4));
    assert.equal(end.event, 'end', 'No answer: gone 10 min after it left');
    assert.equal(end['content-state'].asks, undefined, 'Its last look is Departed, no question');
    assert.equal(end['dismissal-date'], at('7:27') / 1000);
    assert.deepEqual(await cycle('7:28:00', delayFeed('7:28', 4)), [], 'Ended once');
  });

  test('No on the card: nothing more is sent, no notification', async () => {
    await setUp();
    await cycle('6:43:00');
    await report({ token: ACTIVITY_TOKEN });
    const [asking] = await cycle('7:13:30');
    assert.equal(asking['content-state'].asks, true);
    assert.equal((await report({ handedOff: true })).status, 204, 'The app reports the No as it reports a hand-off');
    assert.deepEqual(await cycle('7:23:00'), [], 'No end push: the intent ended it');
    assert.equal(apns.pushes.length, 0);
  });

  test('the app was in front as the train left: the question comes with no alert and no notification, and still ends', async () => {
    await setUp();
    await cycle('6:43:00');
    await report({ token: ACTIVITY_TOKEN });
    assert.equal((await report({ asked: true })).status, 204);
    const [boarding] = await cycle('7:11:30');
    assert.equal(boarding['content-state'].phase, 'boarding', 'Updates go on');
    const [asking] = await cycle('7:13:30');
    assert.equal(asking['content-state'].asks, true);
    assert.equal(asking.alert, undefined, 'Silent');
    assert.equal(apns.pushes.length, 0);
    const [end] = await cycle('7:23:00');
    assert.equal(end.event, 'end');

    // With no card either, nothing is sent at all.
    db = memoryD1();
    apns = new FakeApns();
    await saveSampleTimetables(db, ['20261109']);
    await setUp(INSTALLATION, null);
    await report({ asked: true });
    assert.deepEqual(await cycle('7:13:30'), []);
    assert.equal(apns.pushes.length, 0);
  });

  test('no card (no push-to-start token): the question goes once as a notification', async () => {
    await setUp(INSTALLATION, null);
    assert.deepEqual(await cycle('6:43:00'), []);
    assert.deepEqual(await cycle('7:12:59'), []);
    assert.equal(apns.pushes.length, 0, 'Not before it leaves');
    await cycle('7:13:00');
    assert.equal(apns.pushes.length, 1);
    const push = apns.pushes[0];
    assert.equal(push.title, 'On the 7:13 AM train?');
    assert.equal(push.body, '');
    assert.equal(push.category, 'depart.question');
    assert.deepEqual(push.data, { tripId: '20261109-LW-1256', serviceDate: '20261109', originId: 'OA', destinationId: 'UN', kind: 'departure' });
    assert.equal(push.expiration, at('7:23'), 'Gone with the question');
    await cycle('7:14:00');
    assert.equal(apns.pushes.length, 1, 'Once');
  });

  test('a card the server cannot reach (no update token): the question goes as a notification', async () => {
    await setUp();
    await cycle('6:43:00');
    assert.deepEqual(await cycle('7:13:30'), []);
    assert.equal(apns.pushes.length, 1);
    assert.equal(apns.pushes[0].category, 'depart.question');
    await cycle('7:14:30');
    assert.equal(apns.pushes.length, 1);
  });

  test('the app’s ride took it over: nothing more is sent', async () => {
    await setUp();
    await cycle('6:43:00');
    await report({ token: ACTIVITY_TOKEN });
    assert.equal((await report({ handedOff: true })).status, 204);
    assert.deepEqual(await cycle('7:11:30'), [], 'No Boarding now');
    assert.deepEqual(await cycle('7:15:30'), [], 'No question');
    assert.deepEqual(await cycle('7:23:30'), [], 'No end');
    assert.equal(apns.pushes.length, 0);
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
    assert.equal(first['content-state'].minutes, '29 min');
    const [next] = await cycle('6:45:00');
    assert.equal(next['content-state'].minutes, '28 min', 'The next minute');
    assert.deepEqual(await cycle('6:45:00'), []);
  });

  test('no push-to-start token (iOS 17.0 and 17.1, or not yet sent): no activity starts', async () => {
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
    assert.equal(start.alert.title, '07:13 departs in 30 min');
    assert.equal(start['content-state'].title, '07:13 departs in');
  });
});

describe('a card whose alert is gone (TT-240)', () => {
  const OTHER_TOKEN = 'd'.repeat(160);
  const rows = () => db.prepare('SELECT COUNT(*) AS n FROM activities').first<{ n: number }>().then((row) => row!.n);

  /** The server's card for the 7:13 is up, its token is in and a cycle has updated it. */
  async function cardUp() {
    await setUp();
    await cycle('6:43:00');
    await report({ token: ACTIVITY_TOKEN });
    assert.equal((await cycle('6:44:00'))[0].event, 'update');
  }

  test('the alert removed: the card ends within a cycle, once, and its row goes', async () => {
    await cardUp();
    assert.equal((await deleteRule()).status, 204);
    const [end] = await cycle('6:45:00');
    assert.equal(end.event, 'end', 'No rule watches the train, so no cycle would update the card again');
    assert.equal(apns.activityPushes.at(-1)!.token, ACTIVITY_TOKEN);
    assert.equal(end['dismissal-date'], at('6:45') / 1000, 'It leaves the Lock Screen now');
    assert.equal(end['content-state'].phase, 'departed');
    assert.equal(end['content-state'].title, '7:13 AM departs in', 'The line it last showed');
    assert.equal(await rows(), 0);
    assert.deepEqual(await cycle('6:46:00'), [], 'Ended once');
    assert.equal(apns.pushes.length, 0, 'No notification');
  });

  test('the alert switched off (paused): the same end', async () => {
    await cardUp();
    assert.equal((await saveRule({ paused: true })).status, 200);
    const [end] = await cycle('6:45:00');
    assert.equal(end.event, 'end');
    assert.equal(await rows(), 0);
    assert.deepEqual(await cycle('6:46:00'), []);
  });

  test('switched on again inside its window: a fresh card starts and is followed', async () => {
    await cardUp();
    await deleteRule();
    await cycle('6:45:00');
    assert.equal((await saveRule()).status, 200, 'Undo, or the bell again');
    const [start] = await cycle('6:46:00');
    assert.equal(start.event, 'start');
    assert.equal(start['content-state'].minutes, '27 min');
    await report({ token: OTHER_TOKEN });
    const [update] = await cycle('6:47:00');
    assert.equal(update.event, 'update');
    assert.equal(apns.activityPushes.at(-1)!.token, OTHER_TOKEN);
  });

  test('Undo before the next cycle: the card the app started again takes the row over, and nothing ends', async () => {
    await cardUp();
    await deleteRule();
    await saveRule();
    await report({ token: OTHER_TOKEN });
    const [update] = await cycle('6:45:00');
    assert.equal(update.event, 'update');
    assert.equal(apns.activityPushes.at(-1)!.token, OTHER_TOKEN);
  });

  test('a train another alert still covers keeps its updates', async () => {
    await cardUp();
    // A Repeat alert for the same usual train on Mondays: the two share one watch.
    assert.equal((await saveRule({ kind: 'repeat', weekdays: [1] }, 'r2')).status, 200);
    await deleteRule('r1');
    const [update] = await cycle('6:45:00');
    assert.equal(update.event, 'update');
    assert.equal(update['content-state'].minutes, '28 min');
    assert.equal(await rows(), 1);
  });

  test('a card the app started and no cycle followed yet (bell on and off within the minute) ends too', async () => {
    await setUp();
    await report({});
    await report({ token: ACTIVITY_TOKEN });
    await deleteRule();
    const [end] = await cycle('6:45:00');
    assert.equal(end.event, 'end');
    assert.equal(end['content-state'].phase, 'departed');
    assert.equal(await rows(), 0);
  });

  test('cards no rule here ever watched are left alone: the demo departure, another route’s', async () => {
    await setUp();
    const demo = { tripId: 'DEMO-LW-1713', originId: 'UN', destinationId: 'CL', token: OTHER_TOKEN };
    assert.equal((await report(demo)).status, 204);
    assert.deepEqual(await cycle('6:30:00'), [], 'Reported by the app, never followed by a cycle');
    // Removing the alert on the 7:13 from Oakville releases only cards between its stations.
    await deleteRule();
    assert.deepEqual(await cycle('6:45:00'), []);
    assert.equal(await rows(), 1);
  });

  test('a card the ride took over, or answered No, is left alone', async () => {
    await cardUp();
    await report({ handedOff: true });
    await deleteRule();
    assert.deepEqual(await cycle('6:45:00'), [], 'It is the ride’s card now');
    assert.deepEqual(await db.prepare('SELECT token, state FROM activities').first(), { token: ACTIVITY_TOKEN, state: 'handedOff' });
  });

  test('an end APNs cannot take for a while is sent again the next minute', async () => {
    await cardUp();
    await deleteRule();
    apns.answers.push('retry');
    assert.equal((await cycle('6:45:00'))[0].event, 'end');
    assert.equal(await rows(), 1, 'Kept for the next cycle');
    assert.equal((await cycle('6:46:00'))[0].event, 'end');
    assert.equal(await rows(), 0);
  });

  test('the ends stay inside the cycle’s APNs calls', async () => {
    const riders = Array.from({ length: MAX_SENDS + 3 }, (_, i) => `6f1c2a9e-3b4d-4c5e-9f60-${String(i).padStart(12, '0')}`);
    for (const rider of riders) await setUp(rider);
    await cycle('6:43:00');
    await cycle('6:44:00');
    for (const rider of riders) {
      await report({ token: ACTIVITY_TOKEN }, rider);
      await deleteRule('r1', rider);
    }
    assert.equal((await cycle('6:45:00')).length, MAX_SENDS);
    assert.equal((await cycle('6:46:00')).length, 3);
    assert.equal((await cycle('6:47:00')).length, 0);
  });

  test('an ended card stays ended, until the app reports another token for the train', async () => {
    await cardUp();
    // APNs says the card is gone (swiped away, or the app ended it): the server stops.
    apns.answers.push('unregistered');
    await cycle('6:45:00');
    assert.deepEqual(await cycle('6:46:00'), []);
    await report({ token: ACTIVITY_TOKEN });
    assert.deepEqual(await cycle('6:47:00'), [], 'The same token: the same card, still gone');
    // The alert was switched on again and the app started a new card: it gets the server's updates.
    await report({ token: OTHER_TOKEN });
    const [update] = await cycle('6:48:00');
    assert.equal(update.event, 'update');
    assert.equal(apns.activityPushes.at(-1)!.token, OTHER_TOKEN);
  });
});

describe('the rules', () => {
  const train: Departure = { scheduled: at('7:13'), scheduledArrival: at('7:47'), status: null, origin: 'Oakville GO', destination: 'Union Station GO' };

  test('the window: 30 min before, Boarding now for the last 2, the question for 10 after or to your stop', () => {
    assert.equal(phaseAt(train, at('6:42:59')), 'before');
    assert.equal(phaseAt(train, at('6:43')), 'countingDown');
    assert.equal(phaseAt(train, at('7:10:59')), 'countingDown');
    assert.equal(phaseAt(train, at('7:11')), 'boarding');
    assert.equal(phaseAt(train, at('7:13')), 'asking', 'At the departure, not before');
    assert.equal(phaseAt(train, at('7:22:59')), 'asking');
    assert.equal(phaseAt(train, at('7:23')), 'over');
    const short = { ...train, scheduledArrival: at('7:19') };
    assert.equal(phaseAt(short, at('7:18:59')), 'asking');
    assert.equal(phaseAt(short, at('7:19')), 'over', 'At your stop if sooner');
    const late = { ...train, status: { kind: 'running' as const, delayMin: 4, expected: at('7:17'), reportedAt: at('7:00') } };
    assert.equal(phaseAt(late, at('6:46:30')), 'before', 'From the expected departure');
    assert.equal(phaseAt(late, at('6:47')), 'countingDown');
    assert.equal(phaseAt(late, at('7:16:59')), 'boarding', 'A delayed train asks at its expected time');
    assert.equal(phaseAt(late, at('7:17')), 'asking');
    assert.equal(phaseAt(late, at('7:27')), 'over');
    assert.equal(phaseAt({ ...train, status: { kind: 'skipped', stop: 'destination', reportedAt: at('7:00') } }, at('7:00')), 'over');
  });

  test('on time with live data, a small lateness, the minutes, and the update time does not count as a change', () => {
    const onTime = { ...train, status: { kind: 'running' as const, delayMin: 1, expected: at('7:14'), reportedAt: at('7:00') } };
    const state = contentState(onTime, 'countingDown', at('7:00'), '12h');
    assert.equal(state.title, '7:14 AM departs in', 'The expected time, not late under 3 min');
    assert.equal(state.delay, undefined);
    assert.equal(state.late, false);
    assert.equal(state.countdownEnd, at('7:14') / 1000);
    assert.equal(state.minutes, '14 min');
    assert.equal(signature(state), signature({ ...state, updated: 'Updated 7:01 AM' }));
    assert.notEqual(signature(state), signature(contentState(onTime, 'countingDown', at('7:01'), '12h')), 'A new minute');
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
    assert.deepEqual(await report({ asked: 'yes' }), { status: 400, json: { error: 'invalid', field: 'asked' } });
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
