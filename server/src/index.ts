// Train Times alert server (TT-140, D38): a Cloudflare Worker with a D1 database, on the Workers Free plan (D43).
// - fetch: the app's API (src/api.ts), feedback (src/feedback.ts) and the daily timetable upload from GitHub Actions (src/upload.ts).
// - every minute: the monitoring cycle (src/monitor.ts).
// - daily: retention.

import { handleRequest } from './api.ts';
import { handleFeedback } from './feedback.ts';
import { ApnsClient } from './apns.ts';
import { applyRetention, monitor } from './monitor.ts';
import { decodeFeed, type Feed } from './realtime.ts';
import { GITHUB_JWKS_URL, handleTimetableUpload, type JWKS } from './upload.ts';

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
  /** The only workflow allowed to upload timetables, as its GitHub OIDC token names it (D43). */
  TIMETABLE_WORKFLOW: string;
}

/** The daily schedule in wrangler.toml; the other is every minute. */
const DAILY = '17 8 * * *';

let apns: ApnsClient | null = null;

/** One client per isolate, so its provider token is reused between cycles. */
function apnsClient(env: Env): ApnsClient | null {
  if (!env.APNS_KEY || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) return null;
  if (apns?.config.keyId !== env.APNS_KEY_ID) {
    apns = new ApnsClient({ key: env.APNS_KEY, keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID, topic: env.APNS_TOPIC });
  }
  return apns;
}

async function fetchTripUpdates(env: Env, trips: ReadonlySet<string>): Promise<Feed | null> {
  const url = new URL(env.TRIP_UPDATES_URL);
  // The parameter name is to be confirmed when the key arrives (Q1), as in the app.
  if (env.METROLINX_API_KEY) url.searchParams.set('key', env.METROLINX_API_KEY);
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(10_000) });
    if (!response.ok) {
      console.warn(`TripUpdates ${response.status}`);
      return null;
    }
    return decodeFeed(new Uint8Array(await response.arrayBuffer()), trips);
  } catch (error) {
    console.warn('TripUpdates fetch failed', error);
    return null;
  }
}

async function githubKeys(): Promise<JWKS> {
  const response = await fetch(GITHUB_JWKS_URL);
  if (!response.ok) throw new Error(`GitHub JWKS ${response.status}`);
  return response.json();
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const pathname = new URL(request.url).pathname;
      if (pathname === '/v1/feedback') return await handleFeedback(request, env.DB, Date.now());
      if (pathname.startsWith('/v1/timetables/')) {
        return await handleTimetableUpload(request, env.DB, Date.now(), env.TIMETABLE_WORKFLOW, githubKeys);
      }
      return await handleRequest(request, env.DB, Date.now());
    } catch (error) {
      console.error(error);
      return new Response(JSON.stringify({ error: 'server' }), { status: 500, headers: { 'content-type': 'application/json' } });
    }
  },

  async scheduled(controller: ScheduledController, env: Env): Promise<void> {
    if (controller.cron === DAILY) {
      await applyRetention(env.DB, Date.now());
      return;
    }
    const client = apnsClient(env);
    if (!client) {
      console.warn('APNS_KEY, APNS_KEY_ID or APNS_TEAM_ID is not set; no alerts are sent.');
      return;
    }
    const sent = await monitor({ db: env.DB, apns: client, feed: (trips) => fetchTripUpdates(env, trips), now: Date.now() });
    if (sent.length) console.log(`Sent ${sent.length} alerts`);
  },
} satisfies ExportedHandler<Env>;
