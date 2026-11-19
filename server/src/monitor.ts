// One monitoring cycle, run every minute: find the trips active rules watch, read the live feed once, and send what the
// alert rules decide. Plus the daily retention and storing the uploaded timetable (D38, D43).
//
// A cycle stays inside the Workers Free plan (D43): it reads only the rules whose watch window is open, the watched
// trips' part of the feed and today's timetable (the coming week's only when the usual train is missing today), reads
// the watches in one query, and makes at most MAX_SENDS calls to APNs. GO's train positions are read once, and only
// while an alerted train is in its Live Activity window; a station's board only while one stands at it (TT-233, D114).
// Every cycle, idle ones too, also reads the Live Activity cards no rule watches any more and ends them (TT-240, D118).

import {
  decide,
  expiry,
  hasDeparted,
  isWatching,
  sentKind,
  STALE_MS,
  WATCH_AFTER_MS,
  WATCH_BEFORE_MS,
  type Sent,
  type SentKind,
} from './alerts.ts';
import {
  asksIn,
  askTitle,
  BOARDING_RADIUS_M,
  contentState,
  DEPART_LEAD_MS,
  endPayload,
  hasSighting,
  leaves,
  LINE_COLORS,
  phaseAt,
  shortName,
  signature,
  startPayload,
  staleDate,
  sweptState,
  updatePayload,
  type Departure,
} from './activity.ts';
import { deleteInstallation } from './api.ts';
import type { LiveActivityPush, Push, PushResult } from './apns.ts';
import { alertNotice, reviewNotice, type Direction } from './copy.ts';
import { platformFor, type PlatformBoard } from './platforms.ts';
import { hasLeftOrigin, liveStatus, tripUpdatesOn, type Call, type Feed, type LiveStatus, type TrainPosition, type TripUpdate } from './realtime.ts';
import { STATIONS } from './stations.ts';
import { resolveUsualTrain, type Timetable } from './timetable.ts';
import { addDays, DAY, gtfsInstant, gtfsSeconds, isoWeekday, MINUTE, serviceDate, type TimeFormat } from './time.ts';
import type { ApnsEnvironment } from './apns.ts';

/**
 * APNs calls per cycle. The Free plan allows 50 outside requests per run, and the Cache API's calls share that quota
 * with fetch(). Reading something through a relay costs 3 at worst (the cache's match, the call to GO, the cache's
 * put): TripUpdates 3, the train positions 3 and BOARD_STATIONS station boards 3 each (TT-233) make 12, which leaves 38
 * for APNs; 36 keeps 2 spare, as 45 did beside the feed's 3. The rest are decided again the next minute. On Workers Paid
 * (10,000 per run) this can be raised.
 */
export const MAX_SENDS = 36;

/** Station boards read per cycle at most (TT-233): each can cost 3 outside requests, counted in MAX_SENDS. */
export const BOARD_STATIONS = 2;

export interface Sender {
  send(push: Push, now: number): Promise<PushResult>;
  sendLiveActivity(push: LiveActivityPush, now: number): Promise<PushResult>;
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
  /** The push-to-start token for the before-departure Live Activity (TT-178); null before iOS 17.2 or until the app sends it. */
  start_token: string | null;
}

interface ActivityRow {
  installation_id: string;
  key: string;
  token: string | null;
  /**
   * `asked`: the app was in front as the train left, so the question comes silently (TT-231); `notified`: it went as a
   * notification; `removed`: the app ended the card because its alert was gone (TT-240), so nothing follows it.
   */
  state: 'started' | 'ended' | 'handedOff' | 'asked' | 'notified' | 'removed';
  shown: string | null;
  version: number;
}

/** A card the sweep may end (TT-240): its row with what a push to it needs. */
interface SweptRow extends ActivityRow {
  service_date: string;
  token: string;
  shown: string;
  environment: ApnsEnvironment;
}

interface WatchRow {
  installation_id: string;
  key: string;
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
  /** The latest TripUpdates feed, decoded for these trips only; null when there is none (no key yet, or the fetch failed). */
  feed: (trips: ReadonlySet<string>) => Promise<Feed | null>;
  /**
   * GO's train positions, from the VehiclePosition snapshot the relay holds (TT-233); null when there is none. Called at
   * most once a cycle, and only when an alerted train is in its activity window. Left out, every train follows the clock.
   */
  positions?: () => Promise<{ timestamp?: number; trains: TrainPosition[] } | null>;
  /**
   * A station's departures board, for its posted platforms (TT-225); null while GO fails. Called for BOARD_STATIONS
   * stations a cycle at most, and only for one where an alerted train stands. Left out, no train boards by its position.
   */
  platforms?: (stop: string) => Promise<PlatformBoard | null>;
  now: number;
}

/** What GO's train feed and the origin's board say about one alerted train (TT-233): `Departure.position` and `platform`. */
interface Sighting {
  origin: string;
  tripId: string;
  position: { metres: number; at: number } | null;
  platform: string | null;
}

/**
 * Metres between two places, on a flat frame at their mean latitude, as the app measures a train against its station
 * (`TrackShape.distance`), so both put the 350 m line in the same place.
 */
export function metresBetween(a: readonly [latitude: number, longitude: number], b: readonly [latitude: number, longitude: number]): number {
  const metresPerDegree = 111_195.08;
  const latitude = (((a[0] + b[0]) / 2) * Math.PI) / 180;
  return Math.hypot((b[1] - a[1]) * metresPerDegree * Math.cos(latitude), (b[0] - a[0]) * metresPerDegree);
}

/** The train's departure for the activity, before anything is known of where it is. */
function departureOf(watch: Watch, status: LiveStatus | null): Departure {
  return {
    scheduled: watch.departure,
    scheduledArrival: watch.call.arrivals[watch.call.to],
    status,
    origin: watch.rule.origin_name,
    destination: watch.rule.destination_name,
  };
}

/** One train at one origin station, whoever watches it. */
const trainKey = (watch: Watch) => `${watch.date}|${watch.tripId}|${watch.rule.origin_id}`;

/** A watch's key, and its activity's: the service date, the trip and the rider's two stations. */
const watchKey = (watch: Watch) => `${watch.date}|${watch.tripId}|${watch.rule.origin_id}|${watch.rule.destination_id}`;

/** Runs one cycle and returns the notifications APNs accepted, for logs and tests. */
export async function monitor({ db, apns, feed: loadFeed, positions: loadPositions, platforms: loadPlatforms, now }: MonitorDeps): Promise<Push[]> {
  const sent: Push[] = [];
  const gone = new Set<string>();
  let sends = 0;

  async function deliver(rule: RuleRow, push: Omit<Push, 'token' | 'environment'>): Promise<PushResult> {
    if (gone.has(rule.installation_id)) return 'failed';
    const full = { ...push, token: rule.device_token, environment: rule.environment };
    sends++;
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
  // Only rules whose watch window may be open on one of the dates (a minute of margin; isWatching decides).
  const windows = dates.flatMap((date) => {
    const seconds = gtfsSeconds(date, now);
    return [seconds - (WATCH_AFTER_MS + MINUTE) / 1000, seconds + (WATCH_BEFORE_MS + MINUTE) / 1000];
  });
  const rules = await db
    .prepare(
      `SELECT r.*, i.device_token, i.environment, i.time_format, s.token AS start_token FROM rules r
       JOIN installations i ON i.id = r.installation_id
       LEFT JOIN start_tokens s ON s.installation_id = r.installation_id
       WHERE r.paused = 0 AND r.state = 'on' AND i.device_token IS NOT NULL
         AND (r.departure BETWEEN ? AND ? OR r.departure BETWEEN ? AND ?)
         AND (r.kind = 'repeat' OR r.service_date IN (?, ?))`,
    )
    .bind(...windows, ...dates)
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
      const train = { line: rule.line, origin: rule.origin_id, destination: rule.destination_id, departure: rule.departure, weekdays };
      // Today's timetable usually has the usual train; the coming week is read only when it does not, once a day.
      await timetables.load([date]);
      let resolution = resolveUsualTrain(train, date, (d) => timetables.peek(d));
      if (resolution.kind === 'noTrain' && rule.no_train_date !== date) {
        await timetables.load(Array.from({ length: 7 }, (_, days) => addDays(date, days + 1)));
        resolution = resolveUsualTrain(train, date, (d) => timetables.peek(d));
      }
      if (resolution.kind === 'trip') {
        watches.push({ rule, date, tripId: resolution.tripId, departure: usual, call: callFor(timetables.peek(date), resolution.tripId, rule, date) });
      } else if (resolution.kind === 'noTrain' && rule.no_train_date !== date) {
        // "No matching train today" in the Alerts row; nothing is sent (rule 8).
        await db
          .prepare('UPDATE rules SET no_train_date = ? WHERE installation_id = ? AND id = ?')
          .bind(date, rule.installation_id, rule.id)
          .run();
      } else if (resolution.kind === 'changed' && sends < MAX_SENDS) {
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
  await sweep();
  if (watches.length === 0) return sent;

  const feed = await loadFeed(new Set(watches.map((watch) => watch.tripId)));
  const feedTime = feed?.timestamp;
  // Stale data never starts an alert or ends a watch (Q2, D13).
  const fresh = feed && feedTime !== undefined && now - feedTime <= STALE_MS ? feed : null;
  const updatesByDate = new Map(dates.map((date) => [date, fresh ? tripUpdatesOn(fresh, date) : new Map()]));
  const seen = new Set<string>();
  // The watches of the watched dates in one query, rather than one query per watched trip.
  const watchDates = [...new Set(watches.map((watch) => watch.date))];
  const rows = await db
    .prepare('SELECT installation_id, key, sent_kind, sent_delay, sent_at, done, version FROM watches WHERE service_date IN (?, ?)')
    .bind(watchDates[0], watchDates.at(-1))
    .all<WatchRow>();
  const watchRows = new Map(rows.results.map((row) => [`${row.installation_id}|${row.key}`, row]));
  // The before-departure activities of the same dates (TT-178), in one query too.
  const activityRows = await db
    .prepare('SELECT installation_id, key, token, state, shown, version FROM activities WHERE service_date IN (?, ?)')
    .bind(watchDates[0], watchDates.at(-1))
    .all<ActivityRow>();
  const activities = new Map(activityRows.results.map((row) => [`${row.installation_id}|${row.key}`, row]));
  // Riders sent nothing yet go first, then those sent to longest ago, so past MAX_SENDS nobody waits behind updates.
  const queue = watches
    .map((watch) => {
      const key = watchKey(watch);
      const update: TripUpdate | undefined = updatesByDate.get(watch.date)?.get(watch.tripId);
      const status = update && fresh ? liveStatus(update, watch.call, feedTime!) : null;
      // The Live Activity runs on past the train's departure, when departure alerts stop.
      const activity = activities.get(`${watch.rule.installation_id}|${key}`) ?? null;
      return { ...watch, key, watch: watchRows.get(`${watch.rule.installation_id}|${key}`) ?? null, update, status, activity };
    })
    .sort((a, b) => (a.watch?.sent_at ?? 0) - (b.watch?.sent_at ?? 0));
  const sightings = await sight(queue);

  for (const { rule, date, tripId, departure, call, key, watch, update, status, activity } of queue) {
    // A This-trip rule and a Repeat rule for the same train share one watch, so the rider gets one message.
    if (seen.has(`${rule.installation_id}|${key}`) || gone.has(rule.installation_id)) continue;
    seen.add(`${rule.installation_id}|${key}`);
    // With no push-to-start token the activity never starts, but the question still goes, as a notification (TT-231).
    await followActivity({ rule, date, tripId, departure, call, key }, status, activity, update);
    if (watch?.done) continue;
    const version = watch?.version ?? 0;

    if (hasDeparted(status, feedTime ?? 0)) {
      // Departure-delay alerts stop once the train has left (rule 6).
      await upsertWatch(db, rule.installation_id, key, date, watch, { done: 1 }, version);
      continue;
    }
    const last: Sent | null = watch?.sent_kind ? { kind: watch.sent_kind, delayMin: watch.sent_delay, at: watch.sent_at ?? 0 } : null;
    const alert = decide(last, status, now);
    // Past the cycle's APNs calls, the alert is decided again next minute.
    if (!alert || !status || sends >= MAX_SENDS) continue;

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

  /**
   * Cards nobody watches (TT-240, D118): a Live Activity the server can reach (it has the card's token, and `shown` says
   * a cycle followed it or its rule was just removed or paused) whose train no watch of this cycle claims. Its alert was
   * removed, switched off or set to Review needed, so nothing would update the card again and its minutes would stand
   * still on the Lock Screen: it gets `event: end` and its row goes, so an alert switched on again starts a fresh card.
   * The app ends the card itself at the tap; this is for a card it could not reach (closed meanwhile, an older build).
   * Rows without `shown` are left alone: the app reported them and no rule here ever watched them (Demo trains ›
   * Departure, a rule whose save has not arrived). So are cards handed off to a ride or answered No. Runs every cycle,
   * idle ones too: one indexed read, and its pushes count in MAX_SENDS.
   */
  async function sweep() {
    const rows = await db
      .prepare(
        `SELECT a.installation_id, a.key, a.service_date, a.token, a.state, a.shown, a.version, i.environment FROM activities a
         JOIN installations i ON i.id = a.installation_id
         WHERE a.service_date IN (?, ?) AND a.state IN ('started', 'asked') AND a.token IS NOT NULL AND a.shown IS NOT NULL`,
      )
      .bind(...dates)
      .all<SweptRow>();
    if (rows.results.length === 0) return;
    const watched = new Set(watches.map((watch) => `${watch.rule.installation_id}|${watchKey(watch)}`));
    for (const row of rows.results) {
      if (watched.has(`${row.installation_id}|${row.key}`)) continue;
      if (sends >= MAX_SENDS) return;
      // Claim the end first: an overlapping cycle, or the app reporting a new card for the train meanwhile, changes the
      // version, and then nothing is sent or removed.
      const claimed = await db
        .prepare('DELETE FROM activities WHERE installation_id = ? AND key = ? AND version = ?')
        .bind(row.installation_id, row.key, row.version)
        .run();
      if (claimed.meta.changes === 0) continue;
      sends++;
      const push = { token: row.token, environment: row.environment, payload: endPayload(sweptState(row.shown), now), expiration: now + 60 * MINUTE };
      if ((await apns.sendLiveActivity(push, now)) !== 'retry') continue;
      // Not delivered: the row goes back for the next cycle, unless the app reported a new card meanwhile.
      await db
        .prepare('INSERT OR IGNORE INTO activities (installation_id, key, service_date, token, state, shown, version) VALUES (?, ?, ?, ?, ?, ?, ?)')
        .bind(row.installation_id, row.key, row.service_date, row.token, row.state, row.shown, row.version + 1)
        .run();
    }
  }

  /**
   * Boarding at the platform (TT-233, D114): where GO's train feed places the alerted trains that are in their activity
   * window, by `trainKey`, and the platform the origin's board posts for the ones standing there. The positions are read
   * once, and only when such a train exists. A board is read only for a station where one stands within 350 m, for
   * BOARD_STATIONS stations at most: the ones where most riders wait, so the same stations are read from one minute to the
   * next. A train at a station left out, or missing from `STATIONS`, does not board; `boardingPhase` says what it does.
   */
  async function sight(trains: (Watch & { status: LiveStatus | null; activity: ActivityRow | null })[]): Promise<Map<string, Sighting>> {
    const found = new Map<string, Sighting>();
    if (!loadPositions) return found;
    const live = trains.filter((train) => {
      // `followActivity` does nothing more for these, and a card that asks stays the question wherever the train is.
      if (train.activity && train.activity.state !== 'started' && train.activity.state !== 'asked') return false;
      if (asksIn(train.activity?.shown ?? null) && now >= leaves(departureOf(train, train.status)) - DEPART_LEAD_MS) return false;
      // The window is the clock's and the live status's alone: no position opens or closes it.
      const phase = phaseAt(departureOf(train, train.status), now);
      return phase !== 'before' && phase !== 'over';
    });
    if (live.length === 0) return found;
    let vehicles: { timestamp?: number; trains: TrainPosition[] } | null = null;
    try {
      vehicles = await loadPositions();
    } catch (error) {
      console.warn('Train positions failed', error);
    }
    if (!vehicles) return found;

    const stands = (sighting: Sighting) => sighting.position !== null && hasSighting(sighting, now) && sighting.position.metres <= BOARDING_RADIUS_M;
    // Riders by origin station whose train stands at it.
    const waiting = new Map<string, number>();
    for (const train of live) {
      const id = trainKey(train);
      let sighting = found.get(id);
      if (!sighting) {
        const origin = train.rule.origin_id;
        // The rule's station id is the app's text: only GO's own station codes have a place, and so a board to read.
        const place = Object.hasOwn(STATIONS, origin) ? STATIONS[origin] : undefined;
        // A vehicle that names a start date must be on the train's service date.
        const vehicle = place && vehicles.trains.find((v) => v.tripId === train.tripId && (v.startDate === undefined || v.startDate === train.date));
        // With no time of its own a position is as old as the feed, as the app reads it (`RelayTrainPositions`).
        const position = place && vehicle ? { metres: metresBetween(place, [vehicle.latitude, vehicle.longitude]), at: vehicle.timestamp ?? vehicles.timestamp ?? 0 } : null;
        sighting = { origin, tripId: train.tripId, position, platform: null };
        found.set(id, sighting);
      }
      if (stands(sighting)) waiting.set(sighting.origin, (waiting.get(sighting.origin) ?? 0) + 1);
    }
    if (!loadPlatforms || waiting.size === 0) return found;

    const boardOf = loadPlatforms;
    const stations = [...waiting.keys()].sort((a, b) => waiting.get(b)! - waiting.get(a)! || (a < b ? -1 : 1)).slice(0, BOARD_STATIONS);
    const boards = await Promise.all(
      stations.map(async (stop) => {
        try {
          return await boardOf(stop);
        } catch (error) {
          console.warn(`Board ${stop} failed`, error);
          return null;
        }
      }),
    );
    for (const sighting of found.values()) {
      const board = boards[stations.indexOf(sighting.origin)];
      if (board && stands(sighting)) sighting.platform = platformFor(board, sighting.tripId);
    }
    return found;
  }

  /**
   * The watched train's before-departure Live Activity (TT-178, D74): started once at T−30 with a push-to-start, updated
   * when what it shows changes, turned into the question once the train has left, with an alert (TT-231), and ended 10 min
   * later or at the rider's stop (at once when it is cancelled or skips a stop). With no card to reach, the question goes as
   * a notification. Nothing once the app's ride took it over or the rider said No. Boarding and the moment it has left
   * come from where the train is (TT-233, `sight`, `boardingPhase`), the clock when nothing places it.
   */
  async function followActivity(watch: Watch & { key: string }, status: LiveStatus | null, activity: ActivityRow | null, update: TripUpdate | undefined) {
    const { rule, call, key, date } = watch;
    if (activity && activity.state !== 'started' && activity.state !== 'asked') return;
    const sighting = sightings.get(trainKey(watch));
    const train: Departure = {
      ...departureOf(watch, status),
      position: sighting?.position,
      platform: sighting?.platform,
      hasLeftOrigin: update !== undefined && hasLeftOrigin(update, call),
    };
    let phase = phaseAt(train, now);
    // The question is asked once (TT-231): a card that asks stays the question, though a later position puts the train
    // back at the station or the feed that said it had left is gone. Not once its expected time has moved on (a delay
    // reported after the question): then it counts down again and asks when it leaves, as before TT-233.
    if ((phase === 'countingDown' || phase === 'boarding') && asksIn(activity?.shown ?? null) && now >= leaves(train) - DEPART_LEAD_MS) phase = 'asking';
    if (phase === 'before') return;
    const expiration = staleDate(train);

    if (!activity) {
      if (phase === 'asking') {
        await askByNotification(watch, train, null);
        return;
      }
      // No card starts once the train's time has come, as none did before the boarding rule (TT-233): the start's alert
      // says "departs in". A train still standing there is asked about, by notification, when it leaves.
      if (phase === 'over' || !rule.start_token || sends >= MAX_SENDS || now >= leaves(train)) return;
      // Claim the start first: an overlapping cycle finds the row and starts nothing.
      const state = contentState(train, phase, now, rule.time_format);
      const claimed = await db
        .prepare(`INSERT OR IGNORE INTO activities (installation_id, key, service_date, state, shown) VALUES (?, ?, ?, 'started', ?)`)
        .bind(rule.installation_id, key, date, signature(state))
        .run();
      if (claimed.meta.changes === 0) return;
      const attributes = {
        tripId: watch.tripId,
        serviceDate: Number(date),
        originId: rule.origin_id,
        destinationId: rule.destination_id,
        lineCode: rule.line,
        lineColorHex: LINE_COLORS[rule.line] ?? null,
        destinationName: shortName(rule.destination_name),
        stopCount: call.to - call.from + 1,
      };
      sends++;
      const result = await apns.sendLiveActivity(
        { token: rule.start_token, environment: rule.environment, payload: startPayload(train, attributes, state, now, rule.time_format), expiration },
        now,
      );
      if (result === 'sent') return;
      if (result === 'unregistered' || result === 'badToken') {
        // The push-to-start token is no longer good: nothing starts until the app sends a new one.
        await db.prepare('DELETE FROM start_tokens WHERE installation_id = ? AND token = ?').bind(rule.installation_id, rule.start_token).run();
      }
      if (result !== 'failed') {
        // Not started: let a later cycle try again.
        await db.prepare('DELETE FROM activities WHERE installation_id = ? AND key = ?').bind(rule.installation_id, key).run();
      }
      return;
    }

    // Started, by the server or by the app: updates and the end go to the activity's own token.
    if (phase === 'over') {
      if (activity.token) {
        if (sends >= MAX_SENDS) return;
        // Its last look: Departed, or the timetable's for a train that no longer runs; it leaves the Lock Screen at once.
        const last = contentState(status?.kind === 'running' ? train : { ...train, status: null }, 'departed', now, rule.time_format);
        sends++;
        const result = await apns.sendLiveActivity({ token: activity.token, environment: rule.environment, payload: endPayload(last, now), expiration: now + 60 * MINUTE }, now);
        if (result === 'retry') return;
      }
      await setActivity(activity, { state: 'ended' });
      return;
    }
    // The app was in front as the train left (it reported `asked`): the question comes with no alert and no notification.
    const silent = activity.state === 'asked';
    // No token to reach the card (the app has not reported it): the question goes as a notification instead (TT-231).
    if (!activity.token && phase === 'asking') {
      if (!silent) await askByNotification(watch, train, activity);
      return;
    }
    if (!activity.token || sends >= MAX_SENDS) return;
    const state = contentState(train, phase, now, rule.time_format);
    const shown = signature(state);
    if (shown === activity.shown) return;
    // Claim the update first, as a watch's send is claimed.
    if (!(await setActivity(activity, { shown }))) return;
    sends++;
    // The alert goes with the update that turns the card into the question, not with a later one that only moves its
    // time (the expected departure moves once the feed drops the station, D89).
    const payload = updatePayload(train, state, now, rule.time_format, silent || asksIn(activity.shown));
    const result = await apns.sendLiveActivity({ token: activity.token, environment: rule.environment, payload, expiration }, now);
    if (result === 'unregistered' || result === 'badToken') {
      // The rider swiped it away, or it ended: nothing more to send.
      await setActivity({ ...activity, version: activity.version + 1 }, { state: 'ended' });
    } else if (result === 'retry') {
      await setActivity({ ...activity, version: activity.version + 1 }, { shown: activity.shown });
    }
  }

  /**
   * The departure question as a notification, once, when there is no card to ask on (TT-231, D110): "On the 4:29 PM
   * train?" with Yes and No (category `depart.question`), expiring when the question ends. The activity row records it, so
   * it goes once and the card's alert never goes as well.
   */
  async function askByNotification(watch: Watch & { key: string }, train: Departure, activity: ActivityRow | null) {
    const { rule, key, date, tripId } = watch;
    if (sends >= MAX_SENDS) return;
    if (activity) {
      if (!(await setActivity(activity, { state: 'notified' }))) return;
    } else {
      const claimed = await db
        .prepare(`INSERT OR IGNORE INTO activities (installation_id, key, service_date, state) VALUES (?, ?, ?, 'notified')`)
        .bind(rule.installation_id, key, date)
        .run();
      if (claimed.meta.changes === 0) return;
    }
    const result = await deliver(rule, {
      title: askTitle(train, rule.time_format),
      body: '',
      expiration: staleDate(train),
      category: 'depart.question',
      data: { tripId, serviceDate: date, originId: rule.origin_id, destinationId: rule.destination_id, kind: 'departure' },
    });
    if (result === 'retry') {
      // Not delivered: a later cycle within the question's 10 min tries again.
      if (activity) {
        await setActivity({ ...activity, version: activity.version + 1 }, { state: activity.state });
      } else {
        await db.prepare(`DELETE FROM activities WHERE installation_id = ? AND key = ? AND state = 'notified'`).bind(rule.installation_id, key).run();
      }
    }
  }

  /** Writes an activity only if nobody wrote it since it was read; true when this call wrote it. */
  async function setActivity(activity: ActivityRow, changes: Partial<Pick<ActivityRow, 'state' | 'shown'>>): Promise<boolean> {
    const row = { ...activity, ...changes };
    const result = await db
      .prepare('UPDATE activities SET state = ?, shown = ?, version = version + 1 WHERE installation_id = ? AND key = ? AND version = ?')
      .bind(row.state, row.shown, activity.installation_id, activity.key, activity.version)
      .run();
    return result.meta.changes > 0;
  }
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

/**
 * Stores one service date's rail timetable (JSON trips by trip id, as `importTimetables` reads them). The daily upload
 * sends today and the next 7 days (D43); a date the feed does not cover is never sent, so it stays missing rather than
 * empty and never reads as "the train is gone".
 */
export async function saveTimetable(db: D1Database, date: string, trips: string, now: number): Promise<void> {
  await db
    .prepare('INSERT OR REPLACE INTO timetables (service_date, trips, imported_at) VALUES (?, ?, ?)')
    .bind(date, trips, now)
    .run();
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
    db.prepare('DELETE FROM activities WHERE service_date <= ?').bind(expired),
    db
      .prepare(
        `DELETE FROM installations WHERE last_seen < ? AND NOT EXISTS (SELECT 1 FROM rules WHERE rules.installation_id =
           installations.id AND rules.kind = 'repeat' AND rules.paused = 0 AND rules.state = 'on')`,
      )
      .bind(now - 30 * DAY),
    db.prepare('DELETE FROM rules WHERE installation_id NOT IN (SELECT id FROM installations)'),
    db.prepare('DELETE FROM watches WHERE installation_id NOT IN (SELECT id FROM installations)'),
    db.prepare('DELETE FROM activities WHERE installation_id NOT IN (SELECT id FROM installations)'),
    db.prepare('DELETE FROM feedback WHERE created_at < ?').bind(now - 365 * DAY),
    db.prepare('DELETE FROM start_tokens WHERE installation_id NOT IN (SELECT id FROM installations)'),
    db.prepare('DELETE FROM timetables WHERE service_date < ?').bind(addDays(today, -1)),
  ]);
}
