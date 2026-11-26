// The before-departure Live Activity (TT-178, D74): an alerted train's countdown on the Lock Screen and in the Dynamic
// Island from 30 min before it leaves. The server starts it with a push-to-start (iOS 17.2+), updates it only when what it
// shows changes, and once the train has left turns it into the question "On board?" with Yes and No, with an alert (TT-231,
// D110); with no card to update it sends the question as a notification instead. While the app's automatic-ride watch
// decides whether the rider left with the train (TT-242, D120), the app asks the server to hold that buzz: the question
// comes silently and the notification waits, until the app lets go or the hold ends by itself (`holdEnds`). It ends 10 min
// after the train left, or at the rider's stop if sooner, unless the app's ride took it over (the same activity becomes
// the ride) or the rider said No, and at once when its alert is removed, switched off or needs review (TT-240, D118: the
// minute cycle's sweep). Every word is the app's (`RideActivityAttributes.ContentState` in `Shared/`), so an activity the
// app updates later looks the same: one card for every moment (TT-205, D93), "7:13 AM departs in" over the minutes,
// "Platform" and the pill.
//
// Boarding at the platform (TT-233, D114): "boarding now" and the moment the train has left follow `boardingPhase`, the
// port of the app's `BoardingRule` (`Sources/Core/Schedule/BoardingRule.swift`; change both together). The minute cycle
// gives it where GO's train feed places the train, whether the feed still lists the rider's station, and the platform the
// station's board posts (`src/monitor.ts`). With no fresh position the clock decides, as before: boarding for the last 2
// min, left at its time. The pill carries the platform the station's board posts, planned or posted, from the window's
// start (TT-245, D122: before it, only while the train stood there), and the dash while it posts none or was not read.
//
// Two buzzes (TT-245, D122): the update that asks with its alert goes twice, ECHO_MS apart (`echo` in `src/monitor.ts`).

import { DELAY_MIN } from './alerts.ts';
import { format, strings } from './copy.ts';
import type { LiveStatus } from './realtime.ts';
import { formatTime, MINUTE, type TimeFormat } from './time.ts';

/** The window opens this long before the expected departure (`LiveDeparture.window`). */
export const WINDOW_MS = 30 * MINUTE;
/** "Boarding now" from this long before the expected departure, when no position says where the train is. */
export const BOARDING_MS = 2 * MINUTE;
/** The question after departure stays this long at most, then the activity ends (TT-231, `LiveDeparture.askFor`). */
export const ASK_MS = 10 * MINUTE;
/** The question's second alert follows the first by this much, so the phone vibrates twice (TT-245, D122). */
export const ECHO_MS = 1_500;
/** A train this close to the station's place stands at it (`BoardingRule.radius`, TT-233). */
export const BOARDING_RADIUS_M = 350;
/** A position older than this says nothing (`BoardingRule.fixMaxAge`). */
export const POSITION_FRESH_MS = 2 * MINUTE;
/** The feed's word that the train has left counts from this long before its time (`BoardingRule.departLead`). */
export const DEPART_LEAD_MS = MINUTE;
/** The app's hold on the question's buzz ends by itself this long after the expected departure at the latest (TT-242). */
export const HOLD_MS = 7 * MINUTE;
/** ...and this long before the question ends, if that is sooner (a short ride, TT-242). */
export const HOLD_MARGIN_MS = 90 * 1000;

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
  /**
   * How far GO's train feed places the train from the rider's origin station, and when it did, epoch ms (the app's
   * `OriginFix`, TT-233). Null or left out when the feed does not carry the train: it follows the clock.
   */
  position?: { metres: number; at: number } | null;
  /** The origin has dropped out of the trip's TripUpdates: the train has left it (`hasLeftOrigin` in `realtime.ts`). */
  hasLeftOrigin?: boolean;
  /** The platform the origin's board posts for the train, "7/8" at Union; null or left out while none is posted or the board was not read. */
  platform?: string | null;
  /**
   * The platform the card already shows (`platformIn` of its stored signature), set only while the origin's board was not
   * read this cycle (TT-245, D122): the pill keeps it rather than dropping to the dash. Never counts for boarding.
   */
  keptPlatform?: string | null;
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
  phase: Exclude<Phase, 'asking'>;
  /** The card asks "On board?" with Yes and No (TT-231). */
  asks?: boolean;
  title: string;
  countdownEnd?: number;
  /**
   * The big number in whole minutes, "12 min" (TT-219): sent again each minute, since iOS has no live "12 min" text.
   * "Departing" once the train's time has come and it has not left (TT-233).
   */
  minutes?: string;
  now: string;
  label: string;
  delay?: string;
  /** The posted platform in its pill, "3", Union's pair "7/8" (TT-233, TT-245); left out, the app draws the dash. */
  platformNumber?: string;
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
 * When the server lets go of the app's hold by itself (TT-242, D120): 7 min after the expected departure, or 90 s before
 * the question ends if sooner, so the released question still comes inside a short ride's window. The app's watch lets
 * go sooner (3 min after the train left, 6 min after its time at the latest); this covers an app that died, was suspended
 * or lost the network.
 */
export function holdEnds(departure: Departure): number {
  return Math.min(leaves(departure) + HOLD_MS, endsAt(departure) - HOLD_MARGIN_MS);
}

/** What said the train has left: its position is away from the station, the feed dropped the station, or its time came. */
export type DepartedBy = 'moved' | 'feed' | 'clock';

/** `BoardingRule.Phase`: not at the platform as far as anyone knows and not left, standing there with its platform posted, or left. */
export type BoardingPhase = { kind: 'waiting' } | { kind: 'boarding' } | { kind: 'departed'; source: DepartedBy };

/**
 * Boarding at the platform (TT-233, D114): the app's `BoardingRule.phase(of:now:)`, check for check and in its order.
 *
 * - Boarding while GO's train feed places the train within 350 m of the rider's station, not more than 2 min ago, and its
 *   platform is posted. It stays boarding past its time while the train stands there.
 * - Departed when the origin has dropped out of the trip's TripUpdates (from 1 min before its time), or its position is
 *   farther than 350 m once its time has come. In the minute before its time a far position alone is not a departure: a
 *   train still rolling in is as far away.
 * - No fresh position: the clock, as before. Never boarding on a guess.
 * - Cancelled trains and skipped stops never board; they follow the clock.
 */
export function boardingPhase(departure: Departure, now: number): BoardingPhase {
  const leavesAt = leaves(departure);
  const clock: BoardingPhase = now >= leavesAt ? { kind: 'departed', source: 'clock' } : { kind: 'waiting' };
  if (departure.status && departure.status.kind !== 'running') return clock;
  if (departure.hasLeftOrigin && now >= leavesAt - DEPART_LEAD_MS) return { kind: 'departed', source: 'feed' };
  const position = departure.position;
  if (!position || !hasSighting(departure, now)) return clock;
  if (position.metres <= BOARDING_RADIUS_M) {
    // Never departed while it stands there, whatever the clock says; boarding only once the platform is posted.
    return departure.platform ? { kind: 'boarding' } : { kind: 'waiting' };
  }
  return now >= leavesAt ? { kind: 'departed', source: 'moved' } : { kind: 'waiting' };
}

/** The train feed placed the train recently enough to go by (`BoardingRule.hasSighting`): nothing is guessed from the clock. */
export function hasSighting(departure: Pick<Departure, 'position'>, now: number): boolean {
  return !!departure.position && now - departure.position.at <= POSITION_FRESH_MS;
}

/**
 * Where the train is at `now` (the app's `LiveDeparture`): before its window, counting down, boarding, asking (once it has
 * left, until `endsAt`), or over. Boarding and left are `boardingPhase`'s (TT-233): a train standing at the station past
 * its time stays boarding until the window ends, and it asks when it moves off. With no fresh position the last 2 min
 * read boarding and it has left at its time, by the clock (D69). A cancelled train or a skipped stop is over at once: it
 * never goes live.
 */
export function phaseAt(departure: Departure, now: number): Exclude<Phase, 'departed'> | 'before' | 'over' {
  if (departure.status && departure.status.kind !== 'running') return 'over';
  const until = leaves(departure) - now;
  if (until > WINDOW_MS) return 'before';
  if (now >= endsAt(departure)) return 'over';
  const rule = boardingPhase(departure, now);
  if (rule.kind === 'departed') return 'asking';
  if (rule.kind === 'boarding') return 'boarding';
  return !hasSighting(departure, now) && until <= BOARDING_MS ? 'boarding' : 'countingDown';
}

/**
 * The activity at `now` in `phase`, as the app writes it (`ContentState(departure:…)`): the expected departure's clock time
 * in the line and the countdown to it, "3 min late" beside it while late; "Departing" in the minutes' place once its time
 * has come and it has not left, and the posted platform in the pill when the cycle read it (TT-233, TT-245).
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
    // Never "1 min" for a train that stands at its platform past its time (`LiveDeparture.isDeparting`).
    state.minutes = now >= leavesAt ? strings['schedule.departing'] : format(strings['onboard.minutes'], minutesUntil(leavesAt, now));
    const platform = departure.platform ?? departure.keptPlatform;
    if (platform) state.platformNumber = platform;
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
 * (the app allows 15 s). The platform is added only when there is one, so a signature stored before TT-233 still matches
 * the same look.
 */
export function signature(state: ContentState): string {
  const countdown = state.countdownEnd === undefined ? '' : Math.round(state.countdownEnd / 30);
  const parts = [state.phase, state.title, state.delay ?? '', countdown, state.minutes ?? '', state.asks ? 'asks' : ''];
  if (state.platformNumber) parts.push(`platform ${state.platformNumber}`);
  return parts.join('|');
}

/** The stored signature is the question's: `signature` of a state that asks, which carries no platform, so it ends there. */
/** The platform in a stored signature ("…|platform 7/8", `signature`), null without one (TT-245). */
export function platformIn(shown: string | null): string | null {
  const part = shown?.split('|').find((piece) => piece.startsWith('platform '));
  return part ? part.slice('platform '.length) : null;
}

export function asksIn(shown: string | null): boolean {
  return shown?.endsWith('|asks') ?? false;
}

/**
 * The stored signature with the question's mark taken off (TT-242, D120): a hold that ends with the question already on
 * the card makes the next update its question again, and so it goes with its alert. Kept rather than set to NULL, so the
 * sweep, which skips rows without `shown`, still sees the card. `releaseHold` in `src/api.ts` does the same in SQL.
 */
export function withoutAsks(shown: string | null): string | null {
  return shown !== null && asksIn(shown) ? shown.slice(0, -'|asks'.length) : shown;
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
 * Screen lights up, the phone buzzes, and the island opens on it; "On the 4:29 PM train?" names the train as its
 * notification does. The cycle sends it twice for two buzzes (TT-245). Not when `silent`: the app was in front as the
 * train left, where Schedule asks.
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

/**
 * The last look of a card that ends because no alert watches its train any more (TT-240, D118): the line it last showed,
 * read back from its stored signature, as Departed. The rule that knew the train is gone, and the card leaves the Lock
 * Screen with this push, so nothing more is worked out for it.
 */
export function sweptState(shown: string): ContentState {
  const title = shown.split('|')[1] ?? '';
  return { phase: 'departed', title, now: '', label: '', late: false, position: 0, isClose: false, updated: '' };
}
