# Train Times alert server

TT-140, decision D37. A Cloudflare Worker with a D1 database. The app registers its APNs device token and alert rules here under an anonymous installation id. Every minute the Worker checks the trips those rules watch against GO's GTFS-realtime TripUpdates feed and sends visible notifications through APNs. Every hour it refreshes the GO rail timetable from the public GTFS feed and applies retention.

| File | Holds |
|---|---|
| `src/api.ts` | The app's API (the routes are listed at the top of the file) |
| `src/monitor.ts` | The minute cycle, timetable refresh and retention |
| `src/alerts.ts` | The alert rules (thresholds, updates, coalescing, window, expiry) |
| `src/copy.ts` | Notification copy, word for word from `design/handoff/Localizable.strings` |
| `src/realtime.ts` | GTFS-realtime decoder and live mapping, ported from the app (D36) |
| `src/timetable.ts` | GTFS zip import and repeating-rule resolution |
| `src/apns.ts` | APNs with a .p8 key |
| `schema.sql` | The D1 tables |

## Test

Node 22.18 or later, no Xcode needed:

```sh
cd server && npm ci && npm test && npm run typecheck
```

The replays in `test/replay.test.ts` run the server end to end on the TT-131 sample feeds and the TT-130 sample timetable, so no Metrolinx key is needed.

## Set up and deploy (once)

These steps need Grigor's accounts. Never paste a key in chat or commit it.

1. **Cloudflare plan.** Turn on Workers Paid ($5 a month) on the account that holds traintimes.ca. The Free plan allows 10 ms of CPU per run, which is too little to decode the feed or read the GTFS zip.
2. **Database.** Run `npx wrangler d1 create traintimes-alerts`, put the id it prints in `wrangler.toml` (`database_id`), then run `npx wrangler d1 execute traintimes-alerts --remote --file schema.sql`.
3. **APNs key.** In the Apple Developer account, go to Certificates, IDs & Profiles, then Keys, then +. Tick Apple Push Notifications service (APNs) and download the .p8 file (it downloads only once). Note the Key ID and your Team ID. The App ID `ca.traintimes.TrainTimes` needs the Push Notifications capability.
4. **Secrets.** Run `npx wrangler secret put APNS_KEY < AuthKey_XXXXXXXXXX.p8`, then `npx wrangler secret put APNS_KEY_ID` and `npx wrangler secret put APNS_TEAM_ID`. Or add them in the Cloudflare dashboard under Workers, then traintimes-alerts, then Settings, then Variables and Secrets.
5. **Deploy.** Run `npx wrangler deploy`. This also creates the `alerts.traintimes.ca` custom domain.
6. **When the Metrolinx key arrives**, run `npx wrangler secret put METROLINX_API_KEY`. Until then there is no live feed, so the server sends nothing.

A development build's device token works only with APNs sandbox, so the app registers with `"environment": "sandbox"` in Debug and `"production"` in TestFlight and App Store builds.
