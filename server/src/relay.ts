// GO's live feeds relayed to the app (TT-179, D88): the Metrolinx key stays in this Worker's secret and never ships in
// the app. Each feed is fetched from GO at most once per 30 s for everyone, whatever the number of phones: a copy in
// this isolate's memory, then in the data centre's cache (Cache API), then GO. A failed fetch is remembered for 30 s
// too, so a GO outage costs one call per 30 s (Metrolinx may suspend a key for many failed calls or 429s).

import { decodeVehicles, type TrainPosition } from './realtime.ts';

export type FeedName = 'TripUpdates' | 'Alerts' | 'VehiclePosition';

/** A copy younger than this is served without asking GO. */
export const RELAY_SECONDS = 30;
const FRESH_MS = RELAY_SECONDS * 1000;

export interface Snapshot {
  bytes: Uint8Array;
  /** Epoch milliseconds. */
  fetchedAt: number;
}

export interface RelayDependencies {
  /** One call to GO; null when it failed or there is no key. */
  download: (feed: FeedName) => Promise<Uint8Array | null>;
  /** The data centre's cache (`caches.default`); none in tests unless faked. */
  cache?: Pick<Cache, 'match' | 'put'> | null;
  now: () => number;
}

/**
 * One call to GO for a feed; null without the key (an unkeyed call is a failed call), when GO fails, or when the answer
 * is not GTFS-realtime protobuf. GO answers JSON unless asked for protobuf (checked against the real feeds on
 * 2026-11-14), so the request says `Accept: application/x-protobuf`, and a FeedMessage starts with its header, byte 0x0a.
 */
export async function downloadFeed(
  fetcher: typeof fetch,
  base: string,
  key: string | undefined,
  feed: FeedName,
): Promise<Uint8Array | null> {
  if (!key) return null;
  const url = new URL(feed, base);
  url.searchParams.set('key', key);
  try {
    const response = await fetcher(url, { headers: { accept: 'application/x-protobuf' }, signal: AbortSignal.timeout(10_000) });
    if (!response.ok) {
      console.warn(`${feed} ${response.status}`);
      return null;
    }
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes[0] !== 0x0a) {
      console.warn(`${feed} is not protobuf (${response.headers.get('content-type')})`);
      return null;
    }
    return bytes;
  } catch (error) {
    console.warn(`${feed} fetch failed`, error);
    return null;
  }
}

/** The cache key's origin: the Cache API keys on URLs of the Worker's own zone. */
const CACHE_ORIGIN = 'https://alerts.traintimes.ca/__relay/';

export class FeedRelay {
  private readonly deps: RelayDependencies;
  private readonly memory = new Map<FeedName, Snapshot>();
  private readonly failedAt = new Map<FeedName, number>();
  private readonly loading = new Map<FeedName, Promise<Snapshot | null>>();

  constructor(deps: RelayDependencies) {
    this.deps = deps;
  }

  /** The feed, from GO only when no copy or failure is under 30 s old; null while GO is failing. */
  async get(feed: FeedName): Promise<Snapshot | null> {
    const now = this.deps.now();
    const held = this.memory.get(feed);
    if (held && now - held.fetchedAt < FRESH_MS) return held;
    const failed = this.failedAt.get(feed);
    if (failed !== undefined && now - failed < FRESH_MS) return null;
    let pending = this.loading.get(feed);
    if (!pending) {
      pending = this.load(feed, now).finally(() => this.loading.delete(feed));
      this.loading.set(feed, pending);
    }
    return pending;
  }

  private async load(feed: FeedName, now: number): Promise<Snapshot | null> {
    const key = CACHE_ORIGIN + feed;
    const cached = await this.deps.cache?.match(key).catch(() => undefined);
    if (cached) {
      const at = Number(cached.headers.get('x-fetched-at'));
      if (now - at < FRESH_MS) {
        if (cached.headers.get('x-failed')) {
          this.failedAt.set(feed, at);
          return null;
        }
        const snapshot = { bytes: new Uint8Array(await cached.arrayBuffer()), fetchedAt: at };
        this.memory.set(feed, snapshot);
        return snapshot;
      }
    }
    const bytes = await this.deps.download(feed);
    const fetchedAt = this.deps.now();
    const headers: Record<string, string> = { 'cache-control': `max-age=${RELAY_SECONDS}`, 'x-fetched-at': String(fetchedAt) };
    if (!bytes) {
      this.failedAt.set(feed, fetchedAt);
      await this.deps.cache?.put(key, new Response(null, { headers: { ...headers, 'x-failed': '1' } })).catch(() => {});
      return null;
    }
    const snapshot = { bytes, fetchedAt };
    this.memory.set(feed, snapshot);
    this.failedAt.delete(feed);
    await this.deps.cache?.put(key, new Response(bytes, { headers })).catch(() => {});
    return snapshot;
  }
}

/** A train as the app reads it: times in seconds since 1970. */
interface TrainJSON {
  tripId: string;
  startDate?: string;
  latitude: number;
  longitude: number;
  stopped: boolean;
  timestamp?: number;
}

const decoded = new WeakMap<Snapshot, { timestamp?: number; trains: TrainPosition[] }>();

/** The line a train runs on: its route id's suffix ("09261126-LW"), else its trip id's middle part ("20261109-LW-1713"). */
function lineOf(train: TrainPosition): string | undefined {
  return train.routeId?.split('-').pop() ?? train.tripId.split('-')[1];
}

const seconds = (ms: number | undefined) => (ms === undefined ? undefined : Math.floor(ms / 1000));

/**
 * `GET /v1/live/trip-updates` and `GET /v1/live/alerts`: GO's GTFS-realtime protobuf as GO sent it.
 * `GET /v1/trains[?line=LW]`: the trains of the VehiclePosition feed as JSON.
 * Null when the path is not one of these.
 */
export async function handleLive(request: Request, relay: FeedRelay): Promise<Response | null> {
  const url = new URL(request.url);
  const feed: FeedName | undefined = (
    { '/v1/live/trip-updates': 'TripUpdates', '/v1/live/alerts': 'Alerts', '/v1/trains': 'VehiclePosition' } as const
  )[url.pathname as '/v1/trains'];
  if (!feed) return null;
  if (request.method !== 'GET') return new Response(null, { status: 405, headers: { allow: 'GET' } });
  const snapshot = await relay.get(feed);
  if (!snapshot) {
    return new Response(JSON.stringify({ error: 'unavailable' }), { status: 503, headers: { 'content-type': 'application/json' } });
  }
  const cacheControl = `max-age=${RELAY_SECONDS / 2}`;
  if (feed !== 'VehiclePosition') {
    return new Response(snapshot.bytes, { headers: { 'content-type': 'application/x-protobuf', 'cache-control': cacheControl } });
  }
  let vehicles = decoded.get(snapshot);
  if (!vehicles) {
    vehicles = decodeVehicles(snapshot.bytes);
    decoded.set(snapshot, vehicles);
  }
  const line = url.searchParams.get('line');
  const trains: TrainJSON[] = vehicles.trains
    .filter((train) => !line || lineOf(train) === line)
    .map((t) => ({ tripId: t.tripId, startDate: t.startDate, latitude: t.latitude, longitude: t.longitude, stopped: t.stopped, timestamp: seconds(t.timestamp) }));
  return new Response(JSON.stringify({ timestamp: seconds(vehicles.timestamp), trains }), {
    headers: { 'content-type': 'application/json', 'cache-control': cacheControl },
  });
}
