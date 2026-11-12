# Train Times alert server

TT-140, decisions D38 and D43. A Cloudflare Worker with a D1 database, on the free Workers plan. The app registers its APNs device token and alert rules here under an anonymous installation id. Every minute the Worker checks the trips those rules watch against GO's GTFS-realtime TripUpdates feed and sends visible notifications through APNs. Once a day it applies retention. Every morning a GitHub Actions workflow reads the GO rail timetable from the public GTFS feed and uploads it to the Worker.

| File | Holds |
|---|---|
| `src/api.ts` | The app's API (the routes are listed at the top of the file) |
| `src/feedback.ts` | Feedback and questions from the app (`POST /v1/feedback`, TT-202, D85) |
| `src/upload.ts` | The daily timetable upload, checked against the workflow's GitHub OIDC token |
| `src/monitor.ts` | The minute cycle, storing the timetable, and retention |
| `src/alerts.ts` | The alert rules (thresholds, updates, coalescing, window, expiry) |
| `src/activity.ts` | The before-departure Live Activity's content and its start, update and end payloads (TT-178, D74) |
| `src/copy.ts` | Notification and Live Activity copy, word for word from `design/handoff/Localizable.strings` |
| `src/realtime.ts` | GTFS-realtime decoder and live mapping, ported from the app (D36) |
| `src/timetable.ts` | GTFS zip import and repeating-rule resolution |
| `src/apns.ts` | APNs with a .p8 key |
| `schema.sql` | The D1 tables |
| `scripts/push-timetable.ts` | Reads the GTFS zip and uploads the timetable; run by `.github/workflows/server-timetable.yml` |

## Live Activity (TT-178, D74)

The app sends its push-to-start token with the registration (`startToken`) and reports each before-departure activity to `PUT /v1/installations/:id/activities` (its update token, and `handedOff` once "I’m on board" turned it into the ride). For each alerted train whose installation has a push-to-start token, the minute cycle sends `event: start` 30 min before the expected departure (topic `ca.traintimes.TrainTimes.push-type.liveactivity`, the alert "Your 5:13 PM train is live"), once; `update` only when what the rider sees changes; and `end` 2 min after the train left, or at once when it is cancelled. Nothing more once the app reports the hand-off. These sends count toward the cycle's 45. GO's feeds post no platforms, so the server's activity always says "Check the board"; without live status it counts down on the timetable ("Scheduled"). The same .p8 key signs these pushes; nothing more to set up at Apple.

## Feedback (TT-202, D85)

The app's feedback sheet posts `{ kind, message, email?, appVersion, device, osVersion }` to `POST /v1/feedback`; the Worker checks it and stores it in the `feedback` table (no installation id; the email only when the rider gives one for a reply; kept a year). At most 300 messages a day are taken, against a script filling the table. To read them: Cloudflare dashboard › Storage & Databases › D1 › `traintimes-alerts` › Console, `SELECT datetime(created_at / 1000, 'unixepoch') AS at, kind, message, email, app_version, device FROM feedback ORDER BY id DESC;`, or ask a Claude session to read them through the Cloudflare connector.

## Free plan

The Workers Free plan is enough for hundreds of riders (D43). Its limits, and how the server stays inside them:

- **10 ms of CPU per run.** Reading the GTFS zip takes about 2 s, so GitHub Actions does it and the Worker only stores the result. A minute cycle reads only the rules whose watch window is open, decodes only the watched trips in the feed and reads today's timetable (the coming week's only when the usual train is missing today): about 3 ms for 300 riders at rush hour, measured locally. Cloudflare lets a run go over now and then, for example on a cold start.
- **50 outside requests per run.** The feed takes one, so a cycle makes at most 45 APNs calls (`MAX_SENDS` in `src/monitor.ts`). The rest are decided again the next minute, riders who have had no alert yet first, so in a big disruption with many riders on one line the last alerts can come a few minutes late.
- **100,000 requests a day.** The crons make about 1,500 and the app a few per rider.
- **D1: 5 million rows read and 100,000 written a day, 5 GB.** A cycle reads the rules in their window and the watched day's watches (about one row per watched trip): roughly 1 to 2 million rows a day for 300 riders.

If the app grows past this, turn on Workers Paid ($5 a month) and raise `MAX_SENDS`; nothing else changes.

## Test

Node 22.18 or later, no Xcode needed:

```sh
cd server && npm ci && npm test && npm run typecheck
```

The replays in `test/replay.test.ts` run the server end to end on the TT-131 sample feeds and the TT-130 sample timetable, so no Metrolinx key is needed.

## Deployed

Set up on 2026-11-08 on Grigor's Cloudflare account (Workers Free plan) at https://alerts.traintimes.ca, the address the app uses (`HTTPAlertServer`): the D1 database `traintimes-alerts` (id in `wrangler.toml`, schema applied), the Worker with both crons, the APNs secrets and the custom domain. Until the Metrolinx key is added (step 6) it sends no alerts; since TT-178 it does start, update and end the before-departure Live Activity on the timetable for app builds that send a push-to-start token.

To deploy a change, run `npx wrangler deploy` (step 4) or have a Claude session upload the bundle through the Cloudflare connector, keeping the secrets (`keep_bindings: ["secret_text"]`). When `schema.sql` changed, apply it first (`npx wrangler d1 execute traintimes-alerts --remote --file schema.sql`): it only adds the tables and indexes that are missing.

## Set up and deploy (once)

These steps need Grigor's accounts. Never paste a key in chat or commit it. Run the commands in `server/` after `npm ci` and `npx wrangler login`.

1. **Database.** Run `npx wrangler d1 create traintimes-alerts`, put the id it prints in `wrangler.toml` (`database_id`), then run `npx wrangler d1 execute traintimes-alerts --remote --file schema.sql`.
2. **APNs key.** In the Apple Developer account, go to Certificates, IDs & Profiles, then Keys, then +. Tick Apple Push Notifications service (APNs) and download the .p8 file (it downloads only once). Note the Key ID and your Team ID. The App ID `ca.traintimes.TrainTimes` needs the Push Notifications capability.
3. **Secrets.** Run `npx wrangler secret put APNS_KEY < AuthKey_XXXXXXXXXX.p8`, then `npx wrangler secret put APNS_KEY_ID` and `npx wrangler secret put APNS_TEAM_ID`. Or add them in the Cloudflare dashboard under Workers, then traintimes-alerts, then Settings, then Variables and Secrets.
4. **Deploy.** Run `npx wrangler deploy`. This also creates the `alerts.traintimes.ca` custom domain.
5. **Timetable.** Merge the database id from step 1 to main; until then the timetable workflow does nothing. Then run it once (GitHub, Actions, Alert server timetable, Run workflow) so the server has the timetable at once; after that it runs every morning. It needs no secret: the Worker checks the workflow's GitHub OIDC token. Each run covers 8 days, so a missed day does no harm. GitHub turns off scheduled workflows in a public repository after 60 days without a commit and emails a warning first; turn it back on in the Actions tab. A week after the last upload, repeat alerts stop (nothing is decided without a timetable), while This-trip alerts keep working from the feed's estimate at the rider's station.
6. **When the Metrolinx key arrives**, run `npx wrangler secret put METROLINX_API_KEY`. Until then there is no live feed, so the server sends nothing.

A development build's device token works only with APNs sandbox, so the app registers with `"environment": "sandbox"` in Debug and `"production"` in TestFlight and App Store builds.
