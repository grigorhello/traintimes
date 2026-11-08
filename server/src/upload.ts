// The daily timetable upload (D43). The Workers Free plan's 10 ms of CPU per run cannot read the GTFS zip, so the
// GitHub Actions workflow `.github/workflows/server-timetable.yml` reads it (`scripts/push-timetable.ts`) and sends each
// service date here. The request carries the workflow's GitHub OIDC token, which proves it came from that workflow on
// main, so there is no shared secret to set up.
//
//   PUT /v1/timetables/:date    JSON trips by trip id, as `importTimetables` reads them

import { saveTimetable } from './monitor.ts';

/** The audience the workflow asks GitHub to put in its token. */
export const AUDIENCE = 'https://alerts.traintimes.ca';
const ISSUER = 'https://token.actions.githubusercontent.com';
export const GITHUB_JWKS_URL = `${ISSUER}/.well-known/jwks`;
/** Clock skew allowed on the token's times. */
const SKEW_MS = 60_000;

export interface JWKS {
  keys: (JsonWebKey & { kid?: string })[];
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

function base64url(value: string): Uint8Array {
  return Uint8Array.from(atob(value.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));
}

/** True when `token` is a GitHub Actions OIDC token for `workflow` ("owner/repo/.github/workflows/x.yml@refs/heads/main"). */
export async function isWorkflowToken(token: string, workflow: string, now: number, jwks: () => Promise<JWKS>): Promise<boolean> {
  const parts = token.split('.');
  if (parts.length !== 3) return false;
  let header: Record<string, unknown>;
  let claims: Record<string, unknown>;
  try {
    header = JSON.parse(new TextDecoder().decode(base64url(parts[0])));
    claims = JSON.parse(new TextDecoder().decode(base64url(parts[1])));
  } catch {
    return false;
  }
  if (header.alg !== 'RS256') return false;
  const jwk = (await jwks()).keys.find((key) => key.kid === header.kid && key.kty === 'RSA');
  if (!jwk) return false;
  const key = await crypto.subtle.importKey(
    'jwk',
    { kty: 'RSA', n: jwk.n, e: jwk.e },
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify'],
  );
  const signed = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  if (!(await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, base64url(parts[2]), signed))) return false;

  const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  return (
    claims.iss === ISSUER &&
    audiences.includes(AUDIENCE) &&
    typeof claims.exp === 'number' &&
    claims.exp * 1000 > now - SKEW_MS &&
    (typeof claims.nbf !== 'number' || claims.nbf * 1000 <= now + SKEW_MS) &&
    claims.workflow_ref === workflow
  );
}

export async function handleTimetableUpload(
  request: Request,
  db: D1Database,
  now: number,
  workflow: string,
  jwks: () => Promise<JWKS>,
): Promise<Response> {
  const path = new URL(request.url).pathname.split('/').filter(Boolean);
  if (path.length !== 3 || path[0] !== 'v1' || path[1] !== 'timetables') return json(404, { error: 'notFound' });
  if (request.method !== 'PUT') return json(405, { error: 'methodNotAllowed' });
  const date = path[2];
  if (!/^\d{8}$/.test(date)) return json(400, { error: 'invalid', field: 'date' });
  const authorization = request.headers.get('authorization') ?? '';
  const token = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
  if (!token || !(await isWorkflowToken(token, workflow, now, jwks))) return json(401, { error: 'unauthorized' });

  const text = await request.text();
  let trips: unknown = null;
  try {
    trips = JSON.parse(text);
  } catch {
    // Answered below.
  }
  if (!trips || typeof trips !== 'object' || Array.isArray(trips) || Object.keys(trips).length === 0) {
    return json(400, { error: 'invalid', field: 'body' });
  }
  await saveTimetable(db, date, text, now);
  return new Response(null, { status: 204 });
}
