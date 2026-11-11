// The before-departure Live Activity (TT-178, D74): an alerted train's countdown on the Lock Screen and in the Dynamic
// Island from 30 min before it leaves. The server starts it with a push-to-start (iOS 17.2+), updates it only when what it
// shows changes, and ends it 2 min after the train left, unless the app's ride took it over (the same activity becomes the
// ride). Every word is the app's (`RideActivityAttributes.ContentState` in `Shared/`), so an activity the app updates later
// looks the same. GO's feeds post no platforms (D35, D36), so the server's activity always says "Check the board".

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

/** The app's `ContentState`, key for key; `countdownEnd` is seconds since 1970. */
export interface ContentState {
  phase: Phase;
  title: string;
  detail: string;
  countdownEnd?: number;
  now: string;
  time: string;
  departure: string;
  arrival: string;
  arrives: string;
  position: number;
  button: string;
  updated: string;
  platform: string;
  pill: boolean;
  late: boolean;
}

/** "Clarkson GO" reads "Clarkson" (the app's `RideDetails.shortName`). */
export function shortName(name: string): string {
  return name.endsWith(' GO') ? name.slice(0, -3) : name;
}

/** "Union Station GO" reads "Union" on the activity's departure label (the app's `TrainQuestion.shortName`). */
function shorterName(name: string): string {
  const short = shortName(name);
  return short.endsWith(' Station') ? short.slice(0, -8) : short;
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

/** The activity at `now` in `phase`, as the app writes it (`ContentState(departure:…)`). */
export function contentState(departure: Departure, phase: Phase, now: number, timeFormat: TimeFormat): ContentState {
  const time = (ms: number) => formatTime(ms, timeFormat);
  const status = departure.status;
  const running = isRunning(status);
  const leavesAt = leaves(departure);
  const arrivesAt = departure.scheduledArrival + (running ? status.expected - departure.scheduled : 0);
  const delay = running && status.delayMin >= DELAY_MIN ? status.delayMin : null;
  const word =
    phase === 'boarding'
      ? strings['depart.boarding']
      : phase === 'departed'
        ? format(strings['depart.departed'], time(leavesAt))
        : delay !== null
          ? format(strings['depart.delayed'], delay)
          : running
            ? strings['status.on_time']
            : strings['status.scheduled'];
  const platform = strings['depart.checkBoard'];
  const arrival = format(strings['live.stopTime'], shortName(departure.destination), time(arrivesAt));
  const state: ContentState = {
    phase,
    title: format(strings['schedule.route_title'], time(departure.scheduled), shortName(departure.destination)),
    detail: format(strings['onboard.detail'], platform, word),
    now: '',
    time: phase === 'departed' ? '' : strings['depart.in'],
    departure: format(strings['live.stopTime'], shorterName(departure.origin), time(leavesAt)),
    arrival,
    arrives: format(strings['depart.arrives'], arrival),
    position: 0,
    button: strings['onboard.button'],
    updated: format(strings['live.updated'], time(now)),
    platform,
    pill: false,
    late: phase === 'countingDown' && delay !== null,
  };
  if (phase !== 'departed') state.countdownEnd = Math.round(leavesAt / 1000);
  return state;
}

/** What a rider sees, the update time aside: an update is sent only when this changes. */
export function signature(state: ContentState): string {
  return [state.phase, state.title, state.detail, state.departure, state.arrival, state.countdownEnd ?? ''].join('|');
}

/** The activity becomes stale, and the app ends it, 2 min after the expected departure. */
export function staleDate(departure: Departure): number {
  return leaves(departure) + DEPARTED_MS;
}

const seconds = (ms: number) => Math.floor(ms / 1000);

/**
 * `event: start`, sent once at T−30. It must carry an alert: iOS shows the expanded activity and plays the sound (iOS
 * 17.2+). "Your 5:13 PM train is live", the route under it.
 */
export function startPayload(departure: Departure, attributes: Attributes, state: ContentState, now: number, timeFormat: TimeFormat) {
  return {
    aps: {
      timestamp: seconds(now),
      event: 'start',
      'content-state': state,
      'stale-date': seconds(staleDate(departure)),
      'attributes-type': ATTRIBUTES_TYPE,
      attributes,
      alert: {
        title: format(strings['depart.live.title'], formatTime(departure.scheduled, timeFormat)),
        body: format(strings['schedule.route_title'], departure.origin, departure.destination),
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
