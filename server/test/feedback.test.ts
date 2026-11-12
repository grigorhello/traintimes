// Feedback and questions from the app (TT-202, D85).

import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';
import { DAILY_CAP, handleFeedback } from '../src/feedback.ts';
import { at, call, memoryD1 } from './support.ts';

let db: D1Database;
const api = (request: Request) => handleFeedback(request, db, at('6:30'));
const message = { kind: 'question', message: '  Does it work on the Kitchener line?  ', email: 'rider@example.com', appVersion: '1.0 (45)', device: 'iPhone18,1', osVersion: '26.1.0' };

beforeEach(() => {
  db = memoryD1();
});

test('stores a message with the app version, device and iOS version', async () => {
  assert.equal((await call(api, 'POST', '/v1/feedback', message)).status, 204);
  const row = await db.prepare('SELECT * FROM feedback').first<Record<string, unknown>>();
  assert.deepEqual(row, {
    id: 1, created_at: at('6:30'), kind: 'question', message: 'Does it work on the Kitchener line?', email: 'rider@example.com',
    app_version: '1.0 (45)', device: 'iPhone18,1', os_version: '26.1.0',
  });
});

test('the email is optional', async () => {
  const { email: _, ...noEmail } = message;
  assert.equal((await call(api, 'POST', '/v1/feedback', { ...noEmail, kind: 'feedback' })).status, 204);
  assert.equal((await db.prepare('SELECT email FROM feedback').first<{ email: null }>())?.email, null);
});

test('rejects a bad message with the field at fault', async () => {
  const bad = async (body: unknown) => (await call(api, 'POST', '/v1/feedback', body)).json?.field;
  assert.equal(await bad({ ...message, kind: 'bug' }), 'kind');
  assert.equal(await bad({ ...message, message: '   ' }), 'message');
  assert.equal(await bad({ ...message, message: 'x'.repeat(2001) }), 'message');
  assert.equal(await bad({ ...message, email: 'not an email' }), 'email');
  assert.equal(await bad({ ...message, device: undefined }), 'device');
  assert.equal(await bad('hello'), 'body');
  assert.equal((await call(api, 'GET', '/v1/feedback')).status, 405);
  assert.equal(await db.prepare('SELECT COUNT(*) AS count FROM feedback').first<{ count: number }>().then((r) => r?.count), 0);
});

test('stops taking messages after the daily cap', async () => {
  for (let i = 0; i < DAILY_CAP; i++) {
    await db.prepare("INSERT INTO feedback (created_at, kind, message, app_version, device, os_version) VALUES (?, 'feedback', 'x', '1', 'd', '26')").bind(at('6:00')).run();
  }
  assert.equal((await call(api, 'POST', '/v1/feedback', message)).status, 429);
});
