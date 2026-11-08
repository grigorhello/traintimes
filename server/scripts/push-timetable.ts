// The daily timetable upload (D43), run by `.github/workflows/server-timetable.yml`: reads the GO rail timetable for
// today and the next 7 service days from the public GTFS zip, then sends each date to the alert server with the
// workflow's GitHub OIDC token (`src/upload.ts`). The Workers Free plan's 10 ms of CPU cannot read the zip itself.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { GTFS_URL, importTimetables } from '../src/timetable.ts';
import { addDays, serviceDate } from '../src/time.ts';
import { AUDIENCE } from '../src/upload.ts';

// Until the server is set up (README step 2 writes the D1 database id), there is no server to send to.
const config = readFileSync(join(import.meta.dirname, '..', 'wrangler.toml'), 'utf8');
if (config.includes('database_id = "00000000-0000-0000-0000-000000000000"')) {
  console.log('The alert server is not set up yet (server/README.md), so there is nothing to upload to.');
  process.exit(0);
}

const zip = await fetch(GTFS_URL);
if (!zip.ok) throw new Error(`GTFS download ${zip.status}`);
const today = serviceDate(Date.now());
const dates = Array.from({ length: 8 }, (_, days) => addDays(today, days));
const timetables = await importTimetables(new Uint8Array(await zip.arrayBuffer()), dates);

// Asked for after the import: the token lasts about 5 minutes.
const { ACTIONS_ID_TOKEN_REQUEST_URL: tokenURL, ACTIONS_ID_TOKEN_REQUEST_TOKEN: tokenRequest } = process.env;
if (!tokenURL || !tokenRequest) throw new Error('Run in GitHub Actions with the id-token: write permission.');
const oidc = await fetch(`${tokenURL}&audience=${encodeURIComponent(AUDIENCE)}`, { headers: { authorization: `Bearer ${tokenRequest}` } });
if (!oidc.ok) throw new Error(`GitHub OIDC token ${oidc.status}`);
const { value: token } = (await oidc.json()) as { value: string };

for (const [date, trips] of timetables) {
  const count = Object.keys(trips).length;
  // A date the feed does not cover stays missing on the server rather than empty (D38).
  if (count === 0) {
    console.log(`${date}: not in the feed`);
    continue;
  }
  const response = await fetch(`${AUDIENCE}/v1/timetables/${date}`, {
    method: 'PUT',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify(trips),
  });
  if (!response.ok) throw new Error(`${date}: ${response.status} ${await response.text()}`);
  console.log(`${date}: ${count} trips`);
}
