// The GO rail timetable the server needs to watch trips and resolve repeating rules: the same public GTFS feed the app
// imports (TT-130, D35), read from the zip in a stream so the whole network's stop_times never sit in memory.

import { addDays, isoWeekday } from './time.ts';

export const GTFS_URL = 'https://assets.metrolinx.com/raw/upload/Documents/Metrolinx/Open%20Data/GO-GTFS.zip';

/** One rail trip on one service date. Times are GTFS seconds after noon minus 12 h. */
export interface TimetableTrip {
  /** The line's short name, "LW". */
  line: string;
  stops: string[];
  arrivals: number[];
  departures: number[];
}

/** One service date's rail trips by trip id. */
export type Timetable = Record<string, TimetableTrip>;

// MARK: Zip

interface ZipEntry {
  method: number;
  compressedSize: number;
  headerOffset: number;
}

/** The central directory, keyed by file name without its folder. No ZIP64, as in the app's `ZipArchive`. */
function zipEntries(zip: Uint8Array): Map<string, ZipEntry> {
  const view = new DataView(zip.buffer, zip.byteOffset, zip.byteLength);
  let end = zip.length - 22;
  const lowest = Math.max(0, zip.length - 22 - 0xffff);
  while (end >= lowest && view.getUint32(end, true) !== 0x06054b50) end--;
  if (end < lowest) throw new Error('Not a zip');
  const entries = new Map<string, ZipEntry>();
  let offset = view.getUint32(end + 16, true);
  const count = view.getUint16(end + 10, true);
  for (let i = 0; i < count; i++) {
    if (view.getUint32(offset, true) !== 0x02014b50) throw new Error('Corrupt zip central directory');
    const nameLength = view.getUint16(offset + 28, true);
    const path = new TextDecoder().decode(zip.subarray(offset + 46, offset + 46 + nameLength));
    if (!path.endsWith('/')) {
      entries.set(path.split('/').pop()!, {
        method: view.getUint16(offset + 10, true),
        compressedSize: view.getUint32(offset + 20, true),
        headerOffset: view.getUint32(offset + 42, true),
      });
    }
    offset += 46 + nameLength + view.getUint16(offset + 30, true) + view.getUint16(offset + 32, true);
  }
  return entries;
}

/** A file's lines, inflated as a stream. Empty when the zip has no such file. */
async function* zipLines(zip: Uint8Array, entries: Map<string, ZipEntry>, name: string): AsyncGenerator<string> {
  const entry = entries.get(name);
  if (!entry) return;
  const view = new DataView(zip.buffer, zip.byteOffset, zip.byteLength);
  const header = entry.headerOffset;
  if (view.getUint32(header, true) !== 0x04034b50) throw new Error(`Corrupt zip entry ${name}`);
  const start = header + 30 + view.getUint16(header + 26, true) + view.getUint16(header + 28, true);
  const data = zip.slice(start, start + entry.compressedSize);
  let stream: ReadableStream<Uint8Array> = new Blob([data]).stream();
  if (entry.method === 8) stream = stream.pipeThrough(new DecompressionStream('deflate-raw'));
  else if (entry.method !== 0) throw new Error(`Unsupported zip compression ${entry.method}`);

  let rest = '';
  for await (const chunk of stream.pipeThrough(new TextDecoderStream())) {
    const lines = (rest + chunk).split('\n');
    rest = lines.pop()!;
    yield* lines;
  }
  if (rest) yield rest;
}

// MARK: CSV

/** Fields of one CSV line; quoted fields may hold commas and "" for a quote mark. */
function fields(line: string): string[] {
  if (!line.includes('"')) return line.split(',');
  const result: string[] = [];
  let field = '';
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (quoted) {
      if (c === '"' && line[i + 1] === '"') {
        field += '"';
        i++;
      } else if (c === '"') quoted = false;
      else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ',') {
      result.push(field);
      field = '';
    } else field += c;
  }
  result.push(field);
  return result;
}

/** Calls `body` with each record of a GTFS file by column name. With `keep`, other rows are skipped before splitting. */
async function forEachRecord(
  lines: AsyncGenerator<string>,
  body: (record: (column: string) => string) => void,
  keep?: { column: string; test: (value: string) => boolean },
): Promise<void> {
  let columns: Map<string, number> | null = null;
  let keepIndex = -1;
  for await (let line of lines) {
    if (line.endsWith('\r')) line = line.slice(0, -1);
    if (!line) continue;
    if (!columns) {
      const names = fields(line.replace(/^﻿/, '')).map((name) => name.trim());
      columns = new Map(names.map((name, index) => [name, index]));
      keepIndex = keep ? (columns.get(keep.column) ?? -1) : -1;
      continue;
    }
    let values: string[] | null = null;
    if (keep && keepIndex >= 0) {
      values = fields(line);
      if (!keep.test(values[keepIndex] ?? '')) continue;
    }
    const row = values ?? fields(line);
    const map = columns;
    body((column) => {
      const index = map.get(column);
      return index === undefined ? '' : (row[index] ?? '');
    });
  }
}

/** "25:10:00" to seconds; null when empty. */
function gtfsTime(value: string): number | null {
  const parts = value.trim().split(':');
  if (parts.length !== 3) return null;
  return Number(parts[0]) * 3600 + Number(parts[1]) * 60 + Number(parts[2]);
}

// MARK: Import

/**
 * Reads the rail trips (route_type 2) that run on the given service dates. Service dates come from calendar.txt
 * weekly patterns, then calendar_dates.txt additions and removals; GO publishes each date as its own service.
 */
export async function importTimetables(zip: Uint8Array, dates: string[]): Promise<Map<string, Timetable>> {
  const entries = zipEntries(zip);
  const wanted = new Set(dates);

  const lines = new Map<string, string>();
  await forEachRecord(zipLines(zip, entries, 'routes.txt'), (r) => {
    if (r('route_type') === '2') lines.set(r('route_id'), r('route_short_name') || r('route_id'));
  });

  const services = new Map<string, Set<string>>();
  const serviceDates = (id: string) => services.get(id) ?? services.set(id, new Set()).get(id)!;
  const weekdayColumns = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
  await forEachRecord(zipLines(zip, entries, 'calendar.txt'), (r) => {
    for (const date of wanted) {
      if (date >= r('start_date') && date <= r('end_date') && r(weekdayColumns[isoWeekday(date) - 1]) === '1') {
        serviceDates(r('service_id')).add(date);
      }
    }
  });
  await forEachRecord(zipLines(zip, entries, 'calendar_dates.txt'), (r) => {
    const date = r('date');
    if (!wanted.has(date)) return;
    if (r('exception_type') === '1') serviceDates(r('service_id')).add(date);
    else if (r('exception_type') === '2') services.get(r('service_id'))?.delete(date);
  });

  const trips = new Map<string, { line: string; dates: Set<string>; calls: [number, string, number, number][] }>();
  await forEachRecord(zipLines(zip, entries, 'trips.txt'), (r) => {
    const line = lines.get(r('route_id'));
    const running = services.get(r('service_id'));
    if (line && running && running.size > 0) trips.set(r('trip_id'), { line, dates: running, calls: [] });
  });

  await forEachRecord(
    zipLines(zip, entries, 'stop_times.txt'),
    (r) => {
      const arrival = gtfsTime(r('arrival_time'));
      const departure = gtfsTime(r('departure_time'));
      if (arrival === null && departure === null) return;
      trips.get(r('trip_id'))!.calls.push([
        Number(r('stop_sequence')),
        r('stop_id'),
        arrival ?? departure!,
        departure ?? arrival!,
      ]);
    },
    { column: 'trip_id', test: (id) => trips.has(id) },
  );

  const timetables = new Map<string, Timetable>(dates.map((date) => [date, {}]));
  for (const [tripId, trip] of trips) {
    if (trip.calls.length < 2) continue;
    trip.calls.sort((a, b) => a[0] - b[0]);
    const entry: TimetableTrip = {
      line: trip.line,
      stops: trip.calls.map((c) => c[1]),
      arrivals: trip.calls.map((c) => c[2]),
      departures: trip.calls.map((c) => c[3]),
    };
    for (const date of trip.dates) timetables.get(date)![tripId] = entry;
  }
  return timetables;
}

// MARK: Repeating rules

/** The train a repeating rule follows: a line, a direction and the scheduled departure from the origin. */
export interface UsualTrain {
  line: string;
  origin: string;
  destination: string;
  /** GTFS seconds of the scheduled departure from the origin. */
  departure: number;
  /** ISO weekdays, 1 is Monday. */
  weekdays: number[];
}

/** The trip on this date that is the usual train: same line, leaves the origin at the same time, then calls at the destination. */
export function findUsualTrain(timetable: Timetable, train: UsualTrain): string | null {
  for (const [tripId, trip] of Object.entries(timetable)) {
    if (trip.line !== train.line) continue;
    const from = trip.stops.indexOf(train.origin);
    if (from < 0 || trip.departures[from] !== train.departure) continue;
    if (trip.stops.indexOf(train.destination, from + 1) > from) return tripId;
  }
  return null;
}

/**
 * - trip: the usual train runs today.
 * - noTrain: not today, but it runs on another selected weekday in the next 7 days, so today is an exception
 *   (a holiday): "No matching train today", nothing sent (rule 8).
 * - changed: it runs on none of the selected weekdays in the next 7 days the timetable covers: the schedule moved or
 *   removed it, so the rule needs review (rule 7). Never attached to another train.
 * - unknown: today's timetable is not imported; nothing is decided.
 */
export type Resolution = { kind: 'trip'; tripId: string } | { kind: 'noTrain' } | { kind: 'changed' } | { kind: 'unknown' };

export function resolveUsualTrain(
  train: UsualTrain,
  date: string,
  timetableOn: (date: string) => Timetable | undefined,
): Resolution {
  const today = timetableOn(date);
  if (!today) return { kind: 'unknown' };
  const tripId = findUsualTrain(today, train);
  if (tripId) return { kind: 'trip', tripId };
  let checked = 0;
  for (let days = 1; days <= 7; days++) {
    const later = addDays(date, days);
    if (!train.weekdays.includes(isoWeekday(later))) continue;
    const timetable = timetableOn(later);
    if (!timetable) continue;
    checked++;
    if (findUsualTrain(timetable, train)) return { kind: 'noTrain' };
  }
  return checked > 0 ? { kind: 'changed' } : { kind: 'noTrain' };
}
