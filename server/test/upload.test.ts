// The daily timetable upload (D43): only the timetable workflow's GitHub OIDC token may store a timetable.

import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';
import { AUDIENCE, handleTimetableUpload, type JWKS } from '../src/upload.ts';
import { at, memoryD1 } from './support.ts';

const WORKFLOW = 'grigorhello/traintimes/.github/workflows/server-timetable.yml@refs/heads/main';
const algorithm = { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' };
const github = (await crypto.subtle.generateKey(algorithm, true, ['sign', 'verify'])) as CryptoKeyPair;
const stranger = (await crypto.subtle.generateKey(algorithm, true, ['sign', 'verify'])) as CryptoKeyPair;
const jwks = async (): Promise<JWKS> => ({ keys: [{ ...((await crypto.subtle.exportKey('jwk', github.publicKey)) as JsonWebKey), kid: 'k1' }] });

const encode = (value: string | Uint8Array) =>
  Buffer.from(typeof value === 'string' ? value : value).toString('base64url');

/** A token like the one GitHub gives the workflow, signed with `key`. */
async function token(claims: Record<string, unknown> = {}, key = github.privateKey): Promise<string> {
  const now = at('3:40') / 1000;
  const header = encode(JSON.stringify({ alg: 'RS256', typ: 'JWT', kid: 'k1' }));
  const payload = encode(
    JSON.stringify({ iss: 'https://token.actions.githubusercontent.com', aud: AUDIENCE, workflow_ref: WORKFLOW, nbf: now - 5, exp: now + 300, ...claims }),
  );
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${payload}`));
  return `${header}.${payload}.${encode(new Uint8Array(signature))}`;
}

let db: D1Database;
beforeEach(() => {
  db = memoryD1();
});

async function upload(authorization: string | null, body = JSON.stringify({ 'LW-1': { line: 'LW', stops: [], arrivals: [], departures: [] } })) {
  const headers: Record<string, string> = authorization ? { authorization } : {};
  const request = new Request('https://alerts.traintimes.ca/v1/timetables/20261109', { method: 'PUT', headers, body });
  return (await handleTimetableUpload(request, db, at('3:40'), WORKFLOW, jwks)).status;
}

const stored = async () => (await db.prepare('SELECT service_date FROM timetables').all<{ service_date: string }>()).results.length;

test("the timetable workflow's token stores the date", async () => {
  assert.equal(await upload(`Bearer ${await token()}`), 204);
  assert.equal(await stored(), 1);
});

test('anything else is turned away and stores nothing', async () => {
  assert.equal(await upload(null), 401, 'no token');
  assert.equal(await upload(`Bearer ${await token({}, stranger.privateKey)}`), 401, 'not signed by GitHub');
  assert.equal(await upload(`Bearer ${await token({ workflow_ref: 'someone/else/.github/workflows/x.yml@refs/heads/main' })}`), 401, 'another workflow');
  assert.equal(await upload(`Bearer ${await token({ workflow_ref: WORKFLOW.replace('main', 'feature') })}`), 401, 'another branch');
  assert.equal(await upload(`Bearer ${await token({ aud: 'https://example.com' })}`), 401, 'another audience');
  assert.equal(await upload(`Bearer ${await token({ exp: at('3:30') / 1000 })}`), 401, 'expired');
  assert.equal(await upload(`Bearer ${await token()}`, '{}'), 400, 'an empty timetable');
  assert.equal(await upload(`Bearer ${await token()}`, 'not json'), 400, 'not JSON');
  assert.equal(await stored(), 0);
});
