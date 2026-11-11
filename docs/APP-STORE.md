# App Store listing (TT-152, D42)

What is entered in App Store Connect for Train Times. Title, subtitle, promotional text, keywords and the description's first line are as in `design/Screen-Requirements.md` § Brand: Train Times (keywords use "transit" in place of "go transit", D42). The rest of the description is new, written to the same voice rules (plain words, Canadian spelling, states never promises, no "real-time" claims).

## App Information (Apple: App Store › App Information)

| Field | Value |
|---|---|
| Name (30 max) | Train Times: GO train schedule |
| Subtitle (30 max) | Today's GO trains and delays |
| Bundle ID | ca.traintimes.TrainTimes |
| Primary language | English (Canada) |
| SKU | traintimes-ios |
| Primary category | Travel |
| Secondary category | Navigation |
| Content rights | Contains third-party content (Metrolinx open data), with the rights to use it |
| Age rating | Answer None / No to every question, giving 4+ |
| Privacy Policy URL | https://traintimes.ca/privacy/ |
| Price | Free |

## Version 1.0 page

| Field | Value |
|---|---|
| Promotional text (170 max) | Independent app for GO train riders. Your next direct trains on one timeline, delays shown as they are reported, alerts for the trains you watch. No login, no ads. |
| Keywords (100 max) | transit,lakeshore,union station,toronto,hamilton,commuter,rail,departures,late,next train |
| Support URL | https://traintimes.ca/support/ |
| Marketing URL | https://traintimes.ca/ |
| Copyright | 2026 and the owner's name (the developer account holder) |

### Description

```
Independent app, not affiliated with GO Transit or Metrolinx.

Train Times shows the next direct GO trains between your two stations on one to-scale timeline, delays as they are reported, and alerts for the trains you watch. No login, no ads.

YOUR NEXT TRAIN, AT A GLANCE
• Pick two stations once. The app opens on your route next time.
• Trains are drawn to scale, so the gap to the next one is easy to see.
• The next train you can catch stands out, with the minutes until it leaves.
• Platforms show as soon as they are published.
• Look ahead to another day with the day strip.
• Your last three routes are one tap away.

DELAYS AND CANCELLATIONS, SAID PLAINLY
• A delayed train keeps its scheduled time and shows when it is now expected.
• Every delay and cancellation shows the time it was reported.
• Notices for your line open from the top of the timeline.
• The time of the last update is always on screen.

ALERTS FOR THE TRAINS YOU WATCH
• Tap the bell on a train to get its delays and cancellations.
• Repeat an alert for your usual weekday train.
• Updates start 1 hour before the scheduled departure. Changes are sent as they are reported. Delivery is best effort.

PRIVATE BY DESIGN
• No account, no ads and no tracking.
• Your routes stay on your iPhone.
• Alerts use an anonymous installation id, never your name or Apple ID.

Light and dark appearance. 12 or 24-hour time.

Schedule and status data: Metrolinx open data. Times may differ from station displays. For official service updates, check GO Transit.
```

## Screenshots (later, from the finished app)

Captions in order: Your next GO train, in 11 min · Delays drawn as reported · Watch a train with one tap · Alerts for the trains you watch · Cancelled, said plainly. iPhone only (the app is iPhone only, so no iPad set). App Store Connect needs the 6.9-inch size (1320 × 2868, iPhone 17 Pro Max simulator); the iPhone 17 Pro's 1206 × 2622 is not an accepted size. No GO Transit or Metrolinx marks in any screenshot.

## Before submitting: privacy label and App Review notes (TT-154)

- **App Privacy › Location (TT-171, TT-176, D60, D73):** Precise Location and Coarse Location, used for App Functionality, not linked to the user, not used for tracking. Location is used on the phone to follow a ride and to notice a GO train, and never leaves it.
- **App Review notes, background location (TT-176, D73):** "Train Times uses location in the background only for features the rider turns on. During a ride the rider starts (On board), it follows the train to show the next station and tap before the rider's stop. With "Detect my train" (Settings › Notifications, off by default, opt-in with location Always), significant location changes wake the app and, near a GO line between 5 AM and 1 AM, GPS runs for at most 12 minutes to match the phone to a train; on a match it posts a notification asking "On the 5:13 PM train?". Nothing starts without the rider's tap, and location never leaves the phone."

## TestFlight builds (TT-154, D47)

One-time setup, done by the account holder or an Admin in App Store Connect and GitHub:

1. App Store Connect › Users and Access › Integrations › App Store Connect API › Team Keys: generate a key named "GitHub TestFlight" with the **Admin** role (it creates a signing certificate for each build). Download the `.p8` file (it can be downloaded only once) and note the Key ID and the Issuer ID shown above the list.
2. GitHub › grigorhello/traintimes › Settings › Secrets and variables › Actions › New repository secret, three times: `ASC_KEY_ID` (the Key ID), `ASC_ISSUER_ID` (the Issuer ID) and `ASC_KEY_P8` (the whole `.p8` file opened in a text editor, including the BEGIN and END lines).
3. App Store Connect › Train Times › TestFlight › Internal Testing: create a group and add yourself, so each processed build reaches the TestFlight app on your iPhone.

Each build: GitHub › Actions › TestFlight › Run workflow (branch `main`). It uploads 1.0 (run number) and finishes once TestFlight has processed it, about 15 to 30 minutes in all. Apple may email the account holder about the certificate each run creates and revokes. When the Metrolinx key arrives, add it as the `METROLINX_API_KEY` secret and run the workflow again.
