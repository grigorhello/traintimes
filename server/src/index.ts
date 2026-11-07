// Train Times alert server (TT-140, D37): a Cloudflare Worker with a D1 database.
// - fetch: the app's API (src/api.ts).
// - every minute: the monitoring cycle (src/monitor.ts).
// - hourly: refresh the GO rail timetable and apply retention.

import { handleRequest } from './api.ts';
import { ApnsClient } from './apns.ts';
import { applyRetention, monitor, refreshTimetables } from './monitor.ts';
import { decodeFeed, type Feed } from './realtime.ts';
import { GTFS_URL } from './timetable.ts';

export interface Env {
  DB: D1Database;
  /** The app's bundle id, the APNs topic. */
  APNS_TOPIC: string;
  /** Secrets (`wrangler secret put`): the APNs .p8 key's text, its key id and the Apple Developer team id. */
  APNS_KEY?: string;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  /** GO's GTFS-realtime TripUpdates feed. */
  TRIP_UPDATES_URL: string;
  /** Secret. Until Metrolinx issues it there is no live feed, so nothing is sent (D36). */
  METROLINX_API_KEY?: string;
}

/** The hourly schedule in wrangler.toml; the other is every minute. */
const HOURLY = '17 * * * *';

let apns: ApnsClient | null = null;

/** One client per isolate, so its provider token is reused between cycles. */
function apnsClient(env: Env): ApnsClient | null {
  if (!env.APNS_KEY || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) return null;
  if (apns?.config.keyId !== env.APNS_KEY_ID) {
    apns = new ApnsClient({ key: env.APNS_KEY, keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID, topic: env.APNS_TOPIC });
  }
  return apns;
}

async function fetchTripUpdates(env: Env): Promise<Feed | null> {
  const url = new URL(env.TRIP_UPDATES_URL);
  // The parameter name is to be confirmed when the key arrives (Q1), as in the app.
  if (env.METROLINX_API_KEY) url.searchParams.set('key', env.METROLINX_API_KEY);
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(10_000) });
    if (!response.ok) {
      console.warn(`TripUpdates ${response.status}`);
      return null;
    }
    return decodeFeed(new Uint8Array(await response.arrayBuffer()));
  } catch (error) {
    console.warn('TripUpdates fetch failed', error);
    return null;
  }
}

async function downloadGTFS(): Promise<Uint8Array> {
  const response = await fetch(GTFS_URL);
  if (!response.ok) throw new Error(`GTFS download ${response.status}`);
  return new Uint8Array(await response.arrayBuffer());
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await handleRequest(request, env.DB, Date.now());
    } catch (error) {
      console.error(error);
      return new Response(JSON.stringify({ error: 'server' }), { status: 500, headers: { 'content-type': 'application/json' } });
    }
  },

  async scheduled(controller: ScheduledController, env: Env): Promise<void> {
    if (controller.cron === HOURLY) {
      const imported = await refreshTimetables(env.DB, downloadGTFS, Date.now());
      if (imported) console.log(`Imported the timetable for ${imported} service dates`);
      await applyRetention(env.DB, Date.now());
      return;
    }
    const client = apnsClient(env);
    if (!client) {
      console.warn('APNS_KEY, APNS_KEY_ID or APNS_TEAM_ID is not set; no alerts are sent.');
      return;
    }
    const sent = await monitor({ db: env.DB, apns: client, feed: () => fetchTripUpdates(env), now: Date.now() });
    if (sent.length) console.log(`Sent ${sent.length} alerts`);
  },
} satisfies ExportedHandler<Env>;
