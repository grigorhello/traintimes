// Registration and rules through the API, including registration failures (acceptance criterion 3).

import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';
import { handleRequest } from '../src/api.ts';
import { at, call, INSTALLATION, memoryD1, TOKEN } from './support.ts';

let db: D1Database;
const api = (request: Request) => handleRequest(request, db, at('6:30'));
const base = `/v1/installations/${INSTALLATION}`;
const rule = {
  kind: 'repeat',
  tripId: '20261109-LW-1256',
  serviceDate: '20261109',
  line: 'LW',
  scheduledDeparture: '2026-11-09T12:13:00Z',
  origin: { id: 'OA', name: 'Oakville' },
  destination: { id: 'UN', name: 'Union' },
  weekdays: [5, 1, 2, 3, 4, 1],
};

beforeEach(() => {
  db = memoryD1();
});

test('registers a device token, and registering again updates it', async () => {
  assert.equal((await call(api, 'PUT', base, { deviceToken: TOKEN, timeFormat: '12h' })).status, 204);
  assert.equal((await call(api, 'PUT', base.toUpperCase().replace('/V1/INSTALLATIONS', '/v1/installations'), { deviceToken: 'B'.repeat(64), timeFormat: '24h', environment: 'sandbox' })).status, 204);
  const row = await db.prepare('SELECT * FROM installations').first<Record<string, unknown>>();
  assert.deepEqual(row, { id: INSTALLATION, device_token: 'b'.repeat(64), environment: 'sandbox', time_format: '24h', last_seen: at('6:30') });
});

test('rejects a bad registration with the field at fault', async () => {
  assert.deepEqual(await call(api, 'PUT', '/v1/installations/not-a-uuid', { deviceToken: TOKEN, timeFormat: '12h' }), { status: 400, json: { error: 'invalid', field: 'installation' } });
  assert.deepEqual(await call(api, 'PUT', base, { deviceToken: 'xyz', timeFormat: '12h' }), { status: 400, json: { error: 'invalid', field: 'deviceToken' } });
  assert.deepEqual(await call(api, 'PUT', base, { deviceToken: TOKEN, timeFormat: 'device' }), { status: 400, json: { error: 'invalid', field: 'timeFormat' } });
  assert.deepEqual(await call(api, 'PUT', base, { deviceToken: TOKEN, timeFormat: '12h', environment: 'dev' }), { status: 400, json: { error: 'invalid', field: 'environment' } });
  assert.equal((await call(api, 'PUT', base, 'token')).status, 400);
  assert.equal((await call(api, 'POST', base, {})).status, 405);
  assert.equal((await call(api, 'GET', '/v2/anything')).status, 404);
});

test('a rule needs a registered installation', async () => {
  assert.deepEqual(await call(api, 'PUT', `${base}/rules/r1`, rule), { status: 404, json: { error: 'unknownInstallation' } });
  assert.deepEqual(await call(api, 'GET', `${base}/rules`), { status: 404, json: { error: 'unknownInstallation' } });
});

test('saves, lists, updates and deletes rules', async () => {
  await call(api, 'PUT', base, { deviceToken: TOKEN, timeFormat: '12h' });
  const saved = await call(api, 'PUT', `${base}/rules/r1`, rule);
  assert.equal(saved.status, 200);
  assert.deepEqual(saved.json, {
    id: 'r1',
    kind: 'repeat',
    tripId: '20261109-LW-1256',
    serviceDate: '20261109',
    line: 'LW',
    scheduledDeparture: '2026-11-09T12:13:00.000Z',
    origin: { id: 'OA', name: 'Oakville' },
    destination: { id: 'UN', name: 'Union' },
    weekdays: [1, 2, 3, 4, 5],
    paused: false,
    state: 'on',
    noMatchingTrainOn: null,
  });
  // Saving the same rule again updates it: no duplicate.
  await call(api, 'PUT', `${base}/rules/r1`, { ...rule, paused: true });
  const listed = await call(api, 'GET', `${base}/rules`);
  assert.equal(listed.json.rules.length, 1);
  assert.equal(listed.json.rules[0].paused, true);

  assert.equal((await call(api, 'DELETE', `${base}/rules/r1`)).status, 204);
  assert.deepEqual((await call(api, 'GET', `${base}/rules`)).json, { rules: [] });
});

test('rejects an invalid rule', async () => {
  await call(api, 'PUT', base, { deviceToken: TOKEN, timeFormat: '12h' });
  const field = async (body: object) => (await call(api, 'PUT', `${base}/rules/r1`, { ...rule, ...body })).json.field;
  assert.equal(await field({ kind: 'weekly' }), 'kind');
  assert.equal(await field({ serviceDate: '2026-11-09' }), 'serviceDate');
  assert.equal(await field({ scheduledDeparture: 'soon' }), 'scheduledDeparture');
  assert.equal(await field({ weekdays: [] }), 'weekdays');
  assert.equal(await field({ weekdays: [0] }), 'weekdays');
  assert.equal(await field({ origin: { id: 'OA' } }), 'origin.name');
  assert.equal(await field({ paused: 'yes' }), 'paused');
  assert.equal((await call(api, 'PUT', `${base}/rules/${'x'.repeat(101)}`, rule)).json.field, 'rule');
});

test('deleting the installation removes it with its rules', async () => {
  await call(api, 'PUT', base, { deviceToken: TOKEN, timeFormat: '12h' });
  await call(api, 'PUT', `${base}/rules/r1`, rule);
  assert.equal((await call(api, 'DELETE', base)).status, 204);
  assert.equal((await db.prepare('SELECT COUNT(*) AS n FROM rules').first<{ n: number }>())!.n, 0);
  assert.equal((await call(api, 'GET', `${base}/rules`)).status, 404);
});
