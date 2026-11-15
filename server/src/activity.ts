// The before-departure Live Activity (TT-178, D74): an alerted train's countdown on the Lock Screen and in the Dynamic
// Island from 30 min before it leaves. The server starts it with a push-to-start (iOS 17.2+), updates it only when what it
// shows changes, and ends it 2 min after the train left, unless the app's ride took it over (the same activity becomes the
// ride). Every word is the app's (`RideActivityAttributes.ContentState` in `Shared/`), so an activity the app updates later
// looks the same: one card for every moment (TT-205, D92), "7:13 AM departs in" over the minutes, "Platform" and the pill.
// GO's feeds post no platforms (D35, D36), so the server's pill is always the dash.

import { DELAY_MIN } from './alerts.ts';
import { format, strings } from './copy.ts';
import type { LiveStatus } from './realtime.ts';
import { formatTime, MINUTE, type TimeFormat } from './time.ts';

/** The window opens this long before the expected departure (`LiveDeparture.window`). */
export const WINDOW_MS = 30 * MINUTE;
/** "Boarding now" from this long before the expected departure. */
export const BOARDING_MS = 2 * MINUTE;
/** "Departed" stays this long, then the activity ends. */
export const DEPARTED_MS = 2 * MINUTE;

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

export type Phase = 'countingDown' | 'boarding' | 'departed';

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
  phase: Phase;
  title: string;
  countdownEnd?: number;
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

/**
 * Where the train is at `now`: before its window, counting down, boarding (the last 2 min), departed (2 min from the
 * expected departure), or over. A cancelled train or a skipped stop is over at once: it never goes live (D69).
 */
export function phaseAt(departure: Departure, now: number): Phase | 'before' | 'over' {
  if (departure.status && departure.status.kind !== 'running') return 'over';
  const until = leaves(departure) - now;
  if (until > WINDOW_MS) return 'before';
  if (until > BOARDING_MS) return 'countingDown';
  if (until > 0) return 'boarding';
  return until > -DEPARTED_MS ? 'departed' : 'over';
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
  const late = phase !== 'departed' && delay !== null;
  const title =
    phase === 'boarding'
      ? format(strings['depart.boardingLine'], time(leavesAt))
      : phase === 'departed'
        ? format(strings['depart.departed'], time(leavesAt))
        : format(strings['depart.line'], time(leavesAt));
  const state: ContentState = {
    phase,
    title,
    now: '',
    label: strings['depart.platformLabel'],
    late,
    position: 0,
    isClose: phase === 'boarding',
    updated: format(strings['live.updated'], time(now)),
  };
  if (late) state.delay = format(strings['onboard.late'], delay);
  if (phase !== 'departed') state.countdownEnd = Math.round(leavesAt / 1000);
  return state;
}

/**
 * What a rider sees, the update time aside: an update is sent only when this changes. The countdown counts to the half
 * minute, so an expected time that moves by a few seconds sends nothing (the app allows 15 s).
 */
export function signature(state: ContentState): string {
  const countdown = state.countdownEnd === undefined ? '' : Math.round(state.countdownEnd / 30);
  return [state.phase, state.title, state.delay ?? '', countdown].join('|');
}

/** The activity becomes stale, and the app ends it, 2 min after the expected departure. */
export function staleDate(departure: Departure): number {
  return leaves(departure) + DEPARTED_MS;
}

const seconds = (ms: number) => Math.floor(ms / 1000);

/**
 * `event: start`, sent once at T−30. It must carry an alert: iOS shows the expanded activity and plays the sound (iOS
 * 17.2+). The card's line with its minutes, "7:13 AM departs in 30 min"; no body.
 */
export function startPayload(departure: Departure, attributes: Attributes, state: ContentState, now: number, timeFormat: TimeFormat) {
  const leavesAt = leaves(departure);
  const minutes = Math.max(1, Math.floor((leavesAt - now) / MINUTE));
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

/** `event: update`: the platform, the delay or the phase changed. */
export function updatePayload(departure: Departure, state: ContentState, now: number) {
  return { aps: { timestamp: seconds(now), event: 'update', 'content-state': state, 'stale-date': seconds(staleDate(departure)) } };
}

/** `event: end`, 2 min after the train left (or at once for a cancelled train): it leaves the Lock Screen now. */
export function endPayload(state: ContentState, now: number) {
  return { aps: { timestamp: seconds(now), event: 'end', 'content-state': state, 'dismissal-date': seconds(now) } };
}
