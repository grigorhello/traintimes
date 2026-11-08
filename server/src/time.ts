// GO time rules on the server, matching the app's `TimeFormatter` and `ServiceDay` (D17, D18, D24).
// Instants are epoch milliseconds; service dates are GTFS "YYYYMMDD" strings.

const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

export type TimeFormat = '12h' | '24h';

const torontoParts = new Intl.DateTimeFormat('en-US', {
  timeZone: 'America/Toronto',
  hourCycle: 'h23',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
});

interface WallTime {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
}

/** The wall-clock time in Toronto at an instant. */
function toronto(ms: number): WallTime {
  const parts: Record<string, number> = {};
  for (const part of torontoParts.formatToParts(new Date(ms))) {
    if (part.type !== 'literal') parts[part.type] = Number(part.value);
  }
  return {
    year: parts.year,
    month: parts.month,
    day: parts.day,
    hour: parts.hour % 24,
    minute: parts.minute,
    second: parts.second,
  };
}

/** "7:32 AM" or "07:32" in Toronto, as the app's one formatter writes it (D24). */
export function formatTime(ms: number, format: TimeFormat): string {
  const { hour, minute } = toronto(ms);
  const mm = String(minute).padStart(2, '0');
  if (format === '24h') return `${String(hour).padStart(2, '0')}:${mm}`;
  const hour12 = hour % 12 === 0 ? 12 : hour % 12;
  return `${hour12}:${mm} ${hour < 12 ? 'AM' : 'PM'}`;
}

function parseDate(date: string): [number, number, number] {
  return [Number(date.slice(0, 4)), Number(date.slice(4, 6)), Number(date.slice(6, 8))];
}

function dateKey(utcMidnight: number): string {
  const d = new Date(utcMidnight);
  return `${d.getUTCFullYear()}${String(d.getUTCMonth() + 1).padStart(2, '0')}${String(d.getUTCDate()).padStart(2, '0')}`;
}

/** The GO service date at an instant: the day changes at 3:00 AM Toronto time (D24). */
export function serviceDate(ms: number): string {
  const wall = toronto(ms);
  const midnight = Date.UTC(wall.year, wall.month - 1, wall.day);
  return dateKey(wall.hour < 3 ? midnight - DAY : midnight);
}

export function addDays(date: string, days: number): string {
  const [y, m, d] = parseDate(date);
  return dateKey(Date.UTC(y, m - 1, d) + days * DAY);
}

/** ISO weekday of a service date: 1 is Monday, 7 is Sunday. */
export function isoWeekday(date: string): number {
  const [y, m, d] = parseDate(date);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay() || 7;
}

/**
 * The instant of a GTFS time on a service date. GTFS counts seconds from noon minus 12 h, so DST days keep their
 * wall-clock times and 25:10:00 is 1:10 AM the next morning (D35).
 */
export function gtfsInstant(date: string, seconds: number): number {
  let start = dayStarts.get(date);
  if (start === undefined) {
    const [y, m, d] = parseDate(date);
    const guess = Date.UTC(y, m - 1, d, 12);
    const wall = toronto(guess);
    const offset = Date.UTC(wall.year, wall.month - 1, wall.day, wall.hour, wall.minute, wall.second) - guess;
    start = guess - offset - 12 * HOUR;
    if (dayStarts.size > 100) dayStarts.clear();
    dayStarts.set(date, start);
  }
  return start + seconds * 1000;
}

/** Noon minus 12 h by service date: the time zone lookup is most of a minute cycle's CPU otherwise (D43). */
const dayStarts = new Map<string, number>();

/** Seconds after noon minus 12 h on the service date: the inverse of `gtfsInstant`. */
export function gtfsSeconds(date: string, ms: number): number {
  return Math.round((ms - gtfsInstant(date, 0)) / 1000);
}

export { MINUTE, HOUR, DAY };
