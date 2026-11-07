import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';
import { alertNotice, reviewNotice, strings } from '../src/copy.ts';
import { addDays, formatTime, gtfsInstant, gtfsSeconds, isoWeekday, serviceDate } from '../src/time.ts';
import { at } from './support.ts';

test('the server copy matches design/handoff/Localizable.strings word for word', () => {
  const handoff = readFileSync(join(import.meta.dirname, '..', '..', 'design', 'handoff', 'Localizable.strings'), 'utf8');
  for (const [key, value] of Object.entries(strings)) {
    const line = handoff.split('\n').find((l) => l.startsWith(`"${key}" = `));
    assert.ok(line, `${key} is missing from the handoff strings`);
    assert.equal(line, `"${key}" = "${value}";`);
  }
  for (const key of handoff.match(/^"notif\.(delay|recovery|cancel|skip|rule)\.[^"]+"/gm) ?? []) {
    assert.ok(key.slice(1, -1) in strings, `${key} is not in the server copy`);
  }
});

test('notifications read as the requirements table', () => {
  const direction = { origin: 'Oakville', destination: 'Union' };
  const train = at('7:32');
  assert.deepEqual(alertNotice({ kind: 'delay', delayMin: 9, expected: at('7:41'), update: false }, train, direction, at('7:14'), '12h'), {
    title: '7:32 AM train delayed 9 min',
    body: 'Oakville to Union. Now expected 7:41 AM, as reported at 7:14 AM.',
  });
  assert.deepEqual(alertNotice({ kind: 'delay', delayMin: 15, expected: at('7:47'), update: true }, train, direction, at('7:22'), '12h'), {
    title: '7:32 AM train now delayed 15 min',
    body: 'Oakville to Union. Now expected 7:47 AM, as reported at 7:22 AM.',
  });
  assert.deepEqual(alertNotice({ kind: 'recovery', delayMin: 0, expected: at('7:32') }, train, direction, at('7:26'), '12h'), {
    title: '7:32 AM train back on time',
    body: 'Oakville to Union. Expected 7:32 AM, as reported at 7:26 AM.',
  });
  assert.deepEqual(alertNotice({ kind: 'cancelled' }, train, direction, at('7:05'), '12h'), {
    title: '7:32 AM train cancelled',
    body: 'Oakville to Union. Cancelled, as reported at 7:05 AM. Open to see the next trains.',
  });
  assert.deepEqual(alertNotice({ kind: 'skipped', stop: 'origin' }, train, direction, at('7:05'), '12h'), {
    title: '7:32 AM train will skip Oakville',
    body: 'Skips Oakville, as reported at 7:05 AM. Open to see the next trains.',
  });
  assert.deepEqual(reviewNotice(direction), {
    title: 'Your usual train has changed',
    body: 'Review your Oakville to Union weekday alert.',
  });
});

test('times follow the app formatter: Toronto, 12 or 24 hour', () => {
  assert.equal(formatTime(at('7:05'), '12h'), '7:05 AM');
  assert.equal(formatTime(at('7:05'), '24h'), '07:05');
  assert.equal(formatTime(at('0:10'), '12h'), '12:10 AM');
  assert.equal(formatTime(at('12:00'), '12h'), '12:00 PM');
  assert.equal(formatTime(at('17:10'), '24h'), '17:10');
  // Summer time: 7:05 AM EDT is 11:05 UTC.
  assert.equal(formatTime(Date.parse('2026-07-06T11:05:00Z'), '12h'), '7:05 AM');
});

test('service day changes at 3 AM Toronto time', () => {
  assert.equal(serviceDate(at('2:59')), '20261108');
  assert.equal(serviceDate(at('3:00')), '20261109');
  assert.equal(addDays('20261130', 1), '20261201');
  assert.equal(isoWeekday('20261109'), 1);
  assert.equal(isoWeekday('20261108'), 7);
});

test('GTFS times count from noon minus 12 h, so DST days keep their wall-clock times', () => {
  assert.equal(gtfsInstant('20261109', 7 * 3600 + 13 * 60), at('7:13'));
  assert.equal(gtfsInstant('20261109', 25 * 3600 + 10 * 60), at('1:10', '2026-11-10'));
  // Nov 1, 2026: clocks go back at 2 AM; 7:00 is still 7:00 EST (12:00 UTC).
  assert.equal(gtfsInstant('20261101', 7 * 3600), Date.parse('2026-11-01T12:00:00Z'));
  assert.equal(gtfsSeconds('20261109', at('7:13')), 7 * 3600 + 13 * 60);
});
