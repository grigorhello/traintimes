// The timetable import, repeating rules (Review needed, No matching train today) and retention.

import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';
import { handleRequest } from '../src/api.ts';
import { applyRetention, monitor } from '../src/monitor.ts';
import { importTimetables, resolveUsualTrain, type Timetable } from '../src/timetable.ts';
import { at, call, FakeApns, INSTALLATION, memoryD1, sampleGTFS, TOKEN } from './support.ts';

const H = 3600;
/** A one-trip timetable: the Lakeshore West train leaving Oakville at `departure`. */
const timetable = (trip: string, departure: number): Timetable => ({
  [trip]: { line: 'LW', stops: ['AL', 'OA', 'UN'], arrivals: [departure - 600, departure, departure + 2040], departures: [departure - 600, departure, departure + 2040] },
});
const usual = { line: 'LW', origin: 'OA', destination: 'UN', departure: 7 * H + 13 * 60, weekdays: [1, 2, 3, 4, 5] };

test('imports the rail trips running on each date from the GTFS zip', async () => {
  const timetables = await importTimetables(sampleGTFS(), ['20261109', '20261127', '20261110']);
  const monday = timetables.get('20261109')!;
  const trip = monday['20261109-LW-1256'];
  assert.equal(trip.line, 'LW');
  assert.equal(trip.stops.at(-1), 'UN');
  assert.equal(trip.departures[trip.stops.indexOf('OA')], 7 * H + 13 * 60);
  assert.ok(Object.keys(monday).every((id) => id.startsWith('20261109-')), 'only that date’s trips');
  assert.ok(!('20261109-21-1234' in monday), 'no bus trips');
  assert.ok(Object.values(monday).some((t) => t.line === 'KI'));
  assert.ok('20261127-LW-1256' in timetables.get('20261127')!);
  assert.deepEqual(timetables.get('20261110'), {}, 'a date the feed does not cover');
});

describe('resolving a repeating rule', () => {
  const week: Record<string, Timetable> = {
    '20261109': timetable('20261109-LW-1256', usual.departure),
    '20261110': timetable('20261110-LW-1256', usual.departure),
  };
  test('finds the usual train by line, origin departure and destination', () => {
    assert.deepEqual(resolveUsualTrain(usual, '20261109', (d) => week[d]), { kind: 'trip', tripId: '20261109-LW-1256' });
    assert.equal(resolveUsualTrain({ ...usual, destination: 'AL' }, '20261109', (d) => week[d]).kind, 'changed', 'a destination before the origin is no match');
  });
  test('a day without it while it still runs later in the week is an exception', () => {
    const holiday: Record<string, Timetable> = { ...week, '20261109': timetable('20261109-LW-9999', 8 * H) };
    assert.deepEqual(resolveUsualTrain(usual, '20261109', (d) => holiday[d]), { kind: 'noTrain' });
  });
  test('a train moved or removed on every selected day ahead means the schedule changed', () => {
    const moved: Record<string, Timetable> = { '20261109': timetable('20261109-LW-1256', usual.departure + 300), '20261110': timetable('20261110-LW-1256', usual.departure + 300) };
    assert.deepEqual(resolveUsualTrain(usual, '20261109', (d) => moved[d]), { kind: 'changed' });
  });
  test('nothing is decided without the timetable', () => {
    assert.deepEqual(resolveUsualTrain(usual, '20261109', () => undefined), { kind: 'unknown' });
    assert.deepEqual(resolveUsualTrain(usual, '20261109', (d) => (d === '20261109' ? {} : undefined)), { kind: 'noTrain' });
  });
});

describe('repeating rules in the monitoring cycle', () => {
  let db: D1Database;
  let apns: FakeApns;
  const api = (request: Request) => handleRequest(request, db, at('6:00'));
  const base = `/v1/installations/${INSTALLATION}`;
  const repeat = {
    kind: 'repeat',
    tripId: '20261109-LW-1256',
    serviceDate: '20261109',
    line: 'LW',
    scheduledDeparture: new Date(at('7:13')).toISOString(),
    origin: { id: 'OA', name: 'Oakville' },
    destination: { id: 'UN', name: 'Union' },
    weekdays: [1, 2, 3, 4, 5],
  };
  const store = (date: string, trips: Timetable) =>
    db.prepare('INSERT OR REPLACE INTO timetables VALUES (?, ?, ?)').bind(date, JSON.stringify(trips), at('3:30')).run();
  const cycle = (time: string) => monitor({ db, apns, feed: async () => null, now: at(time) });

  beforeEach(async () => {
    db = memoryD1();
    apns = new FakeApns();
    await call(api, 'PUT', base, { deviceToken: TOKEN, timeFormat: '12h' });
    await call(api, 'PUT', `${base}/rules/r1`, repeat);
  });

  test('a changed train sets Review needed and sends one notification', async () => {
    await store('20261109', timetable('20261109-LW-1256', usual.departure + 300));
    await store('20261110', timetable('20261110-LW-1256', usual.departure + 300));
    await cycle('6:13');
    await cycle('6:14');
    assert.deepEqual(apns.pushes.map((p) => [p.title, p.body, p.data]), [
      ['Your usual train has changed', 'Review your Oakville to Union weekday alert.', { ruleId: 'r1' }],
    ]);
    assert.equal((await call(api, 'GET', `${base}/rules`)).json.rules[0].state, 'reviewNeeded');
    // Picking the new departure clears it.
    await call(api, 'PUT', `${base}/rules/r1`, { ...repeat, scheduledDeparture: new Date(at('7:18')).toISOString() });
    assert.equal((await call(api, 'GET', `${base}/rules`)).json.rules[0].state, 'on');
  });

  test('a selected day with no matching train shows it and sends nothing', async () => {
    await store('20261109', timetable('20261109-LW-9999', 8 * H));
    await store('20261110', timetable('20261110-LW-1256', usual.departure));
    await cycle('6:13');
    assert.equal(apns.pushes.length, 0);
    assert.equal((await call(api, 'GET', `${base}/rules`)).json.rules[0].noMatchingTrainOn, '20261109');
  });

  test('an unselected day stays quiet', async () => {
    await call(api, 'PUT', `${base}/rules/r1`, { ...repeat, weekdays: [6, 7] });
    await store('20261109', {});
    await cycle('6:13');
    assert.equal(apns.pushes.length, 0);
    assert.equal((await call(api, 'GET', `${base}/rules`)).json.rules[0].noMatchingTrainOn, null);
  });
});

test('retention: trip rules 24 h after their day, idle installations after 30 days unless a repeat alert is on', async () => {
  const db = memoryD1();
  const register = (id: string, lastSeen: number) =>
    db.prepare(`INSERT INTO installations VALUES (?, ?, 'production', '12h', ?)`).bind(id, TOKEN, lastSeen).run();
  const rule = (installation: string, id: string, kind: string, date: string) =>
    db
      .prepare(
        `INSERT INTO rules (installation_id, id, kind, trip_id, service_date, line, departure, origin_id, origin_name,
           destination_id, destination_name, weekdays, updated_at) VALUES (?, ?, ?, 't', ?, 'LW', 0, 'OA', 'Oakville', 'UN', 'Union', '1', 0)`,
      )
      .bind(installation, id, kind, date)
      .run();
  const now = at('4:17');
  const day = 24 * H * 1000;
  await register('active', now - day);
  await rule('active', 'old trip', 'trip', '20261107');
  await rule('active', 'yesterday', 'trip', '20261108');
  await register('idle', now - 31 * day);
  await rule('idle', 'trip', 'trip', '20261109');
  await register('commuter', now - 31 * day);
  await rule('commuter', 'weekdays', 'repeat', '20261002');

  await applyRetention(db, now);
  const left = await db.prepare("SELECT installation_id || ':' || id AS rule FROM rules ORDER BY 1").all<{ rule: string }>();
  assert.deepEqual(left.results.map((r) => r.rule), ['active:yesterday', 'commuter:weekdays']);
  const installations = await db.prepare('SELECT id FROM installations ORDER BY id').all<{ id: string }>();
  assert.deepEqual(installations.results.map((r) => r.id), ['active', 'commuter']);
});
