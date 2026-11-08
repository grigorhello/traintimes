// One monitoring cycle, run every minute: find the trips active rules watch, read the live feed once, and send what the
// alert rules decide. Plus the hourly jobs: refresh the timetable and apply retention (D38).

import { decide, expiry, hasDeparted, isWatching, sentKind, STALE_MS, type Sent, type SentKind } from './alerts.ts';
import { deleteInstallation } from './api.ts';
import type { Push, PushResult } from './apns.ts';
import { alertNotice, reviewNotice, type Direction } from './copy.ts';
import { liveStatus, tripUpdatesOn, type Call, type Feed } from './realtime.ts';
import { importTimetables, resolveUsualTrain, type Timetable } from './timetable.ts';
import { addDays, DAY, gtfsInstant, HOUR, isoWeekday, serviceDate, type TimeFormat } from './time.ts';
import type { ApnsEnvironment } from './apns.ts';

export interface Sender {
  send(push: Push, now: number): Promise<PushResult>;
}

interface RuleRow {
  installation_id: string;
  id: string;
  kind: 'trip' | 'repeat';
  trip_id: string;
  service_date: string;
  line: string;
  departure: number;
  origin_id: string;
  origin_name: string;
  destination_id: string;
  destination_name: string;
  weekdays: string;
  no_train_date: string | null;
  device_token: string;
  environment: ApnsEnvironment;
  time_format: TimeFormat;
}

interface WatchRow {
  sent_kind: SentKind | null;
  sent_delay: number | null;
  sent_at: number | null;
  done: number;
  version: number;
}

/** Timetables read once per cycle. */
class Timetables {
  db: D1Database;
  cache = new Map<string, Timetable | undefined>();

  constructor(db: D1Database) {
    this.db = db;
  }

  async load(dates: string[]): Promise<void> {
    const missing = dates.filter((date) => !this.cache.has(date));
    if (missing.length === 0) return;
    const rows = await this.db
      .prepare(`SELECT service_date, trips FROM timetables WHERE service_date IN (${missing.map(() => '?').join(',')})`)
      .bind(...missing)
      .all<{ service_date: string; trips: string }>();
    for (const date of missing) this.cache.set(date, undefined);
    for (const row of rows.results) this.cache.set(row.service_date, JSON.parse(row.trips) as Timetable);
  }

  peek(date: string): Timetable | undefined {
    return this.cache.get(date);
  }
}

/**
 * The trip's calls for the live mapping. Without the trip in the timetable, the origin and destination alone still
 * carry the origin's own estimate and the trip-wide delay.
 */
function callFor(timetable: Timetable | undefined, tripId: string, rule: RuleRow, date: string): Call {
  const trip = timetable?.[tripId];
  const from = trip?.stops.indexOf(rule.origin_id) ?? -1;
  const to = trip && from >= 0 ? trip.stops.indexOf(rule.destination_id, from + 1) : -1;
  if (trip && to > from) {
    return {
      stops: trip.stops,
      arrivals: trip.arrivals.map((s) => gtfsInstant(date, s)),
      departures: trip.departures.map((s) => gtfsInstant(date, s)),
      from,
      to,
    };
  }
  const departure = gtfsInstant(date, rule.departure);
  return { stops: [rule.origin_id, rule.destination_id], arrivals: [departure, departure], departures: [departure, departure], from: 0, to: 1 };
}

interface Watch {
  rule: RuleRow;
  date: string;
  tripId: string;
  departure: number;
  call: Call;
}

export interface MonitorDeps {
  db: D1Database;
  apns: Sender;
  /** The latest TripUpdates feed; null when there is none (no key yet, or the fetch failed). */
  feed: () => Promise<Feed | null>;
  now: number;
}

/** Runs one cycle and returns the notifications APNs accepted, for logs and tests. */
export async function monitor({ db, apns, feed: loadFeed, now }: MonitorDeps): Promise<Push[]> {
  const sent: Push[] = [];
  const gone = new Set<string>();

  async function deliver(rule: RuleRow, push: Omit<Push, 'token' | 'environment'>): Promise<PushResult> {
    if (gone.has(rule.installation_id)) return 'failed';
    const full = { ...push, token: rule.device_token, environment: rule.environment };
    const result = await apns.send(full, now);
    if (result === 'sent') sent.push(full);
    if (result === 'unregistered') {
      // The app is gone from the device: remove it with its rules (rule 9).
      gone.add(rule.installation_id);
      await deleteInstallation(db, rule.installation_id);
    } else if (result === 'badToken') {
      gone.add(rule.installation_id);
      await db
        .prepare('UPDATE installations SET device_token = NULL WHERE id = ? AND device_token = ?')
        .bind(rule.installation_id, rule.device_token)
        .run();
    }
    return result;
  }

  const today = serviceDate(now);
  const dates = [addDays(today, -1), today];
  const rules = await db
    .prepare(
      `SELECT r.*, i.device_token, i.environment, i.time_format FROM rules r
       JOIN installations i ON i.id = r.installation_id
       WHERE r.paused = 0 AND r.state = 'on' AND i.device_token IS NOT NULL`,
    )
    .all<RuleRow>();
  const timetables = new Timetables(db);
  const watches: Watch[] = [];

  for (const rule of rules.results) {
    // APNs just rejected this installation's token: leave its other rules for a cycle after it registers again.
    if (gone.has(rule.installation_id)) continue;
    const direction: Direction = { origin: rule.origin_name, destination: rule.destination_name };
    for (const date of dates) {
      if (rule.kind === 'trip') {
        const departure = gtfsInstant(date, rule.departure);
        if (rule.service_date !== date || !isWatching(departure, now)) continue;
        await timetables.load([date]);
        watches.push({ rule, date, tripId: rule.trip_id, departure, call: callFor(timetables.peek(date), rule.trip_id, rule, date) });
        continue;
      }

      // A repeating rule: resolve today's trip for the usual train once its watch window opens (rule 7).
      const weekdays = rule.weekdays.split(',').map(Number);
      const usual = gtfsInstant(date, rule.departure);
      if (!weekdays.includes(isoWeekday(date)) || !isWatching(usual, now)) continue;
      await timetables.load(Array.from({ length: 8 }, (_, days) => addDays(date, days)));
      const train = { line: rule.line, origin: rule.origin_id, destination: rule.destination_id, departure: rule.departure, weekdays };
      const resolution = resolveUsualTrain(train, date, (d) => timetables.peek(d));
      if (resolution.kind === 'trip') {
        watches.push({ rule, date, tripId: resolution.tripId, departure: usual, call: callFor(timetables.peek(date), resolution.tripId, rule, date) });
      } else if (resolution.kind === 'noTrain' && rule.no_train_date !== date) {
        // "No matching train today" in the Alerts row; nothing is sent (rule 8).
        await db
          .prepare('UPDATE rules SET no_train_date = ? WHERE installation_id = ? AND id = ?')
          .bind(date, rule.installation_id, rule.id)
          .run();
      } else if (resolution.kind === 'changed') {
        // Review needed, and one notification: only the cycle that changes the state sends it.
        const changed = await db
          .prepare(`UPDATE rules SET state = 'review' WHERE installation_id = ? AND id = ? AND state = 'on'`)
          .bind(rule.installation_id, rule.id)
          .run();
        if (changed.meta.changes > 0) {
          const result = await deliver(rule, { ...reviewNotice(direction), expiration: expiry(usual), data: { ruleId: rule.id } });
          if (result === 'retry' || result === 'badToken') {
            // Not delivered: back to On, so a later cycle sets Review needed again and sends it.
            await db
              .prepare(`UPDATE rules SET state = 'on' WHERE installation_id = ? AND id = ? AND state = 'review'`)
              .bind(rule.installation_id, rule.id)
              .run();
          }
        }
      }
    }
  }
  if (watches.length === 0) return sent;

  const feed = await loadFeed();
  const feedTime = feed?.timestamp;
  // Stale data never starts an alert or ends a watch (Q2, D13).
  const fresh = feed && feedTime !== undefined && now - feedTime <= STALE_MS ? feed : null;
  const updatesByDate = new Map(dates.map((date) => [date, fresh ? tripUpdatesOn(fresh, date) : new Map()]));
  const seen = new Set<string>();

  for (const { rule, date, tripId, departure, call } of watches) {
    const key = `${date}|${tripId}|${rule.origin_id}|${rule.destination_id}`;
    // A This-trip rule and a Repeat rule for the same train share one watch, so the rider gets one message.
    if (seen.has(`${rule.installation_id}|${key}`) || gone.has(rule.installation_id)) continue;
    seen.add(`${rule.installation_id}|${key}`);

    const watch = await db
      .prepare('SELECT sent_kind, sent_delay, sent_at, done, version FROM watches WHERE installation_id = ? AND key = ?')
      .bind(rule.installation_id, key)
      .first<WatchRow>();
    if (watch?.done) continue;
    const update = updatesByDate.get(date)?.get(tripId);
    const status = update && fresh ? liveStatus(update, call, feedTime!) : null;
    const version = watch?.version ?? 0;

    if (hasDeparted(status, feedTime ?? 0)) {
      // Departure-delay alerts stop once the train has left (rule 6).
      await upsertWatch(db, rule.installation_id, key, date, watch, { done: 1 }, version);
      continue;
    }
    const last: Sent | null = watch?.sent_kind ? { kind: watch.sent_kind, delayMin: watch.sent_delay, at: watch.sent_at ?? 0 } : null;
    const alert = decide(last, status, now);
    if (!alert || !status) continue;

    // Claim the send first: an overlapping cycle that read the same version changes nothing and sends nothing.
    const next = { sent_kind: sentKind(alert), sent_delay: 'delayMin' in alert ? alert.delayMin : null, sent_at: now };
    if (!(await upsertWatch(db, rule.installation_id, key, date, watch, next, version))) continue;
    const notice = alertNotice(alert, departure, { origin: rule.origin_name, destination: rule.destination_name }, status.reportedAt, rule.time_format);
    const result = await deliver(rule, { ...notice, expiration: expiry(departure), data: { tripId, serviceDate: date, originId: rule.origin_id, destinationId: rule.destination_id, kind: alert.kind } });
    if (result === 'retry' || result === 'badToken') {
      // Not delivered: put the last sent state back so a later cycle (after the app registers again) decides again.
      const previous = { sent_kind: watch?.sent_kind ?? null, sent_delay: watch?.sent_delay ?? null, sent_at: watch?.sent_at ?? null };
      await upsertWatch(db, rule.installation_id, key, date, watch, previous, version + 1);
    }
  }
  return sent;
}

/** Writes a watch only if nobody wrote it since `version` was read; true when this call wrote it. */
async function upsertWatch(
  db: D1Database,
  installation: string,
  key: string,
  date: string,
  current: WatchRow | null,
  changes: Partial<Pick<WatchRow, 'sent_kind' | 'sent_delay' | 'sent_at' | 'done'>>,
  version: number,
): Promise<boolean> {
  const row = { sent_kind: null, sent_delay: null, sent_at: null, done: 0, ...current, ...changes };
  const result = await db
    .prepare(
      `INSERT INTO watches (installation_id, key, service_date, sent_kind, sent_delay, sent_at, done, version)
       VALUES (?, ?, ?, ?, ?, ?, ?, 1)
       ON CONFLICT (installation_id, key) DO UPDATE SET sent_kind = excluded.sent_kind, sent_delay = excluded.sent_delay,
         sent_at = excluded.sent_at, done = excluded.done, version = watches.version + 1
       WHERE watches.version = ?`,
    )
    .bind(installation, key, date, row.sent_kind, row.sent_delay, row.sent_at, row.done, version)
    .run();
  return result.meta.changes > 0;
}

/** Reads the timetable for today and the next 7 days from the GTFS zip, once a day (hourly while it fails). */
export async function refreshTimetables(db: D1Database, download: () => Promise<Uint8Array>, now: number): Promise<number> {
  const today = serviceDate(now);
  const current = await db
    .prepare('SELECT imported_at FROM timetables WHERE service_date = ?')
    .bind(today)
    .first<{ imported_at: number }>();
  if (current && now - current.imported_at < 24 * HOUR) return 0;
  const dates = Array.from({ length: 8 }, (_, days) => addDays(today, days));
  const timetables = await importTimetables(await download(), dates);
  // A date the feed does not cover stays missing rather than empty, so it never reads as "the train is gone".
  const rows = [...timetables].filter(([, trips]) => Object.keys(trips).length > 0);
  await db.batch(
    rows.map(([date, trips]) =>
      db
        .prepare('INSERT OR REPLACE INTO timetables (service_date, trips, imported_at) VALUES (?, ?, ?)')
        .bind(date, JSON.stringify(trips), now),
    ),
  );
  return rows.length;
}

/**
 * Retention (Q8, D38): a This-trip rule and its watch go 24 h after their service day ends (3 AM the day after); an
 * installation goes after 30 days without the app calling, unless it has an active repeat alert, and as soon as APNs
 * says the app was removed (in `monitor`).
 */
export async function applyRetention(db: D1Database, now: number): Promise<void> {
  const today = serviceDate(now);
  const expired = addDays(today, -2);
  await db.batch([
    db.prepare(`DELETE FROM rules WHERE kind = 'trip' AND service_date <= ?`).bind(expired),
    db.prepare('DELETE FROM watches WHERE service_date <= ?').bind(expired),
    db
      .prepare(
        `DELETE FROM installations WHERE last_seen < ? AND NOT EXISTS (SELECT 1 FROM rules WHERE rules.installation_id =
           installations.id AND rules.kind = 'repeat' AND rules.paused = 0 AND rules.state = 'on')`,
      )
      .bind(now - 30 * DAY),
    db.prepare('DELETE FROM rules WHERE installation_id NOT IN (SELECT id FROM installations)'),
    db.prepare('DELETE FROM watches WHERE installation_id NOT IN (SELECT id FROM installations)'),
    db.prepare('DELETE FROM timetables WHERE service_date < ?').bind(addDays(today, -1)),
  ]);
}
