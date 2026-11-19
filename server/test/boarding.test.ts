// Boarding at the platform (TT-233, D114, acceptance criterion 4): the server's port of the app's `BoardingRule`, case
// for case from `Tests/UnitTests/Core/BoardingRuleTests.swift`, and the minute cycle's Live Activity following it:
// boarding from the train's position, "Departing" past its time, the question when it moves off, the clock with no fresh
// position, and the reads kept inside the Free plan.

import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';
import { boardingPhase, contentState, hasSighting, phaseAt, signature, type BoardingPhase, type Departure } from '../src/activity.ts';
import { handleRequest } from '../src/api.ts';
import worker, { type Env } from '../src/index.ts';
import { BOARD_STATIONS, MAX_SENDS, metresBetween, monitor } from '../src/monitor.ts';
import type { PlatformBoard } from '../src/platforms.ts';
import type { Feed, LiveStatus, TrainPosition } from '../src/realtime.ts';
import { STATIONS } from '../src/stations.ts';
import { at, call, FakeApns, feedMessage, INSTALLATION, memoryD1, saveSampleTimetables, TOKEN, vehicle as vehicleEntity } from './support.ts';

const waiting: BoardingPhase = { kind: 'waiting' };
const boarding: BoardingPhase = { kind: 'boarding' };
const departed = (source: 'moved' | 'feed' | 'clock'): BoardingPhase => ({ kind: 'departed', source });

const START_TOKEN = 'b'.repeat(160);
const ACTIVITY_TOKEN = 'c'.repeat(160);
const rider = (i: number) => `6f1c2a9e-3b4d-4c5e-9f60-${String(i).padStart(12, '0')}`;

/** Registers with a push-to-start token and arms a This-trip alert on a Lakeshore West train to Union on Nov 9. */
async function armRider(api: (request: Request) => Promise<Response>, installation: string, trip: string, departure: string, origin: string) {
  assert.equal((await call(api, 'PUT', `/v1/installations/${installation}`, { deviceToken: TOKEN, timeFormat: '12h', startToken: START_TOKEN })).status, 204);
  const rule = await call(api, 'PUT', `/v1/installations/${installation}/rules/${trip}`, {
    kind: 'trip',
    tripId: `20261109-${trip}`,
    serviceDate: '20261109',
    line: 'LW',
    scheduledDeparture: new Date(at(departure)).toISOString(),
    origin: { id: origin, name: `${origin} GO` },
    destination: { id: 'UN', name: 'Union Station GO' },
  });
  assert.equal(rule.status, 200);
}

describe('the rule, case for case with the app’s BoardingRuleTests', () => {
  interface Said {
    /** `onTime` and `delayed` carry an estimate, as the app's statuses do; null is the timetable alone. */
    status?: 'onTime' | 'delayed' | 'cancelled' | 'skipped' | null;
    delay?: number;
    platform?: string | null;
    metres?: number;
    seen?: string;
    hasLeftOrigin?: boolean;
  }

  /** The 5:58 PM train, with what the feeds say about it at `seen`. */
  function train({ status = 'onTime', delay = 0, platform = '12', metres, seen = '17:50', hasLeftOrigin = false }: Said = {}): Departure {
    const scheduled = at('17:58');
    const live: Record<'onTime' | 'delayed' | 'cancelled' | 'skipped', LiveStatus> = {
      onTime: { kind: 'running', delayMin: delay, expected: scheduled + delay * 60_000, reportedAt: at('17:50') },
      delayed: { kind: 'running', delayMin: delay, expected: scheduled + delay * 60_000, reportedAt: at('17:50') },
      cancelled: { kind: 'cancelled', reportedAt: at('17:30') },
      skipped: { kind: 'skipped', stop: 'origin', reportedAt: at('17:30') },
    };
    return {
      scheduled,
      scheduledArrival: scheduled + 30 * 60_000,
      status: status === null ? null : live[status],
      origin: 'Union Station GO',
      destination: 'Clarkson GO',
      position: metres === undefined ? null : { metres, at: at(seen) },
      hasLeftOrigin,
      platform,
    };
  }

  const phase = (departure: Departure, time: string) => boardingPhase(departure, at(time));

  test('a train at the station with its platform posted is boarding', () => {
    assert.deepEqual(phase(train({ metres: 150, seen: '17:43' }), '17:43:20'), boarding, '15 min before');
    assert.deepEqual(phase(train({ metres: 350, seen: '17:50' }), '17:50:05'), boarding, '350 m is still at the station');
  });

  test('it stays boarding past its time while it stands there', () => {
    assert.deepEqual(phase(train({ metres: 120, seen: '17:58:30' }), '17:58:40'), boarding);
    assert.deepEqual(phase(train({ metres: 120, seen: '18:04' }), '18:04:10'), boarding, '6 min past, still there');
  });

  test('with no platform posted it is not boarding, and not departed while it stands there', () => {
    assert.deepEqual(phase(train({ platform: null, metres: 120, seen: '17:32' }), '17:32:10'), waiting, '26 min before, at Union before its platform is posted');
    assert.deepEqual(phase(train({ platform: null, metres: 120, seen: '17:59' }), '17:59:10'), waiting, 'past its time');
  });

  test('a late train boards against its expected time', () => {
    assert.deepEqual(phase(train({ status: 'delayed', delay: 5, metres: 140, seen: '18:01' }), '18:01:10'), boarding);
    const away = train({ status: 'delayed', delay: 5, metres: 2_000, seen: '18:01' });
    assert.deepEqual(phase(away, '18:01:10'), waiting, 'past the timetable, 2 min before its expected time, not here yet');
    assert.deepEqual(phase(away, '18:03'), departed('moved'));
  });

  test('it has left when its position is away once its time has come', () => {
    assert.deepEqual(phase(train({ metres: 351, seen: '17:58' }), '17:58'), departed('moved'));
    assert.deepEqual(phase(train({ metres: 900, seen: '17:58:20' }), '17:58:30'), departed('moved'));
  });

  test('a far position in the minute before its time is a train still rolling in', () => {
    assert.deepEqual(phase(train({ metres: 900, seen: '17:57:20' }), '17:57:30'), waiting);
    assert.deepEqual(phase(train({ metres: 900, seen: '17:40' }), '17:40:10'), waiting);
  });

  test('the feed dropping the station is a departure from a minute before its time', () => {
    assert.deepEqual(phase(train({ hasLeftOrigin: true }), '17:56:59'), waiting, 'too early to be this train leaving');
    assert.deepEqual(phase(train({ hasLeftOrigin: true }), '17:57'), departed('feed'));
    assert.deepEqual(
      phase(train({ metres: 200, seen: '17:58:20', hasLeftOrigin: true }), '17:58:30'),
      departed('feed'),
      'the feed comes first, though the position is still within 350 m',
    );
  });

  test('with no position it follows the clock', () => {
    assert.deepEqual(phase(train(), '17:57:59'), waiting);
    assert.deepEqual(phase(train(), '17:58'), departed('clock'));
    assert.equal(hasSighting(train(), at('17:50')), false);
  });

  test('a position older than 2 min says nothing', () => {
    const stale = train({ metres: 120, seen: '17:50' });
    assert.deepEqual(phase(stale, '17:52'), boarding, '2 min old');
    assert.deepEqual(phase(stale, '17:52:01'), waiting, 'never boarding on a guess');
    assert.equal(hasSighting(stale, at('17:52:01')), false);
    assert.deepEqual(phase(train({ metres: 120, seen: '17:57' }), '18:08'), departed('clock'), '10 min past with no fresh position');
    assert.deepEqual(phase(train({ metres: 900, seen: '17:55' }), '17:58:10'), departed('clock'), 'a stale far position is the clock');
  });

  test('cancelled and skipped trains never board', () => {
    const cancelled = train({ status: 'cancelled', metres: 120, seen: '17:50' });
    assert.deepEqual(phase(cancelled, '17:50:10'), waiting);
    assert.deepEqual(phase(cancelled, '17:58'), departed('clock'));
    assert.deepEqual(phase(train({ status: 'skipped', metres: 120, seen: '17:59' }), '17:59:10'), departed('clock'), 'standing there does not hold a skipped stop');
  });

  test('a timetable-only train boards on its position too', () => {
    assert.deepEqual(phase(train({ status: null, metres: 120, seen: '17:50' }), '17:50:10'), boarding);
  });

  // The activity's phases, as the app's `LiveDeparture` takes them from the rule (`LiveDepartureTests`).
  test('the activity: boarding is the train standing there, also past its time, and the window still ends', () => {
    const standing = (seen: string, said: Said = {}) => train({ metres: 150, seen, ...said });
    assert.equal(phaseAt(standing('17:43'), at('17:43:10')), 'boarding', '15 min before, at its platform');
    assert.equal(phaseAt(standing('17:59'), at('17:59:10')), 'boarding', 'past its time');
    assert.equal(phaseAt(standing('18:08'), at('18:08')), 'over', 'the window ends 10 min after its time though the train stands');
    assert.equal(phaseAt(train({ metres: 2_000, seen: '17:56:30' }), at('17:56:40')), 'countingDown', 'with a position the last 2 min are not boarding by the clock');
    const noPlatform = { platform: null };
    assert.equal(phaseAt(standing('17:56:30', noPlatform), at('17:56:40')), 'countingDown', 'no platform, no boarding');
    assert.equal(phaseAt(standing('17:56:30', noPlatform), at('17:58:30')), 'countingDown', 'past its time and still there');
    assert.equal(phaseAt(standing('17:56:30', noPlatform), at('17:58:31')), 'asking', 'the position went stale: the clock again');
    assert.equal(phaseAt(train({ metres: 800, seen: '17:58:20' }), at('17:58:30')), 'asking', 'it moved off');
    assert.equal(phaseAt(standing('17:57:20', { hasLeftOrigin: true }), at('17:57:30')), 'asking', 'the feed’s word counts from 1 min before');
    assert.equal(phaseAt(train({ metres: 150, seen: '17:20' }), at('17:27:59')), 'before', 'no position opens the window');
  });

  test('the activity’s words: "Departing" once its time has come, the platform in its pill, and old signatures still match', () => {
    const standing = train({ metres: 150, seen: '17:59', platform: '3' });
    const past = contentState(standing, 'boarding', at('17:59:10'), '12h');
    assert.equal(past.title, '5:58 PM boarding now');
    assert.equal(past.minutes, 'Departing', 'never "1 min" for a train past its time');
    assert.equal(past.countdownEnd, at('17:58') / 1000);
    assert.equal(past.platformNumber, '3');
    assert.equal(past.isClose, true);
    const before = contentState(standing, 'boarding', at('17:57:59'), '12h');
    assert.equal(before.minutes, '1 min');
    assert.notEqual(signature(before), signature(past));
    // A posted platform is a new look; without one the signature is the one stored before TT-233.
    const plain = contentState({ ...standing, platform: null }, 'boarding', at('17:59:10'), '12h');
    assert.equal(plain.platformNumber, undefined, 'the dash');
    assert.equal(signature(plain), `boarding|5:58 PM boarding now||${Math.round(at('17:58') / 30_000)}|Departing|`);
    assert.equal(signature(past), `${signature(plain)}|platform 3`);
    // The question and the last look carry no platform and no minutes.
    const asking = contentState(standing, 'asking', at('18:00'), '12h');
    assert.equal(asking.platformNumber, undefined);
    assert.equal(asking.minutes, undefined);
    assert.equal(signature(asking), 'departed|5:58 PM departed||||asks');
  });
});

describe('the minute cycle', () => {
  let db: D1Database;
  let apns: FakeApns;
  /** What the cycles read: how often the train positions, and which stations' boards. */
  let reads: { positions: number; boards: string[] };
  const api = (request: Request) => handleRequest(request, db, at('6:30'));

  /** An alerted rider: by default on the 7:13 AM from Oakville to Union (LW-1256). */
  const arm = (installation = INSTALLATION, trip = 'LW-1256', departure = '7:13', origin = 'OA') => armRider(api, installation, trip, departure, origin);

  /** The app reports the 7:13's activity: its update token, or that its ride took it over. */
  function report(body: Record<string, unknown>) {
    return call(api, 'PUT', `/v1/installations/${INSTALLATION}/activities`, { tripId: '20261109-LW-1256', serviceDate: '20261109', originId: 'OA', destinationId: 'UN', ...body });
  }

  /** The 7:13 with its card started at T−30 and its update token in. */
  async function started() {
    await arm();
    assert.equal((await cycle('6:43:00'))[0].event, 'start');
    assert.equal((await report({ token: ACTIVITY_TOKEN })).status, 204);
  }

  /** A train as GO's train feed places it: `metres` north of a station's stop point, reported at `seen`. */
  function vehicle(metres: number, seen: string, trip = 'LW-1256', station = 'OA', extra: Partial<TrainPosition> = {}): TrainPosition {
    const [latitude, longitude] = STATIONS[station];
    return { tripId: `20261109-${trip}`, startDate: '20261109', latitude: latitude + metres / 111_195.08, longitude, stopped: metres < 350, timestamp: at(seen), ...extra };
  }

  interface Said {
    feed?: Feed | null;
    trains?: TrainPosition[];
    /** The platform every station's board posts for the trains, by GO trip number; null for a board with none posted. */
    platform?: string | null;
  }

  /** One cycle at `time` with what GO says; returns the Live Activity pushes sent, as their `aps`. */
  async function cycle(time: string, { feed = null, trains, platform = null }: Said = {}): Promise<any[]> {
    const before = apns.activityPushes.length;
    const board: PlatformBoard = { fetchedAt: at(time) / 1000, trips: ['1256', '1108', '1858'].map((trip) => ({ trip, line: 'LW', platform })) };
    await monitor({
      db,
      apns,
      feed: async () => feed,
      positions: async () => {
        reads.positions++;
        return trains ? { timestamp: at(time), trains } : null;
      },
      platforms: async (stop) => {
        reads.boards.push(stop);
        return board;
      },
      now: at(time),
    });
    return apns.activityPushes.slice(before).map((push) => (push.payload as { aps: unknown }).aps);
  }

  /** GO's feed once the train has left Oakville: only the stops still ahead (D89). */
  const pastOakville = (time: string): Feed => ({
    timestamp: at(time),
    tripUpdates: [
      { tripId: '20261109-LW-1256', startDate: '20261109', cancelled: false, timestamp: at(time), stopTimeUpdates: ['CL', 'UN'].map((stopId) => ({ stopId, relationship: 'scheduled' as const, departure: { delay: 0 } })) },
    ],
  });

  const questions = () => apns.pushes.filter((push) => push.category === 'depart.question').length;

  beforeEach(async () => {
    db = memoryD1();
    apns = new FakeApns();
    reads = { positions: 0, boards: [] };
    await saveSampleTimetables(db, ['20261109']);
  });

  test('boarding from the train’s position 15 min before, with its platform', async () => {
    await started();
    const [update] = await cycle('6:58:10', { trains: [vehicle(150, '6:57:50')], platform: '3' });
    assert.equal(update.event, 'update');
    assert.deepEqual(update['content-state'], {
      phase: 'boarding',
      title: '7:13 AM boarding now',
      countdownEnd: at('7:13') / 1000,
      minutes: '14 min',
      platformNumber: '3',
      now: '',
      label: 'Platform',
      late: false,
      position: 0,
      isClose: true,
      updated: 'Updated 6:58 AM',
    });
    assert.equal(update.alert, undefined);
    assert.equal(update['stale-date'], at('7:23') / 1000, 'The window ends as before');
    assert.deepEqual(reads.boards, ['OA'], 'The board of the station it stands at');
    assert.deepEqual(await cycle('6:58:40', { trains: [vehicle(150, '6:58:20')], platform: '3' }), [], 'The same look sends nothing');
    const [next] = await cycle('6:59:10', { trains: [vehicle(160, '6:58:50')], platform: '3' });
    assert.equal(next['content-state'].phase, 'boarding');
    assert.equal(next['content-state'].minutes, '13 min');
  });

  test('past its time and still there: boarding now over "Departing"; the question when it moves off, once, as TT-231 built it', async () => {
    await started();
    const standing = (seen: string) => ({ trains: [vehicle(150, seen)], platform: '3' });
    await cycle('7:12:30', standing('7:12:20'));
    const [past] = await cycle('7:13:30', standing('7:13:20'));
    assert.equal(past['content-state'].phase, 'boarding');
    assert.equal(past['content-state'].title, '7:13 AM boarding now');
    assert.equal(past['content-state'].minutes, 'Departing');
    assert.equal(past['content-state'].countdownEnd, at('7:13') / 1000);
    assert.equal(past['content-state'].isClose, true);
    assert.equal(past['content-state'].asks, undefined, 'Not departed while it stands there');
    assert.equal(past.alert, undefined);
    assert.deepEqual(await cycle('7:14:30', standing('7:14:20')), [], 'Still there: the same look');

    const [asking] = await cycle('7:15:30', { trains: [vehicle(800, '7:15:20')], platform: '3' });
    assert.equal(asking.event, 'update');
    assert.equal(asking['content-state'].phase, 'departed');
    assert.equal(asking['content-state'].asks, true);
    assert.equal(asking['content-state'].title, '7:13 AM departed');
    assert.equal(asking['content-state'].label, '');
    assert.equal(asking['content-state'].minutes, undefined);
    assert.equal(asking['content-state'].countdownEnd, undefined);
    assert.equal(asking['content-state'].platformNumber, undefined);
    assert.deepEqual(asking.alert, { title: 'On the 7:13 AM train?', body: '', sound: 'default' });
    assert.equal(asking['stale-date'], at('7:23') / 1000, 'Its end does not move');
    assert.equal(questions(), 0, 'With a card, no notification');

    const read = reads.positions;
    assert.deepEqual(await cycle('7:16:30', standing('7:16:20')), [], 'Asked once, wherever the train is said to be');
    assert.equal(reads.positions, read, 'A card that asks needs no position');
    const [end] = await cycle('7:23:00', { trains: [vehicle(9_000, '7:22:50')] });
    assert.equal(end.event, 'end', '10 min after its time, as before');
    assert.equal(end['content-state'].asks, undefined);
  });

  test('no card once its time has come: none starts, and the question’s notification waits for the train to move off', async () => {
    await arm();
    assert.deepEqual(await cycle('7:13:30', { trains: [vehicle(150, '7:13:20')], platform: '3' }), [], 'No start past its time, as before');
    assert.equal(questions(), 0, 'Past its time, still at the platform');
    await cycle('7:14:30', { trains: [vehicle(600, '7:14:20')], platform: '3' });
    assert.equal(questions(), 1);
    assert.equal(apns.pushes[0].title, 'On the 7:13 AM train?');
    assert.equal(apns.pushes[0].expiration, at('7:23'));
    await cycle('7:15:30', { trains: [vehicle(150, '7:15:20')], platform: '3' });
    assert.equal(questions(), 1, 'Once');
  });

  test('the feed dropping the station is the departure, from 1 min before its time', async () => {
    await started();
    const [early] = await cycle('7:11:30', { feed: pastOakville('7:11:20') });
    assert.equal(early['content-state'].phase, 'boarding', 'Too early to be this train leaving: the clock’s last 2 min');
    assert.equal(early['content-state'].asks, undefined);
    const [asking] = await cycle('7:12:00', { feed: pastOakville('7:11:50') });
    assert.equal(asking['content-state'].asks, true);
    assert.equal(asking['content-state'].title, '7:13 AM departed');
    assert.deepEqual(asking.alert, { title: 'On the 7:13 AM train?', body: '', sound: 'default' });
    // The feed comes first, though a position still places the train at the station.
    db = memoryD1();
    apns = new FakeApns();
    await saveSampleTimetables(db, ['20261109']);
    await started();
    const [first] = await cycle('7:12:30', { feed: pastOakville('7:12:20'), trains: [vehicle(200, '7:12:20')], platform: '3' });
    assert.equal(first['content-state'].asks, true);
  });

  test('a stale position falls back to the clock: boarding for the last 2 min, left at its time', async () => {
    await started();
    const stale = { trains: [vehicle(150, '7:05')], platform: '3' };
    const [counting] = await cycle('7:10:30', stale);
    assert.equal(counting['content-state'].phase, 'countingDown', 'Never boarding on a guess');
    assert.equal(counting['content-state'].platformNumber, undefined);
    const [boardingNow] = await cycle('7:11:00', stale);
    assert.equal(boardingNow['content-state'].phase, 'boarding');
    assert.equal(boardingNow['content-state'].minutes, '2 min');
    const [asking] = await cycle('7:13:00', stale);
    assert.equal(asking['content-state'].asks, true, 'Departed at its time');
    assert.deepEqual(reads.boards, [], 'No board for a train nobody sees');
    // A vehicle on another service date is not this train either.
    db = memoryD1();
    apns = new FakeApns();
    await saveSampleTimetables(db, ['20261109']);
    await started();
    const [other] = await cycle('6:58:00', { trains: [vehicle(150, '6:57:50', 'LW-1256', 'OA', { startDate: '20261108' })], platform: '3' });
    assert.equal(other['content-state'].phase, 'countingDown');
  });

  test('no platform posted: no boarding, and not departed while it stands there', async () => {
    await started();
    const standing = (seen: string) => ({ trains: [vehicle(150, seen)], platform: null });
    const [early] = await cycle('6:58:00', standing('6:57:50'));
    assert.equal(early['content-state'].phase, 'countingDown');
    assert.equal(early['content-state'].isClose, false);
    const [last] = await cycle('7:11:30', standing('7:11:20'));
    assert.equal(last['content-state'].phase, 'countingDown', 'With a position, no boarding by the clock');
    assert.equal(last['content-state'].minutes, '1 min');
    const [past] = await cycle('7:13:30', standing('7:13:20'));
    assert.equal(past['content-state'].phase, 'countingDown');
    assert.equal(past['content-state'].minutes, 'Departing');
    assert.equal(past['content-state'].asks, undefined);
    assert.deepEqual(reads.boards, ['OA', 'OA', 'OA'], 'The board is asked while the train stands there');
  });

  test('a far position in the minute before its time is not a departure; at its time it is', async () => {
    await started();
    const [rolling] = await cycle('7:12:30', { trains: [vehicle(900, '7:12:20')] });
    assert.equal(rolling['content-state'].phase, 'countingDown', 'Still rolling in: not boarding either');
    assert.equal(rolling['content-state'].asks, undefined);
    assert.deepEqual(reads.boards, [], 'No board for a train that is not at the station');
    const [asking] = await cycle('7:13:00', { trains: [vehicle(900, '7:12:50')] });
    assert.equal(asking['content-state'].asks, true);
  });

  test('the positions are read once a cycle, and only while an alerted train is in its activity window', async () => {
    for (const i of [1, 2, 3]) await arm(rider(i));
    await arm(rider(4), 'LW-1108', '7:21');
    await cycle('6:42:30');
    assert.equal(reads.positions, 0, 'Watched, but 30 s before any window');
    assert.equal((await cycle('6:43:00')).length, 3);
    assert.equal(reads.positions, 1, 'Three riders in their window: one read');
    await cycle('7:00:00');
    assert.equal(reads.positions, 2, 'Two trains in their windows: one read');
    await cycle('7:32:00');
    assert.equal(reads.positions, 2, 'Both windows over: none, though the trains are still watched for delays');

    // A card the app's ride took over is no longer followed.
    db = memoryD1();
    apns = new FakeApns();
    reads = { positions: 0, boards: [] };
    await saveSampleTimetables(db, ['20261109']);
    await started();
    assert.equal(reads.positions, 1);
    await report({ handedOff: true });
    await cycle('6:50:00');
    assert.equal(reads.positions, 1);
  });

  test(`at most ${BOARD_STATIONS} station boards a cycle: where most riders wait`, async () => {
    // Trains standing at three stations at 7:05: the 7:13 at Oakville (two riders), the 7:15 at Bronte and the 7:16 at Appleby.
    await arm(rider(1));
    await arm(rider(2));
    await arm(rider(3), 'LW-1108', '7:15', 'BO');
    await arm(rider(4), 'LW-1858', '7:16', 'AP');
    const trains = [vehicle(100, '7:04:50'), vehicle(100, '7:04:50', 'LW-1108', 'BO'), vehicle(100, '7:04:50', 'LW-1858', 'AP')];
    const pushes = await cycle('7:05:00', { trains, platform: '2' });
    assert.equal(reads.positions, 1);
    assert.deepEqual(reads.boards, ['OA', 'AP'], 'Oakville first, then one of the others, the same one each minute');
    const phases = pushes.map((push) => `${push.attributes.originId} ${push['content-state'].phase}`).sort();
    assert.deepEqual(phases, ['AP boarding', 'BO countingDown', 'OA boarding', 'OA boarding'], 'A train whose board was not read does not board');
  });

  test('a station the server cannot place follows the clock', async () => {
    // A station missing from the table, and a rule whose station id is no station code at all.
    await arm(rider(1), 'LW-1256', '7:13', 'ZZ');
    await arm(rider(2), 'LW-1256', '7:13', 'constructor');
    const last = await cycle('7:11:30', { trains: [vehicle(150, '7:11:20')], platform: '3' });
    assert.deepEqual(last.map((push) => push['content-state'].phase), ['boarding', 'boarding'], 'The clock’s last 2 min');
    assert.deepEqual(last.map((push) => push['content-state'].platformNumber), [undefined, undefined]);
    assert.deepEqual(reads.boards, []);
  });

  test('metres are the app’s: a flat frame at the mean latitude', () => {
    const [latitude, longitude] = STATIONS.UN;
    assert.ok(Math.abs(metresBetween(STATIONS.UN, [latitude + 220 / 111_195.08, longitude]) - 220) < 0.01);
    assert.ok(Math.abs(metresBetween(STATIONS.UN, [latitude, longitude + 0.005]) - 0.005 * 111_195.08 * Math.cos((latitude * Math.PI) / 180)) < 0.01);
    assert.ok(Math.abs(metresBetween(STATIONS.OA, STATIONS.CL) - 7_520) < 100, 'Oakville to Clarkson, about 7.5 km');
  });
});

describe('the Worker’s cron run', () => {
  test('reads the positions and the boards through the relays, and its outside requests fit the Free plan’s 50', async (t) => {
    const db = memoryD1();
    await saveSampleTimetables(db, ['20261109']);
    const api = (request: Request) => handleRequest(request, db, at('6:30'));
    // More riders than a cycle sends to, on trains standing at three stations at 7:05 (as the board test above).
    const riders = [...Array.from({ length: MAX_SENDS + 3 }, () => ['LW-1256', '7:13', 'OA']), ['LW-1108', '7:15', 'BO'], ['LW-1858', '7:16', 'AP']];
    for (const [i, [trip, departure, origin]] of riders.entries()) await armRider(api, rider(i), trip, departure, origin);

    const keys = (await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign'])) as CryptoKeyPair;
    const pkcs8 = new Uint8Array((await crypto.subtle.exportKey('pkcs8', keys.privateKey)) as ArrayBuffer);
    const env: Env = {
      DB: db,
      APNS_TOPIC: 'ca.traintimes.TrainTimes',
      APNS_KEY: `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8))}\n-----END PRIVATE KEY-----\n`,
      APNS_KEY_ID: 'ABC123DEFG',
      APNS_TEAM_ID: 'TEAM123456',
      GO_FEEDS_URL: 'https://go.example/api/V1/Gtfs/Feed/',
      METROLINX_API_KEY: 'k',
      TIMETABLE_WORKFLOW: '',
    };

    // Everything Cloudflare counts toward the 50: fetch() and the Cache API's calls.
    const outside: string[] = [];
    const starts: any[] = [];
    const cached = new Map<string, Response>();
    (globalThis as { caches?: unknown }).caches = {
      default: {
        match: async (key: string) => {
          outside.push('cache');
          return cached.get(key)?.clone();
        },
        put: async (key: string, response: Response) => {
          outside.push('cache');
          cached.set(key, response);
        },
      },
    };
    t.after(() => delete (globalThis as { caches?: unknown }).caches);
    t.mock.method(Date, 'now', () => at('7:05'));
    const train = (id: string, trip: string, station: string) => {
      const [latitude, longitude] = STATIONS[station];
      return vehicleEntity(id, `20261109-${trip}`, '09261126-LW', latitude + 100 / 111_195.08, longitude, 1, at('7:04:40'));
    };
    const positions = feedMessage(at('7:04:50'), [train('1', 'LW-1256', 'OA'), train('2', 'LW-1108', 'BO'), train('3', 'LW-1858', 'AP')]);
    const board = { NextService: { Lines: ['1256', '1108', '1858'].map((TripNumber) => ({ TripNumber, ServiceType: 'T', LineCode: 'LW', ScheduledPlatform: '', ActualPlatform: '2' })) } };
    t.mock.method(globalThis, 'fetch', async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = new URL(String(input));
      if (url.hostname.endsWith('push.apple.com')) {
        outside.push('APNs');
        starts.push(JSON.parse(String(init!.body)).aps);
        return new Response(null, { status: 200 });
      }
      assert.equal(url.searchParams.get('key'), 'k');
      outside.push(`GO ${url.pathname.split('/').slice(-2).join('/')}`);
      if (url.pathname.endsWith('/Feed/TripUpdates')) return new Response(feedMessage(at('7:04:50')));
      if (url.pathname.endsWith('/Feed/VehiclePosition')) return new Response(positions);
      if (url.pathname.includes('/Stop/NextService/')) return Response.json(board);
      throw new Error(`Unexpected request ${url}`);
    });

    await worker.scheduled({ cron: '* * * * *' } as ScheduledController, env);
    const go = outside.filter((request) => request.startsWith('GO')).sort();
    assert.deepEqual(go, ['GO Feed/TripUpdates', 'GO Feed/VehiclePosition', 'GO NextService/AP', 'GO NextService/OA'], 'Each feed once, two boards');
    assert.equal(outside.filter((request) => request === 'cache').length, 8, 'A match and a put for each');
    assert.equal(starts.length, MAX_SENDS);
    assert.equal(outside.length, MAX_SENDS + 12, 'The sum in the MAX_SENDS comment');
    assert.ok(outside.length <= 50, 'Inside the Free plan');
    // The positions and the boards reached the rule: the Oakville riders' cards start on boarding now with the platform.
    const oakville = starts.filter((aps) => aps.attributes.originId === 'OA');
    assert.ok(oakville.length >= MAX_SENDS - 2);
    for (const aps of oakville) {
      assert.equal(aps.event, 'start');
      assert.equal(aps['content-state'].phase, 'boarding');
      assert.equal(aps['content-state'].title, '7:13 AM boarding now');
      assert.equal(aps['content-state'].platformNumber, '2');
    }

    // The next run in the same isolate within 30 s reads everything from memory: only APNs is called.
    await worker.scheduled({ cron: '* * * * *' } as ScheduledController, env);
    assert.equal(starts.length, riders.length, 'The rest start');
    assert.equal(outside.length, riders.length + 12);
    const bronte = starts.find((aps) => aps.attributes.originId === 'BO');
    assert.equal(bronte['content-state'].phase, 'countingDown', 'The third station’s board was not read: no boarding on a guess');
    assert.equal(starts.find((aps) => aps.attributes.originId === 'AP')['content-state'].phase, 'boarding');
  });
});
