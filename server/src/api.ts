// The app's API: register the device token, then save, list and delete alert rules. Keyed by an anonymous
// installation id; no account (D5, rule 9).
//
//   PUT    /v1/installations/:installation                 { deviceToken, timeFormat, environment }
//   DELETE /v1/installations/:installation
//   GET    /v1/installations/:installation/rules
//   PUT    /v1/installations/:installation/rules/:rule     { kind, tripId, serviceDate, line, scheduledDeparture,
//                                                           origin: { id, name }, destination: { id, name },
//                                                           weekdays?, paused? }
//   DELETE /v1/installations/:installation/rules/:rule

import { gtfsInstant, gtfsSeconds } from './time.ts';

export class BadRequest extends Error {}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

const noContent = () => new Response(null, { status: 204 });

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const RULE_ID = /^[A-Za-z0-9._:-]{1,100}$/;
const TOKEN = /^[0-9a-f]{64,200}$/i;
const DATE = /^\d{8}$/;

function text(value: unknown, field: string, max = 100): string {
  if (typeof value !== 'string' || !value.trim() || value.length > max) throw new BadRequest(field);
  return value;
}

function oneOf<T extends string>(value: unknown, options: readonly T[], field: string): T {
  if (!options.includes(value as T)) throw new BadRequest(field);
  return value as T;
}

function station(value: unknown, field: string): { id: string; name: string } {
  const object = (value ?? {}) as Record<string, unknown>;
  return { id: text(object.id, `${field}.id`), name: text(object.name, `${field}.name`) };
}

async function body(request: Request): Promise<Record<string, unknown>> {
  const value = await request.json().catch(() => null);
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new BadRequest('body');
  return value as Record<string, unknown>;
}

interface RuleRow {
  id: string;
  kind: string;
  trip_id: string;
  service_date: string;
  line: string;
  departure: number;
  origin_id: string;
  origin_name: string;
  destination_id: string;
  destination_name: string;
  weekdays: string;
  paused: number;
  state: string;
  no_train_date: string | null;
}

/** A rule as the app reads it, with its server state: On, or Review needed; and "No matching train today". */
function ruleJSON(row: RuleRow) {
  return {
    id: row.id,
    kind: row.kind,
    tripId: row.trip_id,
    serviceDate: row.service_date,
    line: row.line,
    scheduledDeparture: new Date(gtfsInstant(row.service_date, row.departure)).toISOString(),
    origin: { id: row.origin_id, name: row.origin_name },
    destination: { id: row.destination_id, name: row.destination_name },
    weekdays: row.weekdays ? row.weekdays.split(',').map(Number) : [],
    paused: row.paused === 1,
    state: row.state === 'review' ? 'reviewNeeded' : 'on',
    noMatchingTrainOn: row.no_train_date,
  };
}

async function touch(db: D1Database, installation: string, now: number): Promise<boolean> {
  const result = await db.prepare('UPDATE installations SET last_seen = ? WHERE id = ?').bind(now, installation).run();
  return result.meta.changes > 0;
}

/** Deletes an installation and everything keyed to it. */
export function deleteInstallation(db: D1Database, installation: string) {
  return db.batch([
    db.prepare('DELETE FROM rules WHERE installation_id = ?').bind(installation),
    db.prepare('DELETE FROM watches WHERE installation_id = ?').bind(installation),
    db.prepare('DELETE FROM installations WHERE id = ?').bind(installation),
  ]);
}

export async function handleRequest(request: Request, db: D1Database, now: number): Promise<Response> {
  const path = new URL(request.url).pathname.split('/').filter(Boolean);
  if (path[0] !== 'v1' || path[1] !== 'installations' || !path[2] || path.length > 5 || (path.length >= 4 && path[3] !== 'rules')) {
    return json(404, { error: 'notFound' });
  }
  if (!UUID.test(path[2])) return json(400, { error: 'invalid', field: 'installation' });
  const installation = path[2].toLowerCase();
  const method = request.method;

  try {
    if (path.length === 3 && method === 'PUT') {
      const input = await body(request);
      const token = text(input.deviceToken, 'deviceToken', 200);
      if (!TOKEN.test(token)) throw new BadRequest('deviceToken');
      const timeFormat = oneOf(input.timeFormat, ['12h', '24h'] as const, 'timeFormat');
      const environment = oneOf(input.environment ?? 'production', ['production', 'sandbox'] as const, 'environment');
      await db
        .prepare(
          `INSERT INTO installations (id, device_token, environment, time_format, last_seen) VALUES (?, ?, ?, ?, ?)
           ON CONFLICT (id) DO UPDATE SET device_token = excluded.device_token, environment = excluded.environment,
             time_format = excluded.time_format, last_seen = excluded.last_seen`,
        )
        .bind(installation, token.toLowerCase(), environment, timeFormat, now)
        .run();
      return noContent();
    }
    if (path.length === 3 && method === 'DELETE') {
      await deleteInstallation(db, installation);
      return noContent();
    }
    if (path.length === 4 && method === 'GET') {
      if (!(await touch(db, installation, now))) return json(404, { error: 'unknownInstallation' });
      const rows = await db
        .prepare('SELECT * FROM rules WHERE installation_id = ? ORDER BY updated_at DESC')
        .bind(installation)
        .all<RuleRow>();
      return json(200, { rules: rows.results.map(ruleJSON) });
    }
    if (path.length === 5) {
      const rule = path[4];
      if (!RULE_ID.test(rule)) return json(400, { error: 'invalid', field: 'rule' });
      if (method === 'DELETE') {
        await db.prepare('DELETE FROM rules WHERE installation_id = ? AND id = ?').bind(installation, rule).run();
        await touch(db, installation, now);
        return noContent();
      }
      if (method === 'PUT') {
        const input = await body(request);
        const kind = oneOf(input.kind, ['trip', 'repeat'] as const, 'kind');
        const tripId = text(input.tripId, 'tripId');
        const serviceDate = text(input.serviceDate, 'serviceDate');
        if (!DATE.test(serviceDate)) throw new BadRequest('serviceDate');
        const line = text(input.line, 'line', 20);
        const departureAt = Date.parse(text(input.scheduledDeparture, 'scheduledDeparture', 40));
        if (Number.isNaN(departureAt)) throw new BadRequest('scheduledDeparture');
        const origin = station(input.origin, 'origin');
        const destination = station(input.destination, 'destination');
        let weekdays: number[] = [];
        if (kind === 'repeat') {
          const days = input.weekdays;
          if (!Array.isArray(days) || days.length === 0 || days.some((d) => !Number.isInteger(d) || d < 1 || d > 7)) {
            throw new BadRequest('weekdays');
          }
          weekdays = [...new Set(days as number[])].sort();
        }
        const paused = input.paused === undefined ? false : input.paused;
        if (typeof paused !== 'boolean') throw new BadRequest('paused');
        if (!(await touch(db, installation, now))) return json(404, { error: 'unknownInstallation' });

        // Saving again updates the same rule (no duplicates) and clears Review needed.
        await db
          .prepare(
            `INSERT INTO rules (installation_id, id, kind, trip_id, service_date, line, departure, origin_id, origin_name,
               destination_id, destination_name, weekdays, paused, state, no_train_date, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'on', NULL, ?)
             ON CONFLICT (installation_id, id) DO UPDATE SET kind = excluded.kind, trip_id = excluded.trip_id,
               service_date = excluded.service_date, line = excluded.line, departure = excluded.departure,
               origin_id = excluded.origin_id, origin_name = excluded.origin_name,
               destination_id = excluded.destination_id, destination_name = excluded.destination_name,
               weekdays = excluded.weekdays, paused = excluded.paused, state = 'on', no_train_date = NULL,
               updated_at = excluded.updated_at`,
          )
          .bind(
            installation,
            rule,
            kind,
            tripId,
            serviceDate,
            line,
            gtfsSeconds(serviceDate, departureAt),
            origin.id,
            origin.name,
            destination.id,
            destination.name,
            weekdays.join(','),
            paused ? 1 : 0,
            now,
          )
          .run();
        const row = await db
          .prepare('SELECT * FROM rules WHERE installation_id = ? AND id = ?')
          .bind(installation, rule)
          .first<RuleRow>();
        return json(200, ruleJSON(row!));
      }
    }
    return json(405, { error: 'methodNotAllowed' });
  } catch (error) {
    if (error instanceof BadRequest) return json(400, { error: 'invalid', field: error.message });
    throw error;
  }
}
