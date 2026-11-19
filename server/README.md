# Train Times alert server

TT-140, decisions D38 and D43. A Cloudflare Worker with a D1 database, on the free Workers plan. The app registers its APNs device token and alert rules here under an anonymous installation id. Every minute the Worker checks the trips those rules watch against GO's GTFS-realtime TripUpdates feed and sends visible notifications through APNs. Once a day it applies retention. Every morning a GitHub Actions workflow reads the GO rail timetable from the public GTFS feed and uploads it to the Worker.

| File | Holds |
|---|---|
| `src/api.ts` | The app's API (the routes are listed at the top of the file) |
| `src/feedback.ts` | Feedback and questions from the app (`POST /v1/feedback`, TT-202, D85) |
| `src/upload.ts` | The daily timetable upload, checked against the workflow's GitHub OIDC token |
| `src/monitor.ts` | The minute cycle, storing the timetable, and retention |
| `src/alerts.ts` | The alert rules (thresholds, updates, coalescing, window, expiry) |
| `src/activity.ts` | The before-departure Live Activity's content and its start, update and end payloads (TT-178, D74), and the boarding rule (TT-233, D114) |
| `src/copy.ts` | Notification and Live Activity copy, word for word from `design/handoff/Localizable.strings` |
| `src/realtime.ts` | GTFS-realtime decoder and live mapping, ported from the app (D36), and the VehiclePosition decoder (TT-179) |
| `src/relay.ts` | GO's live feeds relayed to the app with the Worker's key (TT-179, D88) |
| `src/platforms.ts` | GO's station boards relayed the same way, for the posted platforms (TT-225, D104) |
| `src/stations.ts` | Where each GO rail station is, from GO's stops.txt (TT-233): the cycle measures a train's distance to the rider's station with it |
| `src/timetable.ts` | GTFS zip import and repeating-rule resolution |
| `src/apns.ts` | APNs with a .p8 key |
| `schema.sql` | The D1 tables |
| `scripts/push-timetable.ts` | Reads the GTFS zip and uploads the timetable; run by `.github/workflows/server-timetable.yml` |

## Live Activity (TT-178, D74)

The app sends its push-to-start token with the registration (`startToken`) and reports each before-departure activity to `PUT /v1/installations/:id/activities` (its update token, and `handedOff` once "I’m on board" turned it into the ride). For each alerted train whose installation has a push-to-start token, the minute cycle sends `event: start` 30 min before the expected departure (topic `ca.traintimes.TrainTimes.push-type.liveactivity`, the alert "Your 5:13 PM train is live"), once; `update` only when what the rider sees changes; and `end` when the departure question ends, or at once when it is cancelled. Once the train has left the update turns the card into the question "On board?" (TT-231, D110: `phase: departed` with `asks: true`, with an alert, "On the 5:13 PM train?"), for 10 min or until the rider's stop if sooner; an alerted train with no card (no push-to-start token, or no update token) gets the same question once as a notification (category `depart.question`, state `notified`). The app reports `asked` when it was in front as the train left: the update then carries no alert and no notification goes. Nothing more once the app reports the hand-off (a ride, or No). These sends count toward the cycle's `MAX_SENDS`. Without live status it counts down on the timetable. The same .p8 key signs these pushes; nothing more to set up at Apple.

**A card ends with its alert (TT-240, D118).** The app ends a before-departure card at the tap when its alert is removed or switched off, and reports it with `removed: true` on `PUT …/activities`: the row becomes `removed` with no token, so no cycle updates, ends or starts a card for that train, even while the rule's own DELETE or paused save is still on its way, and a rule saved switched on between its stations (Undo, the bell again) deletes the row, so the next cycle starts a fresh card with the push-to-start token, whatever train the app shows. A card the ride took over, or whose question went as a notification, is left as it is, and a later report of a new card from the app takes the row back. As the backstop (the app was closed meanwhile, an older build, an alert that went to Review needed), every minute cycle, idle ones too, sweeps the cards nobody watches: activity rows that are `started` or `asked`, have the card's token and a `shown`, and whose train no watch of that cycle claims get `event: end` (the line they last showed, leaving the Lock Screen at once), and the row is deleted, so an alert switched on again starts a fresh card. `DELETE …/rules/:rule` and a paused `PUT` set an empty `shown` on that installation's cards between the rule's stations that no cycle had followed yet, so a bell turned on and off within the minute is swept too. Rows without `shown` that no rule touched (Demo trains › Departure, a card of another route) and cards handed off or answered No are left alone. The ends count toward `MAX_SENDS`; the sweep is one more indexed D1 read per cycle. A row that reached `ended` goes back to `started` only when the app reports another update token for the train (a new card). The app sends a hand-off report even when the rider has no alert left, so a card that became the ride is never swept.

**Boarding at the platform (TT-233, D114).** "Boarding now" and the moment the train has left follow the app's rule (`BoardingRule` in the app, `boardingPhase` in `src/activity.ts`; change both together). A train is boarding while GO's train feed places it within 350 m of the rider's station, not more than 2 min ago, with its platform posted, and it stays boarding past its time while it stands there ("7:13 AM boarding now" over "Departing", the platform in the pill). It has left, and the card asks, when the station has dropped out of its TripUpdates (from 1 min before its time) or its position is farther away once its time has come. With no fresh position the clock decides as before: boarding for the last 2 min, left at its time. The question's end does not move (10 min after the expected departure, or the rider's stop), and the question is asked once, whatever a later position says: its alert goes with the update that turns the card into the question and not with a later one that only moves its time, and the card stays the question unless the train's expected time moves to more than 1 min ahead (a delay reported after the question), when it counts down again and asks when the train leaves. For this the cycle reads the VehiclePosition snapshot the relay already holds, once, and only while an alerted train is in its activity window (from 30 min before it leaves until the rider is asked or the window ends); it reads a station's board (`src/platforms.ts`) only for a station where such a train stands, for two stations a cycle at most (the ones where most riders wait). A train at a third station, or at a station missing from `src/stations.ts`, does not board from the server; the platform shows on the server's card only while the board is read, otherwise the pill is the dash.

## Live feeds (TT-179, D88)

The Metrolinx key is only this Worker's secret `METROLINX_API_KEY`; the app ships none and reads GO's live data here: `GET /v1/live/trip-updates` and `GET /v1/live/alerts` (GTFS-realtime protobuf, as GO sends it when asked with `Accept: application/x-protobuf`; its default is JSON) and `GET /v1/trains[?line=LW]` (JSON from the VehiclePosition feed: trip id, service date, latitude, longitude, stopped, timestamp in seconds). Each feed is fetched from GO at most once per 30 s per Cloudflare data centre, whatever the number of phones (a copy in the isolate's memory, then the Cache API), and the minute cycle reads TripUpdates and, for boarding, VehiclePosition and the station boards through the same copies (one decode per VehiclePosition snapshot, shared with `/v1/trains`). A failed GO call is remembered for 30 s as well, and without the key GO is never called, so a bad key or an outage never floods Metrolinx (it can suspend a key for many failed calls or 429s). While GO fails the endpoints answer 503 and the app shows Offline.

## Feedback (TT-202, D85)

The app's feedback sheet posts `{ kind, message, email?, appVersion, device, osVersion }` to `POST /v1/feedback`; the Worker checks it and stores it in the `feedback` table (no installation id; the email only when the rider gives one for a reply; kept a year). At most 300 messages a day are taken, against a script filling the table. To read them: Cloudflare dashboard › Storage & Databases › D1 › `traintimes-alerts` › Console, `SELECT datetime(created_at / 1000, 'unixepoch') AS at, kind, message, email, app_version, device FROM feedback ORDER BY id DESC;`, or ask a Claude session to read them through the Cloudflare connector.

## Free plan

The Workers Free plan is enough for hundreds of riders (D43). Its limits, and how the server stays inside them:

- **10 ms of CPU per run.** Reading the GTFS zip takes about 2 s, so GitHub Actions does it and the Worker only stores the result. A minute cycle reads only the rules whose watch window is open, decodes only the watched trips in the feed and reads today's timetable (the coming week's only when the usual train is missing today): about 3 ms for 300 riders at rush hour, measured locally. The boarding rule (TT-233) adds about 0.2 ms to a cycle that needs it, measured locally on Node 22: 0.07 ms to decode a VehiclePosition feed of 80 vehicles (0.4 ms for 400), 0.02 ms for the rule on 20 trains and 0.05 ms per station board; about 2 ms more on the first run of a new isolate. Cloudflare lets a run go over now and then, for example on a cold start.
- **50 outside requests per run**, the Cache API's calls included. A read through a relay costs 3 at worst (the cache's match, the call to GO, the cache's put): TripUpdates, the train positions and two station boards make 12, so a cycle makes at most 36 APNs calls (`MAX_SENDS` in `src/monitor.ts`; 45 before TT-233), with 2 to spare. The rest are decided again the next minute, riders who have had no alert yet first, so in a big disruption with many riders on one line the last alerts can come a few minutes late.
- **100,000 requests a day.** The crons make about 1,500, and the app a few per rider plus its live polls: two every 30 s while Schedule is open, so about 10,000 a day for 300 riders who look for 10 minutes.
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
6. **The Metrolinx key** (received 2026-11-13): `npx wrangler secret put METROLINX_API_KEY`, or Cloudflare dashboard › Workers › `traintimes-alerts` › Settings › Variables and Secrets › Add, type Secret. Without it GO is never called: the live endpoints answer 503 and the server sends nothing.

A development build's device token works only with APNs sandbox, so the app registers with `"environment": "sandbox"` in Debug and `"production"` in TestFlight and App Store builds.
