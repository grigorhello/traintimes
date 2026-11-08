# Train Times alert server

TT-140, decisions D38 and D43. A Cloudflare Worker with a D1 database, on the free Workers plan. The app registers its APNs device token and alert rules here under an anonymous installation id. Every minute the Worker checks the trips those rules watch against GO's GTFS-realtime TripUpdates feed and sends visible notifications through APNs. Once a day it applies retention. Every morning a GitHub Actions workflow reads the GO rail timetable from the public GTFS feed and uploads it to the Worker.

| File | Holds |
|---|---|
| `src/api.ts` | The app's API (the routes are listed at the top of the file) |
| `src/upload.ts` | The daily timetable upload, checked against the workflow's GitHub OIDC token |
| `src/monitor.ts` | The minute cycle, storing the timetable, and retention |
| `src/alerts.ts` | The alert rules (thresholds, updates, coalescing, window, expiry) |
| `src/copy.ts` | Notification copy, word for word from `design/handoff/Localizable.strings` |
| `src/realtime.ts` | GTFS-realtime decoder and live mapping, ported from the app (D36) |
| `src/timetable.ts` | GTFS zip import and repeating-rule resolution |
| `src/apns.ts` | APNs with a .p8 key |
| `schema.sql` | The D1 tables |
| `scripts/push-timetable.ts` | Reads the GTFS zip and uploads the timetable; run by `.github/workflows/server-timetable.yml` |

## Free plan

The Workers Free plan is enough for hundreds of riders (D43). Its limits, and how the server stays inside them:

- **10 ms of CPU per run.** Reading the GTFS zip takes about 2 s, so GitHub Actions does it and the Worker only stores the result. A minute cycle reads only the rules whose watch window is open, decodes only the watched trips in the feed and reads today's timetable (the coming week's only when the usual train is missing today): about 3 ms for 300 riders at rush hour, measured locally. Cloudflare lets a run go over now and then, for example on a cold start.
- **50 outside requests per run.** The feed takes one, so a cycle makes at most 45 APNs calls; the rest go out the next minute.
- **100,000 requests a day.** The crons make about 1,500 and the app a few per rider.
- **D1: 5 million rows read and 100,000 written a day, 5 GB.** A cycle reads the rules in their window and the day's watches, a few hundred rows.

If the app grows past this, turning on Workers Paid ($5 a month) needs no code change.

## Test

Node 22.18 or later, no Xcode needed:

```sh
cd server && npm ci && npm test && npm run typecheck
```

The replays in `test/replay.test.ts` run the server end to end on the TT-131 sample feeds and the TT-130 sample timetable, so no Metrolinx key is needed.

## Set up and deploy (once)

These steps need Grigor's accounts. Never paste a key in chat or commit it.

1. **Database.** Run `npx wrangler d1 create traintimes-alerts`, put the id it prints in `wrangler.toml` (`database_id`), then run `npx wrangler d1 execute traintimes-alerts --remote --file schema.sql`.
2. **APNs key.** In the Apple Developer account, go to Certificates, IDs & Profiles, then Keys, then +. Tick Apple Push Notifications service (APNs) and download the .p8 file (it downloads only once). Note the Key ID and your Team ID. The App ID `ca.traintimes.TrainTimes` needs the Push Notifications capability.
3. **Secrets.** Run `npx wrangler secret put APNS_KEY < AuthKey_XXXXXXXXXX.p8`, then `npx wrangler secret put APNS_KEY_ID` and `npx wrangler secret put APNS_TEAM_ID`. Or add them in the Cloudflare dashboard under Workers, then traintimes-alerts, then Settings, then Variables and Secrets.
4. **Deploy.** Run `npx wrangler deploy`. This also creates the `alerts.traintimes.ca` custom domain.
5. **Timetable.** Merge the database id from step 1 to main; until then the timetable workflow does nothing. Then run it once (GitHub, Actions, Alert server timetable, Run workflow) so the server has the timetable at once; after that it runs every morning. It needs no secret: the Worker checks the workflow's GitHub OIDC token. GitHub turns off scheduled workflows in a public repository after 60 days without a commit and emails a warning first; turn it back on in the Actions tab.
6. **When the Metrolinx key arrives**, run `npx wrangler secret put METROLINX_API_KEY`. Until then there is no live feed, so the server sends nothing.

A development build's device token works only with APNs sandbox, so the app registers with `"environment": "sandbox"` in Debug and `"production"` in TestFlight and App Store builds.
