// Feedback and questions from the app (TT-202, D85). Stored in D1; read them in the Cloudflare dashboard (D1 ›
// traintimes-alerts › feedback) or with `wrangler d1 execute`. No account or installation id: the message, an optional
// reply email, and the app version, iPhone model and iOS version.
//
//   POST /v1/feedback   { kind: 'feedback' | 'question', message, email?, appVersion, device, osVersion }

const MAX_MESSAGE = 2000;
/** All messages a day, against a script flooding the table on the free plan. */
export const DAILY_CAP = 300;
const DAY = 86_400_000;

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

class Invalid extends Error {}

function field(value: unknown, name: string, max: number, optional = false): string | null {
  if (optional && (value === undefined || value === null || value === '')) return null;
  if (typeof value !== 'string' || !value.trim() || value.length > max) throw new Invalid(name);
  return value.trim();
}

export async function handleFeedback(request: Request, db: D1Database, now: number): Promise<Response> {
  if (request.method !== 'POST') return json(405, { error: 'method' });
  const input = (await request.json().catch(() => null)) as Record<string, unknown> | null;
  if (!input || typeof input !== 'object' || Array.isArray(input)) return json(400, { error: 'invalid', field: 'body' });
  let row: (string | null)[];
  try {
    const kind = input.kind;
    if (kind !== 'feedback' && kind !== 'question') throw new Invalid('kind');
    const message = field(input.message, 'message', MAX_MESSAGE);
    const email = field(input.email, 'email', 200, true);
    if (email !== null && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Invalid('email');
    row = [kind, message, email, field(input.appVersion, 'appVersion', 40), field(input.device, 'device', 40), field(input.osVersion, 'osVersion', 20)];
  } catch (error) {
    if (error instanceof Invalid) return json(400, { error: 'invalid', field: error.message });
    throw error;
  }
  const today = await db.prepare('SELECT COUNT(*) AS count FROM feedback WHERE created_at > ?').bind(now - DAY).first<{ count: number }>();
  if ((today?.count ?? 0) >= DAILY_CAP) return json(429, { error: 'busy' });
  await db
    .prepare('INSERT INTO feedback (created_at, kind, message, email, app_version, device, os_version) VALUES (?, ?, ?, ?, ?, ?, ?)')
    .bind(now, ...row)
    .run();
  return new Response(null, { status: 204 });
}
