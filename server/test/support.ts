// Test helpers: an in-memory D1 over node:sqlite with the real schema, a fake APNs, and the repo's sample feeds.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync, type SQLInputValue } from 'node:sqlite';
import type { Push, PushResult } from '../src/apns.ts';
import { saveTimetable } from '../src/monitor.ts';
import { decodeFeed, type Feed } from '../src/realtime.ts';
import { importTimetables } from '../src/timetable.ts';

const repo = join(import.meta.dirname, '..', '..');

export function repoFile(path: string): Uint8Array {
  return new Uint8Array(readFileSync(join(repo, path)));
}

/** The TT-131 sample TripUpdates feeds: Lakeshore West at Oakville, Monday Nov 9, 2026, 7:00 to 7:02 AM. */
export function sampleFeed(time: '0700' | '0701' | '0702'): Feed {
  return decodeFeed(repoFile(`Tests/UnitTests/Core/Realtime/tripupdates-${time}.pb`));
}

/** The TT-130 sample GTFS: Lakeshore West and Kitchener trips on Nov 8, 9 and 27, 2026. */
export const sampleGTFS = () => repoFile('Tests/UnitTests/Core/GTFS/go-gtfs-sample.zip');

/** Stores the sample timetable for these dates, as the daily upload would (D43). */
export async function saveSampleTimetables(db: D1Database, dates: string[]): Promise<void> {
  for (const [date, trips] of await importTimetables(sampleGTFS(), dates)) {
    if (Object.keys(trips).length > 0) await saveTimetable(db, date, JSON.stringify(trips), Date.parse('2026-11-09T08:40:00Z'));
  }
}

/** Epoch ms of a Toronto wall-clock time on Monday Nov 9, 2026 (EST, UTC-5). */
export function at(hhmm: string, date = '2026-11-09'): number {
  const [h, m, s = '0'] = hhmm.split(':');
  return Date.parse(`${date}T00:00:00Z`) + ((Number(h) + 5) * 3600 + Number(m) * 60 + Number(s)) * 1000;
}

/** A D1 database in memory with `schema.sql` applied. Enough of the D1 API for the server. */
export function memoryD1(): D1Database {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec(readFileSync(join(repo, 'server', 'schema.sql'), 'utf8'));
  const statement = (sql: string, params: SQLInputValue[] = []) => ({
    bind: (...values: SQLInputValue[]) => statement(sql, values),
    first: async <T>() => {
      const row = sqlite.prepare(sql).get(...params);
      return (row ? { ...row } : null) as T | null;
    },
    all: async <T>() => ({ results: sqlite.prepare(sql).all(...params).map((row) => ({ ...row })) as T[], success: true, meta: {} }),
    run: async () => {
      const result = sqlite.prepare(sql).run(...params);
      return { results: [], success: true, meta: { changes: Number(result.changes) } };
    },
  });
  return {
    prepare: (sql: string) => statement(sql),
    batch: async (statements: { run(): Promise<unknown> }[]) => {
      sqlite.exec('BEGIN');
      try {
        const results = [];
        for (const s of statements) results.push(await s.run());
        sqlite.exec('COMMIT');
        return results;
      } catch (error) {
        sqlite.exec('ROLLBACK');
        throw error;
      }
    },
  } as unknown as D1Database;
}

/** Records every push and answers with `result` (or the next queued answer). */
export class FakeApns {
  pushes: Push[] = [];
  answers: PushResult[] = [];
  result: PushResult = 'sent';

  async send(push: Push): Promise<PushResult> {
    this.pushes.push(push);
    return this.answers.shift() ?? this.result;
  }
}

export const INSTALLATION = '6f1c2a9e-3b4d-4c5e-9f60-718293a4b5c6';
export const TOKEN = 'a'.repeat(64);

/** Calls the API the way the app does. */
export async function call(
  handler: (request: Request) => Promise<Response>,
  method: string,
  path: string,
  body?: unknown,
): Promise<{ status: number; json: any }> {
  const response = await handler(
    new Request(`https://alerts.traintimes.ca${path}`, {
      method,
      body: body === undefined ? undefined : JSON.stringify(body),
      headers: { 'content-type': 'application/json' },
    }),
  );
  const text = await response.text();
  return { status: response.status, json: text ? JSON.parse(text) : null };
}
