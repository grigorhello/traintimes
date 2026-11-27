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

- **App Privacy › Analytics (TT-208, D92):** Identifiers › Device ID and Usage Data › Product Interaction, used for Analytics, not linked to the user, not used for tracking (PostHog, anonymous, no tracking prompt). Events are listed in `docs/ANALYTICS.md`.
- **App Privacy › Location (TT-171, TT-234, TT-242, TT-243, TT-251, D60, D116, D120, D127):** Precise Location and Coarse Location, used for App Functionality, not linked to the user, not used for tracking. Location is used on the phone to follow a ride, to start the ride when the rider leaves with a train they set an alert on, to warn the rider who boards another train than the one they set an alert on or said they were on, and to set the route’s direction when the app opens, and never leaves it.
- **App Review notes, location (TT-234, TT-242, TT-243, TT-251, D116, D120, D127):** "Train Times uses location in the background during a ride and, around the departure of a train the rider set an alert on, to tell whether the rider is on it, or on another train that does not go to their stop (then it warns them). A ride starts with “I’m on board” or Yes on the “On board?” question, or by itself on an alerted train once the phone leaves the station with it (Settings › Automatic ride, on by default; “Not on it” undoes it). If the app was open in the 30 minutes before an alerted train leaves, location keeps running until the app decides: at most 10 minutes after the train leaves, or, while the phone is still at the station (a missed train), at most 30 minutes after it leaves, then up to 6 minutes of the next train's movement, or until a warning it shows is answered or expires (the location indicator shows). With “When the app is closed” (Settings, off by default, opt-in with location Always), significant location changes or the train’s Live Activity arriving wake the app for trains the rider set an alert on only, and GPS runs only until it decides. When the app opens and location is already allowed While Using, it takes one reading to show trains from the closer of the rider’s two saved stations (Settings › Automatic direction, can be turned off). The reading is compared on the phone and is not kept or sent. The app never asks for location at launch. Location never leaves the phone."

## TestFlight builds (TT-154, D47)

One-time setup, done by the account holder or an Admin in App Store Connect and GitHub:

1. App Store Connect › Users and Access › Integrations › App Store Connect API › Team Keys: generate a key named "GitHub TestFlight" with the **Admin** role (it creates a signing certificate for each build). Download the `.p8` file (it can be downloaded only once) and note the Key ID and the Issuer ID shown above the list.
2. GitHub › grigorhello/traintimes › Settings › Secrets and variables › Actions › New repository secret, three times: `ASC_KEY_ID` (the Key ID), `ASC_ISSUER_ID` (the Issuer ID) and `ASC_KEY_P8` (the whole `.p8` file opened in a text editor, including the BEGIN and END lines).
3. App Store Connect › Train Times › TestFlight › Internal Testing: create a group and add yourself, so each processed build reaches the TestFlight app on your iPhone.

Each build: GitHub › Actions › TestFlight › Run workflow (branch `main`). It uploads 1.0 (run number) and finishes once TestFlight has processed it, about 15 to 30 minutes in all. Apple may email the account holder about the certificate each run creates and revokes. The build needs no Metrolinx key: live data comes through the alert server (D88).
