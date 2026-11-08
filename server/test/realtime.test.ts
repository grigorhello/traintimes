import assert from 'node:assert/strict';
import { test } from 'node:test';
import { decide, hasDeparted } from '../src/alerts.ts';
import { decodeFeed, liveStatus, tripUpdatesOn, type Call } from '../src/realtime.ts';
import { importTimetables } from '../src/timetable.ts';
import { gtfsInstant } from '../src/time.ts';
import { at, repoFile, sampleFeed, sampleGTFS } from './support.ts';

const timetable = (await importTimetables(sampleGTFS(), ['20261109'])).get('20261109')!;

/** The trip's calls from Oakville to Union on Nov 9, from the sample timetable. */
function call(trip: string): Call {
  const t = timetable[`20261109-${trip}`];
  return {
    stops: t.stops,
    arrivals: t.arrivals.map((s) => gtfsInstant('20261109', s)),
    departures: t.departures.map((s) => gtfsInstant('20261109', s)),
    from: t.stops.indexOf('OA'),
    to: t.stops.indexOf('UN'),
  };
}

function status(feed: ReturnType<typeof sampleFeed>, trip: string) {
  const update = tripUpdatesOn(feed, '20261109').get(`20261109-${trip}`);
  return update ? liveStatus(update, call(trip), feed.timestamp!) : null;
}

test('decodes the sample feeds written with the official bindings', () => {
  const feed = sampleFeed('0700');
  assert.equal(feed.timestamp, at('7:00'));
  assert.deepEqual(
    feed.tripUpdates.map((u) => u.tripId),
    ['20261109-LW-1256', '20261109-21-1234', '20261109-LW-1108', '20261109-LW-1308'],
  );
  assert.equal(sampleFeed('0701').tripUpdates.find((u) => u.tripId.endsWith('1858'))?.timestamp, at('7:00:40'));
});

test('maps the feed as the app does: own estimate, propagated delay, trip-wide delay, cancelled, skipped', () => {
  assert.deepEqual(status(sampleFeed('0700'), 'LW-1256'), { kind: 'running', delayMin: 1, expected: at('7:14'), reportedAt: at('7:00') });
  assert.deepEqual(status(sampleFeed('0700'), 'LW-1108'), { kind: 'running', delayMin: 5, expected: at('7:26'), reportedAt: at('7:00') });
  assert.equal(status(sampleFeed('0700'), 'LW-1308'), null, 'NO_DATA at the origin is no estimate');
  assert.deepEqual(status(sampleFeed('0701'), 'LW-1858'), { kind: 'cancelled', reportedAt: at('7:00:40') });
  const feed = sampleFeed('0702');
  assert.deepEqual(status(feed, 'LW-1758'), { kind: 'skipped', stop: 'origin', reportedAt: at('7:02') });
  assert.deepEqual(status(feed, 'LW-1308'), { kind: 'running', delayMin: 4, expected: at('7:55'), reportedAt: at('7:02') });
  assert.deepEqual(status(feed, 'LW-1860'), { kind: 'running', delayMin: 3, expected: at('8:01'), reportedAt: at('7:02') });
  assert.equal(status(feed, 'LW-1258'), null, 'an estimate at Union only is no departure estimate');
});

test('alert rules: thresholds, steps, status changes and coalescing', () => {
  const running = (delayMin: number) => ({ kind: 'running' as const, delayMin, expected: at('7:30') + delayMin * 60_000, reportedAt: at('7:00') });
  const now = at('7:10');
  assert.equal(decide(null, running(2), now), null, 'under 3 min is on time');
  assert.equal(decide(null, running(3), now)?.kind, 'delay');
  assert.equal(decide(null, null, now), null, 'no live data, no alert');
  const delayed = { kind: 'delay' as const, delayMin: 9, at: at('7:00') };
  assert.equal(decide(delayed, running(13), now), null);
  assert.deepEqual(decide(delayed, running(14), now), { kind: 'delay', delayMin: 14, expected: at('7:44'), update: true });
  assert.equal(decide(delayed, running(14), at('7:00:59')), null, 'within 60 s of the last alert');
  assert.equal(decide(delayed, running(2), now)?.kind, 'recovery');
  const recovered = { kind: 'recovery' as const, delayMin: 2, at: at('7:00') };
  assert.equal(decide(recovered, running(1), now), null);
  assert.equal(decide(recovered, running(6), now), null, 'back over 3 min but under the 5 min step');
  assert.deepEqual(decide(recovered, running(7), now), { kind: 'delay', delayMin: 7, expected: at('7:37'), update: false });
  assert.equal(decide({ kind: 'cancelled', delayMin: null, at: at('7:00') }, { kind: 'cancelled', reportedAt: now }, now), null);
  assert.deepEqual(decide({ kind: 'cancelled', delayMin: null, at: at('7:00') }, running(6), now), { kind: 'delay', delayMin: 6, expected: at('7:36'), update: false });
  assert.equal(decide({ kind: 'skipped-origin', delayMin: null, at: at('7:00') }, { kind: 'skipped', stop: 'destination', reportedAt: now }, now)?.kind, 'skipped');
  assert.equal(hasDeparted(running(5), at('7:35')), true);
  assert.equal(hasDeparted(running(5), at('7:34')), false);
});

test('decodes only the watched trips when given them (Workers Free plan CPU, D43)', () => {
  const bytes = repoFile('Tests/UnitTests/Core/Realtime/tripupdates-0700.pb');
  const all = decodeFeed(bytes);
  const watched = all.tripUpdates[1];
  const some = decodeFeed(bytes, new Set([watched.tripId]));
  assert.ok(all.tripUpdates.length > 1);
  assert.deepEqual(some, { timestamp: all.timestamp, tripUpdates: [watched] });
});
