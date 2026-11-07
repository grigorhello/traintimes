import assert from 'node:assert/strict';
import { test } from 'node:test';
import { ApnsClient, type Push } from '../src/apns.ts';
import { at } from './support.ts';

const keys = (await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify'])) as CryptoKeyPair;
const pkcs8 = new Uint8Array((await crypto.subtle.exportKey('pkcs8', keys.privateKey)) as ArrayBuffer);
const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8))}\n-----END PRIVATE KEY-----\n`;
const config = { key: pem, keyId: 'ABC123DEFG', teamId: 'TEAM123456', topic: 'ca.traintimes.TrainTimes' };

const push: Push = {
  token: 'a'.repeat(64),
  environment: 'sandbox',
  title: '7:32 AM train delayed 9 min',
  body: 'Oakville to Union. Now expected 7:41 AM, as reported at 7:14 AM.',
  expiration: at('9:32'),
  data: { tripId: '20261109-LW-1256', serviceDate: '20261109' },
};

function decode(part: string): unknown {
  return JSON.parse(atob(part.replace(/-/g, '+').replace(/_/g, '/')));
}

test('signs an ES256 provider token APNs can verify, and reuses it', async () => {
  const client = new ApnsClient(config);
  const token = await client.providerToken(at('7:00'));
  const [header, claims, signature] = token.split('.');
  assert.deepEqual(decode(header), { alg: 'ES256', kid: 'ABC123DEFG' });
  assert.deepEqual(decode(claims), { iss: 'TEAM123456', iat: at('7:00') / 1000 });
  const raw = Uint8Array.from(atob(signature.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));
  assert.equal(raw.length, 64);
  const valid = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, keys.publicKey, raw, new TextEncoder().encode(`${header}.${claims}`));
  assert.ok(valid);
  assert.equal(await client.providerToken(at('7:49')), token);
  assert.notEqual(await client.providerToken(at('7:51')), token);
});

test('sends a visible alert with the expiry and deep-link keys', async () => {
  const requests: { url: string; init: RequestInit }[] = [];
  const client = new ApnsClient(config, async (url, init) => {
    requests.push({ url: String(url), init: init! });
    return new Response(null, { status: 200 });
  });
  assert.equal(await client.send(push, at('7:15')), 'sent');
  const { url, init } = requests[0];
  assert.equal(url, `https://api.sandbox.push.apple.com/3/device/${'a'.repeat(64)}`);
  const headers = init.headers as Record<string, string>;
  assert.equal(headers['apns-topic'], 'ca.traintimes.TrainTimes');
  assert.equal(headers['apns-push-type'], 'alert');
  assert.equal(headers['apns-expiration'], String(at('9:32') / 1000));
  assert.match(headers.authorization, /^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
  assert.deepEqual(JSON.parse(init.body as string), {
    aps: { alert: { title: push.title, body: push.body }, sound: 'default' },
    tripId: '20261109-LW-1256',
    serviceDate: '20261109',
  });
});

test('reads APNs failures: expired token, bad token, provider token, throttling, network', async () => {
  const answer = (status: number, reason?: string) =>
    new ApnsClient(config, async () => new Response(reason ? JSON.stringify({ reason }) : null, { status })).send(push, at('7:15'));
  assert.equal(await answer(410, 'Unregistered'), 'unregistered');
  assert.equal(await answer(400, 'BadDeviceToken'), 'badToken');
  assert.equal(await answer(400, 'DeviceTokenNotForTopic'), 'badToken');
  assert.equal(await answer(403, 'ExpiredProviderToken'), 'retry');
  assert.equal(await answer(429, 'TooManyRequests'), 'retry');
  assert.equal(await answer(503), 'retry');
  assert.equal(await answer(400, 'PayloadTooLarge'), 'failed');
  const offline = new ApnsClient(config, async () => {
    throw new TypeError('network');
  });
  assert.equal(await offline.send(push, at('7:15')), 'retry');
});
