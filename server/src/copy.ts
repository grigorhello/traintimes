import { formatTime, type TimeFormat } from './time.ts';

/**
 * The notification copy, word for word from `design/handoff/Localizable.strings` (D19). `test/copy.test.ts` fails when
 * a value here drifts from that file, so change both in the same PR.
 */
export const strings = {
  'schedule.route_title': '%@ to %@',
  'notif.delay.title': '%@ train delayed %d min',
  'notif.delay.update.title': '%@ train now delayed %d min',
  'notif.delay.body': '%@. Now expected %@, as reported at %@.',
  'notif.recovery.title': '%@ train back on time',
  'notif.recovery.body': '%@. Expected %@, as reported at %@.',
  'notif.cancel.title': '%@ train cancelled',
  'notif.cancel.body': '%@. Cancelled, as reported at %@. Open to see the next trains.',
  'notif.skip.title': '%@ train will skip %@',
  'notif.skip.body': 'Skips %@, as reported at %@. Open to see the next trains.',
  'notif.rule.title': 'Your usual train has changed',
  'notif.rule.body': 'Review your %@ weekday alert.',
  // The before-departure Live Activity (TT-178, src/activity.ts).
  'depart.live.title': 'Your %@ train is live',
  'depart.checkBoard': 'Check the board',
  'depart.in': 'departs',
  'depart.delayed': 'Delayed %d min',
  'depart.boarding': 'Boarding now',
  'depart.departed': 'Departed %@',
  'depart.arrives': 'Arrives %@',
  'status.on_time': 'On time',
  'status.scheduled': 'Scheduled',
  'onboard.detail': '%@ · %@',
  'onboard.button': 'I’m on board',
  'live.stopTime': '%1$@ %2$@',
  'live.updated': 'Updated %@',
} as const;

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
        title: format(strings[alert.update ? 'notif.delay.update.title' : 'notif.delay.title'], train, alert.delayMin),
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
