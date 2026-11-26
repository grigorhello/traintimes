import { formatTime, type TimeFormat } from './time.ts';

/**
 * The notification copy, word for word from `design/handoff/Localizable.strings` (D19). `test/copy.test.ts` fails when
 * a value here drifts from that file, so change both in the same PR.
 */
export const strings = {
  'schedule.route_title': '%@ to %@',
  'notif.delay.title': '%1$@ train delayed %2$@',
  'notif.delay.update.title': '%1$@ train now delayed %2$@',
  'notif.delay.body': '%@. Now expected %@, as reported at %@.',
  'notif.recovery.title': '%@ train back on time',
  'notif.recovery.body': '%@. Expected %@, as reported at %@.',
  'notif.cancel.title': '%@ train cancelled',
  'notif.cancel.body': '%@. Cancelled, as reported at %@. Open to see the next trains.',
  'notif.skip.title': '%@ train will skip %@',
  'notif.skip.body': 'Skips %@, as reported at %@. Open to see the next trains.',
  'notif.rule.title': 'Your usual train has changed',
  'notif.rule.body': 'Review your %@ weekday alert.',
  // The before-departure Live Activity (TT-178, TT-205, src/activity.ts).
  'depart.live.title': '%1$@ departs in %2$d min',
  // The departure question (TT-231, D110).
  'depart.ask.line': '%@ departed',
  'depart.ask.notif': 'On the %@ train?',
  'depart.line': '%@ departs in',
  'depart.boardingLine': '%@ boarding now',
  'depart.departed': 'Departed %@',
  'depart.platformLabel': 'Platform',
  // In the minutes' place once the train's time has come and it still stands at the station (TT-233).
  'schedule.departing': 'Departing',
  'onboard.late': '%@ late',
  'live.updated': 'Updated %@',
  // A count of minutes, one wording everywhere minutes show (TT-246, D123): never "75 min", always "1 h 15 min".
  'duration.minutes': '%d min',
  'duration.hours': '%d h',
  'duration.hours_minutes': '%1$d h %2$d min',
  'duration.days': '%d d',
  'duration.days_hours': '%1$d d %2$d h',
} as const;

/**
 * A count of minutes as the app writes it (`TimeFormatter.duration(minutes:)`, TT-246, D123): "45 min" under an hour,
 * "1 h 20 min" ("1 h" on the hour) under a day, then "1 d 5 h" ("2 d" on the day). The caller rounds the minutes.
 */
export function duration(minutes: number): string {
  const whole = Math.max(0, Math.trunc(minutes));
  if (whole < 60) return format(strings['duration.minutes'], whole);
  if (whole < 24 * 60) {
    const hours = Math.floor(whole / 60);
    const rest = whole % 60;
    return rest === 0 ? format(strings['duration.hours'], hours) : format(strings['duration.hours_minutes'], hours, rest);
  }
  const days = Math.floor(whole / (24 * 60));
  const hours = Math.floor(whole / 60) % 24;
  return hours === 0 ? format(strings['duration.days'], days) : format(strings['duration.days_hours'], days, hours);
}

/** Fills `%@` and `%d` in order, and `%1$@` by position, as `String(format:)` does in the app. */
export function format(template: string, ...args: (string | number)[]): string {
  let next = 0;
  return template.replace(/%(?:(\d+)\$)?[@d]/g, (_, position?: string) => String(args[position ? Number(position) - 1 : next++]));
}

export interface Notice {
  title: string;
  body: string;
}

/** A trip alert the rules decided to send (Notification rules and copy, rules 3 and 4). */
export type Alert =
  | { kind: 'delay'; delayMin: number; expected: number; update: boolean }
  | { kind: 'recovery'; delayMin: number; expected: number }
  | { kind: 'cancelled' }
  | { kind: 'skipped'; stop: 'origin' | 'destination' };

export interface Direction {
  origin: string;
  destination: string;
}

/**
 * The title names the train by its scheduled departure, which never changes (D9); the body names the direction, the
 * expected time and when the change was reported, one fact per sentence.
 */
export function alertNotice(
  alert: Alert,
  scheduledDeparture: number,
  direction: Direction,
  reportedAt: number,
  timeFormat: TimeFormat,
): Notice {
  const train = formatTime(scheduledDeparture, timeFormat);
  const route = format(strings['schedule.route_title'], direction.origin, direction.destination);
  const reported = formatTime(reportedAt, timeFormat);
  switch (alert.kind) {
    case 'delay':
      return {
        title: format(strings[alert.update ? 'notif.delay.update.title' : 'notif.delay.title'], train, duration(alert.delayMin)),
        body: format(strings['notif.delay.body'], route, formatTime(alert.expected, timeFormat), reported),
      };
    case 'recovery':
      return {
        title: format(strings['notif.recovery.title'], train),
        body: format(strings['notif.recovery.body'], route, formatTime(alert.expected, timeFormat), reported),
      };
    case 'cancelled':
      return {
        title: format(strings['notif.cancel.title'], train),
        body: format(strings['notif.cancel.body'], route, reported),
      };
    case 'skipped': {
      const stop = alert.stop === 'origin' ? direction.origin : direction.destination;
      return {
        title: format(strings['notif.skip.title'], train, stop),
        body: format(strings['notif.skip.body'], stop, reported),
      };
    }
  }
}

/** "Your usual train has changed": a repeating rule's train moved or disappeared (rule 7). */
export function reviewNotice(direction: Direction): Notice {
  return {
    title: strings['notif.rule.title'],
    body: format(strings['notif.rule.body'], format(strings['schedule.route_title'], direction.origin, direction.destination)),
  };
}
