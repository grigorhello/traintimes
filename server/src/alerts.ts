// The alert rules (Screen requirements § Notification rules and copy). Pure functions, so feed replays test them.

import type { Alert } from './copy.ts';
import type { LiveStatus } from './realtime.ts';
import { HOUR, MINUTE } from './time.ts';

/** A reported departure delay of 3 min or more is a delay (D12, rule 3). */
export const DELAY_MIN = 3;
/** A further delay update needs the delay to move by 5 min or more (rule 4). */
export const UPDATE_STEP_MIN = 5;
/** Rapid feed changes within 60 s become one notification (rule 4). */
export const COALESCE_MS = MINUTE;
/** Watching starts 60 min before the scheduled departure (rule 1). */
export const WATCH_BEFORE_MS = 60 * MINUTE;
/** The useful trip window ends 2 h after the scheduled departure: the APNs expiry and the end of watching (rule 6). */
export const WATCH_AFTER_MS = 2 * HOUR;
/** Live data older than this is stale and never starts an alert (Q2, D13). */
export const STALE_MS = 3 * MINUTE;

export type SentKind = 'delay' | 'recovery' | 'cancelled' | 'skipped-origin' | 'skipped-destination';

/** The last notification sent for a watched trip. */
export interface Sent {
  kind: SentKind;
  delayMin: number | null;
  at: number;
}

export function sentKind(alert: Alert): SentKind {
  return alert.kind === 'skipped' ? `skipped-${alert.stop}` : alert.kind;
}

/**
 * The notification to send now for a watched trip, or null. `last` is the last one sent for this trip.
 *
 * - First alert: a delay of 3 min or more, a cancellation, or a skipped origin or destination (rule 3). An alert enabled
 *   while a disruption is already known sends it on the first check (rule 2).
 * - Further alerts: the delay moved by 5 min or more, the status changed, or the train recovered to under 3 min late
 *   after an alert (rule 4). The same status is never sent twice.
 * - Nothing within 60 s of the last alert: the next check sends the latest status, so rapid changes coalesce.
 */
export function decide(last: Sent | null, status: LiveStatus | null, now: number): Alert | null {
  if (!status) return null;
  if (last && now - last.at < COALESCE_MS) return null;
  switch (status.kind) {
    case 'cancelled':
      return last?.kind === 'cancelled' ? null : { kind: 'cancelled' };
    case 'skipped':
      return last?.kind === `skipped-${status.stop}` ? null : { kind: 'skipped', stop: status.stop };
    case 'running': {
      const { delayMin, expected } = status;
      if (delayMin >= DELAY_MIN) {
        if (last?.kind !== 'delay') return { kind: 'delay', delayMin, expected, update: false };
        return Math.abs(delayMin - (last.delayMin ?? 0)) >= UPDATE_STEP_MIN
          ? { kind: 'delay', delayMin, expected, update: true }
          : null;
      }
      return last && last.kind !== 'recovery' ? { kind: 'recovery', expected } : null;
    }
  }
}

/** Watching runs from 60 min before the scheduled departure to the end of the trip window (rules 1 and 6). */
export function isWatching(scheduledDeparture: number, now: number): boolean {
  return now >= scheduledDeparture - WATCH_BEFORE_MS && now <= scheduledDeparture + WATCH_AFTER_MS;
}

/** APNs discards an alert still undelivered at the end of the trip window (rule 6). */
export function expiry(scheduledDeparture: number): number {
  return scheduledDeparture + WATCH_AFTER_MS;
}

/**
 * A reliable departure: the feed itself reports the departure from the rider's origin at or before the time it was
 * written. Time passing alone is not one, so a delayed train with no new estimate stays watched (rule 1).
 */
export function hasDeparted(status: LiveStatus | null, feedTime: number): boolean {
  return status?.kind === 'running' && status.expected <= feedTime;
}
