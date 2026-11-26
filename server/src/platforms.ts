// Platforms (TT-225): GO's GTFS and GTFS-realtime feeds carry none (D35, D36), but its Open Data API's
// `Stop/NextService/{stop}` lists each upcoming train at a station with its platform. The Worker relays it per station
// like the live feeds (D88): the key stays here, and each station is fetched from GO at most once per 30 s for everyone.
//
// Union's pair (TT-245, D122): at Union a train stands between two platforms, and GO's boards there say "7 & 8", but
// NextService gives one of the two numbers. GO's `ServiceUpdate/UnionDepartures/All` carries the pair, so Union's board
// takes its platform from there where it posts one. Every platform is written the one way, numbers joined by "/": "7/8".

import { RELAY_SECONDS } from './relay.ts';

const FRESH_MS = RELAY_SECONDS * 1000;

/** A GO station code: "UN", "CL". Anything else is refused before GO is called. */
const STOP_CODE = /^[A-Z0-9]{2,5}$/;

/** One train at the station as the app reads it. */
export interface PlatformTrip {
  /** GO's trip number, the last part of the GTFS trip id ("20261118-LW-1713" is "1713"). */
  trip: string;
  line?: string;
  /** Local time as GO writes it: "2026-11-18 14:17:00". */
  departure?: string;
  /** The track GO posted, else the one it plans, a pair as "7/8" (`platformName`); null when it shows neither. */
  platform: string | null;
}

export interface PlatformBoard {
  /** Seconds since 1970. */
  fetchedAt: number;
  trips: PlatformTrip[];
}

/**
 * The platform the board posts for a GTFS trip id, by GO's trip number, its last part (the app's
 * `Board.platform(forTrip:)`); null while it posts none. The minute cycle reads it for a train standing at the station
 * (TT-233).
 */
export function platformFor(board: PlatformBoard, tripId: string): string | null {
  const number = tripId.split('-').pop();
  let platform: string | null = null;
  for (const trip of board.trips) {
    if (trip.trip === number && trip.platform) platform = trip.platform;
  }
  return platform;
}

type Json = Record<string, unknown>;

const text = (value: unknown): string | undefined => {
  if (typeof value === 'number') return String(value);
  if (typeof value !== 'string') return undefined;
  const trimmed = value.trim();
  return trimmed && trimmed !== '-' ? trimmed : undefined;
};

/**
 * A platform as the app shows it (TT-245, D122): the numbers GO writes, joined by "/" whatever GO joins them with ("7 &
 * 8", "7, 8", "7/8" and "7 and 8" are "7/8"); undefined for no platform ("-", blank).
 */
export function platformName(value: unknown): string | undefined {
  const raw = text(value);
  if (!raw) return undefined;
  const parts = raw.split(/\s*(?:&|,|\/|;|\band\b)\s*/i).map((part) => part.trim()).filter((part) => part && part !== '-');
  return parts.length ? parts.join('/') : undefined;
}

/**
 * GO's answer as the trains the app needs. `Lines` is a list, a single object when there is one train, or null outside
 * service hours. A posted (actual) platform wins over the planned (scheduled) one.
 */
export function parseNextService(body: unknown): PlatformTrip[] {
  const service = (body as Json | null)?.NextService as Json | null | undefined;
  const raw = service?.Lines;
  const lines = Array.isArray(raw) ? raw : raw && typeof raw === 'object' ? [raw] : [];
  const trips: PlatformTrip[] = [];
  for (const line of lines as Json[]) {
    const trip = text(line?.TripNumber);
    if (!trip || text(line.ServiceType)?.toUpperCase() === 'B') continue;
    trips.push({
      trip,
      line: text(line.LineCode),
      departure: text(line.ScheduledDepartureTime),
      platform: platformName(line.ActualPlatform) ?? platformName(line.ScheduledPlatform) ?? null,
    });
  }
  return trips;
}

/**
 * Union's departures list (`ServiceUpdate/UnionDepartures/All`, TT-245): `AllDepartures.Trip`, a list or a single
 * object, each train with its `TripNumber` and the `Platform` GO shows at Union ("7 & 8", "-" while none is posted).
 * Only the trains with a platform posted, written as `platformName` writes it; buses are left out.
 */
export function parseUnionDepartures(body: unknown): { trip: string; departure?: string; platform: string }[] {
  const departures = (body as Json | null)?.AllDepartures as Json | null | undefined;
  const raw = departures?.Trip;
  const list = Array.isArray(raw) ? raw : raw && typeof raw === 'object' ? [raw] : [];
  const trips: { trip: string; departure?: string; platform: string }[] = [];
  for (const entry of list as Json[]) {
    const trip = text(entry?.TripNumber);
    const platform = platformName(entry?.Platform);
    if (!trip || !platform || text(entry.ServiceType)?.toUpperCase() === 'B') continue;
    trips.push({ trip, departure: text(entry.Time), platform });
  }
  return trips;
}

/** Union's board: NextService's trains, each with the pair the Union list posts for it where it posts one (TT-245). */
export function withUnionPlatforms(trips: PlatformTrip[], union: ReturnType<typeof parseUnionDepartures>): PlatformTrip[] {
  const merged = trips.map((trip) => ({ ...trip }));
  for (const posted of union) {
    const listed = merged.filter((trip) => trip.trip === posted.trip);
    if (listed.length === 0) merged.push({ trip: posted.trip, departure: posted.departure, platform: posted.platform });
    for (const trip of listed) trip.platform = posted.platform;
  }
  return merged;
}

/** One call to GO's Open Data API at `path` (next to the feeds); null without the key, when GO fails, or when the answer is not JSON. */
export async function downloadOpenData(fetcher: typeof fetch, feedsBase: string, key: string | undefined, path: string): Promise<unknown | null> {
  if (!key) return null;
  // GO_FEEDS_URL is ".../api/V1/Gtfs/Feed/"; NextService sits at ".../api/V1/Stop/NextService/UN".
  const url = new URL(`../../${path}`, feedsBase);
  url.searchParams.set('key', key);
  try {
    const response = await fetcher(url, { headers: { accept: 'application/json' }, signal: AbortSignal.timeout(10_000) });
    if (!response.ok) {
      console.warn(`${path} ${response.status}`);
      return null;
    }
    return await response.json();
  } catch (error) {
    console.warn(`${path} fetch failed`, error);
    return null;
  }
}

/** One call to GO for a station's NextService. */
export function downloadNextService(fetcher: typeof fetch, feedsBase: string, key: string | undefined, stop: string): Promise<unknown | null> {
  return downloadOpenData(fetcher, feedsBase, key, `Stop/NextService/${stop}`);
}

/** One call to GO for Union's departures list (TT-245). */
export function downloadUnionDepartures(fetcher: typeof fetch, feedsBase: string, key: string | undefined): Promise<unknown | null> {
  return downloadOpenData(fetcher, feedsBase, key, 'ServiceUpdate/UnionDepartures/All');
}

/** Union's station code: its board also reads the Union list (TT-245). */
export const UNION = 'UN';

export interface PlatformRelayDependencies {
  download: (stop: string) => Promise<unknown | null>;
  /** GO's Union departures list, read with Union's NextService for its pairs (TT-245); left out, Union has NextService's. */
  union?: () => Promise<unknown | null>;
  cache?: Pick<Cache, 'match' | 'put'> | null;
  now: () => number;
}

const CACHE_ORIGIN = 'https://alerts.traintimes.ca/__relay/platforms/';

/** The station's trains, from GO only when no copy or failure is under 30 s old; null while GO is failing. */
export class PlatformRelay {
  private readonly deps: PlatformRelayDependencies;
  private readonly memory = new Map<string, PlatformBoard>();
  private readonly failedAt = new Map<string, number>();
  private readonly loading = new Map<string, Promise<PlatformBoard | null>>();

  constructor(deps: PlatformRelayDependencies) {
    this.deps = deps;
  }

  async get(stop: string): Promise<PlatformBoard | null> {
    const now = this.deps.now();
    const held = this.memory.get(stop);
    if (held && now - held.fetchedAt * 1000 < FRESH_MS) return held;
    const failed = this.failedAt.get(stop);
    if (failed !== undefined && now - failed < FRESH_MS) return null;
    let pending = this.loading.get(stop);
    if (!pending) {
      pending = this.load(stop, now).finally(() => this.loading.delete(stop));
      this.loading.set(stop, pending);
    }
    return pending;
  }

  private async load(stop: string, now: number): Promise<PlatformBoard | null> {
    const key = CACHE_ORIGIN + stop;
    const cached = await this.deps.cache?.match(key).catch(() => undefined);
    if (cached) {
      const at = Number(cached.headers.get('x-fetched-at'));
      if (now - at < FRESH_MS) {
        if (cached.headers.get('x-failed')) {
          this.failedAt.set(stop, at);
          return null;
        }
        const board = (await cached.json()) as PlatformBoard;
        this.memory.set(stop, board);
        return board;
      }
    }
    // Union reads its departures list beside NextService, for the pairs (TT-245): one more call to GO per 30 s.
    const readsUnion = stop === UNION && this.deps.union !== undefined;
    const [body, unionBody] = await Promise.all([this.deps.download(stop), readsUnion ? this.deps.union!() : null]);
    const fetchedAt = this.deps.now();
    const headers: Record<string, string> = { 'cache-control': `max-age=${RELAY_SECONDS}`, 'x-fetched-at': String(fetchedAt) };
    if (body === null && unionBody === null) {
      this.failedAt.set(stop, fetchedAt);
      await this.deps.cache?.put(key, new Response(null, { headers: { ...headers, 'x-failed': '1' } })).catch(() => {});
      return null;
    }
    const listed = parseNextService(body);
    const union = readsUnion ? parseUnionDepartures(unionBody) : [];
    const trips = readsUnion ? withUnionPlatforms(listed, union) : listed;
    const posted = trips.filter((t) => t.platform).length;
    console.log(`NextService ${stop}: ${trips.length} trains, ${posted} with a platform${readsUnion ? `, ${union.length} from the Union list` : ''}`);
    // When nothing reads as a platform, a slice of GO's answer shows whether its shape changed; the same for the Union
    // list when NextService posts platforms and the list gives none.
    if (!posted) console.log(`NextService ${stop} sample ${JSON.stringify(body).slice(0, 800)}`);
    if (readsUnion && union.length === 0 && listed.some((t) => t.platform)) {
      console.log(`UnionDepartures sample ${JSON.stringify(unionBody).slice(0, 800)}`);
    }
    const board: PlatformBoard = { fetchedAt: Math.floor(fetchedAt / 1000), trips };
    this.memory.set(stop, board);
    this.failedAt.delete(stop);
    await this.deps.cache?.put(key, new Response(JSON.stringify(board), { headers })).catch(() => {});
    return board;
  }
}

/** `GET /v1/live/platforms?stop=UN`: the station's upcoming trains with their platforms. Null for any other path. */
export async function handlePlatforms(request: Request, relay: PlatformRelay): Promise<Response | null> {
  const url = new URL(request.url);
  if (url.pathname !== '/v1/live/platforms') return null;
  if (request.method !== 'GET') return new Response(null, { status: 405, headers: { allow: 'GET' } });
  const stop = url.searchParams.get('stop')?.toUpperCase() ?? '';
  const json = { 'content-type': 'application/json' };
  if (!STOP_CODE.test(stop)) return new Response(JSON.stringify({ error: 'stop' }), { status: 400, headers: json });
  const board = await relay.get(stop);
  if (!board) return new Response(JSON.stringify({ error: 'unavailable' }), { status: 503, headers: json });
  return new Response(JSON.stringify(board), { headers: { ...json, 'cache-control': `max-age=${RELAY_SECONDS / 2}` } });
}
