// The before-departure Live Activity (TT-178, D74): an alerted train's countdown on the Lock Screen and in the Dynamic
// Island from 30 min before it leaves. The server starts it with a push-to-start (iOS 17.2+), updates it only when what it
// shows changes, and once the train has left turns it into the question "On board?" with Yes and No, with an alert (TT-231,
// D110); with no card to update it sends the question as a notification instead. It ends 10 min after the train left, or
// at the rider's stop if sooner, unless the app's ride took it over (the same activity becomes the ride) or the rider said
// No. Every word is the app's (`RideActivityAttributes.ContentState` in `Shared/`), so an activity the app updates later
// looks the same: one card for every moment (TT-205, D93), "7:13 AM departs in" over the minutes, "Platform" and the pill.
// GO's feeds post no platforms (D35, D36), so the server's pill is always the dash.

import { DELAY_MIN } from './alerts.ts';
import { format, strings } from './copy.ts';
import type { LiveStatus } from './realtime.ts';
import { formatTime, MINUTE, type TimeFormat } from './time.ts';

/** The window opens this long before the expected departure (`LiveDeparture.window`). */
export const WINDOW_MS = 30 * MINUTE;
/** "Boarding now" from this long before the expected departure. */
export const BOARDING_MS = 2 * MINUTE;
/** The question after departure stays this long at most, then the activity ends (TT-231, `LiveDeparture.askFor`). */
export const ASK_MS = 10 * MINUTE;

/** The activity type's name in the app, which a push-to-start names (`attributes-type`). */
export const ATTRIBUTES_TYPE = 'RideActivityAttributes';

/** GO Transit's line colours by line id (`GOLineColor.hex` in the app, D49). */
export const LINE_COLORS: Record<string, string> = {
  LW: '#8B1A31',
  LE: '#EA3624',
  MI: '#E6853E',
  KI: '#3A8346',
  RH: '#4397C3',
  BR: '#143664',
  ST: '#724715',
};

/**
 * `asking` is the question (TT-231). On the wire it is `departed` with `asks`, so an app build from before TT-231 still
 * reads the push (as its Departed card); `departed` alone is the end push's last look.
 */
export type Phase = 'countingDown' | 'boarding' | 'asking' | 'departed';

/** An alerted train before it leaves, as the server knows it. */
export interface Departure {
  /** Scheduled departure from the rider's origin and arrival at their destination, epoch ms. */
  scheduled: number;
  scheduledArrival: number;
  /** The live status at the origin; null on the timetable alone. */
  status: LiveStatus | null;
  /** Station names as the rule carries them, "Union Station GO". */
  origin: string;
  destination: string;
}

/** The activity's fixed part: which ride it is (the app's `Ride`), the line's tile, your stop and the stop count. */
export interface Attributes {
  tripId: string;
  serviceDate: number;
  originId: string;
  destinationId: string;
  lineCode: string;
  lineColorHex: string | null;
  destinationName: string;
  stopCount: number;
}

/** The app's `ContentState`, key for key; `countdownEnd` is seconds since 1970. No `platformNumber`: the dash. */
export interface ContentState {
  phase: Exclude<Phase, 'asking'>;
  /** The card asks "On board?" with Yes and No (TT-231). */
  asks?: boolean;
  title: string;
  countdownEnd?: number;
  /** The big number in whole minutes, "12 min" (TT-219): sent again each minute, since iOS has no live "12 min" text. */
  minutes?: string;
  now: string;
  label: string;
  delay?: string;
  late: boolean;
  position: number;
  isClose: boolean;
  updated: string;
}

/** "Clarkson GO" reads "Clarkson" (the app's `RideDetails.shortName`). */
export function shortName(name: string): string {
  return name.endsWith(' GO') ? name.slice(0, -3) : name;
}

function isRunning(status: LiveStatus | null): status is Extract<LiveStatus, { kind: 'running' }> {
  return status?.kind === 'running';
}

/** The expected departure, else the scheduled one. */
export function leaves(departure: Departure): number {
  return isRunning(departure.status) ? departure.status.expected : departure.scheduled;
}

/** The expected arrival at the rider's stop: the scheduled one moved by the departure's delay. */
export function arrives(departure: Departure): number {
  return departure.scheduledArrival + (leaves(departure) - departure.scheduled);
}

/** When the question ends: 10 min after the expected departure, or at the rider's stop if sooner (`LiveDeparture.endsAt`). */
export function endsAt(departure: Departure): number {
  const leavesAt = leaves(departure);
  return Math.min(leavesAt + ASK_MS, Math.max(arrives(departure), leavesAt));
}

/**
 * Where the train is at `now`: before its window, counting down, boarding (the last 2 min), asking (from the expected
 * departure until `endsAt`), or over. A cancelled train or a skipped stop is over at once: it never goes live (D69).
 */
export function phaseAt(departure: Departure, now: number): Exclude<Phase, 'departed'> | 'before' | 'over' {
  if (departure.status && departure.status.kind !== 'running') return 'over';
  const until = leaves(departure) - now;
  if (until > WINDOW_MS) return 'before';
  if (until > BOARDING_MS) return 'countingDown';
  if (until > 0) return 'boarding';
  return now < endsAt(departure) ? 'asking' : 'over';
}

/**
 * The activity at `now` in `phase`, as the app writes it (`ContentState(departure:…)`): the expected departure's clock time
 * in the line and the countdown to it, "3 min late" beside it while late.
 */
export function contentState(departure: Departure, phase: Phase, now: number, timeFormat: TimeFormat): ContentState {
  const time = (ms: number) => formatTime(ms, timeFormat);
  const status = departure.status;
  const leavesAt = leaves(departure);
  const delay = isRunning(status) && status.delayMin >= DELAY_MIN ? status.delayMin : null;
  const left = phase === 'asking' || phase === 'departed';
  const late = !left && delay !== null;
  const title =
    phase === 'boarding'
      ? format(strings['depart.boardingLine'], time(leavesAt))
      : phase === 'asking'
        ? format(strings['depart.ask.line'], time(leavesAt))
        : phase === 'departed'
          ? format(strings['depart.departed'], time(leavesAt))
          : format(strings['depart.line'], time(leavesAt));
  const state: ContentState = {
    phase: phase === 'asking' ? 'departed' : phase,
    title,
    now: '',
    label: phase === 'asking' ? '' : strings['depart.platformLabel'],
    late,
    position: 0,
    isClose: phase === 'boarding',
    updated: format(strings['live.updated'], time(now)),
  };
  if (phase === 'asking') state.asks = true;
  if (late) state.delay = format(strings['onboard.late'], delay);
  if (!left) {
    state.countdownEnd = Math.round(leavesAt / 1000);
    state.minutes = format(strings['onboard.minutes'], minutesUntil(leavesAt, now));
  }
  return state;
}

/** Whole minutes until the train leaves, as the app counts them (`LiveDeparture.minutes(at:)`), and 1 at least. */
export function minutesUntil(leavesAt: number, now: number): number {
  return Math.max(1, Math.floor((leavesAt - now) / MINUTE));
}

/**
 * What a rider sees, the update time aside: an update is sent only when this changes, so once a minute for the minutes
 * (TT-219). The countdown counts to the half minute, so an expected time that moves by a few seconds sends nothing more
 * (the app allows 15 s).
 */
export function signature(state: ContentState): string {
  const countdown = state.countdownEnd === undefined ? '' : Math.round(state.countdownEnd / 30);
  return [state.phase, state.title, state.delay ?? '', countdown, state.minutes ?? '', state.asks ? 'asks' : ''].join('|');
}

/** The activity becomes stale, and the app ends it, when the question ends (`endsAt`). */
export function staleDate(departure: Departure): number {
  return endsAt(departure);
}

const seconds = (ms: number) => Math.floor(ms / 1000);

/**
 * `event: start`, sent once at T−30. It must carry an alert: iOS shows the expanded activity and plays the sound (iOS
 * 17.2+). The card's line with its minutes, "7:13 AM departs in 30 min"; no body.
 */
export function startPayload(departure: Departure, attributes: Attributes, state: ContentState, now: number, timeFormat: TimeFormat) {
  const leavesAt = leaves(departure);
  const minutes = minutesUntil(leavesAt, now);
  return {
    aps: {
      timestamp: seconds(now),
      event: 'start',
      'content-state': state,
      'stale-date': seconds(staleDate(departure)),
      'attributes-type': ATTRIBUTES_TYPE,
      attributes,
      alert: {
        title: format(strings['depart.live.title'], formatTime(leavesAt, timeFormat), minutes),
        body: '',
        sound: 'default',
      },
    },
  };
}

/**
 * `event: update`: the minutes, the delay or the phase changed. The question's update carries an alert (TT-231): the Lock
 * Screen lights up, the phone buzzes once, and the island opens on it; "On the 4:29 PM train?" names the train as its
 * notification does. Not when `silent`: the app was in front as the train left, where Schedule asks.
 */
export function updatePayload(departure: Departure, state: ContentState, now: number, timeFormat: TimeFormat = '12h', silent = false) {
  const aps: Record<string, unknown> = { timestamp: seconds(now), event: 'update', 'content-state': state, 'stale-date': seconds(staleDate(departure)) };
  if (state.asks && !silent) aps.alert = { title: askTitle(departure, timeFormat), body: '', sound: 'default' };
  return { aps };
}

/** "On the 4:29 PM train?": the train by its scheduled departure, as every notification names it (D9). */
export function askTitle(departure: Departure, timeFormat: TimeFormat): string {
  return format(strings['depart.ask.notif'], formatTime(departure.scheduled, timeFormat));
}

/** `event: end`, when the question ends (or at once for a cancelled train): it leaves the Lock Screen now. */
export function endPayload(state: ContentState, now: number) {
  return { aps: { timestamp: seconds(now), event: 'end', 'content-state': state, 'dismissal-date': seconds(now) } };
}
