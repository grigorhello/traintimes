# Train Times — design handoff for the TrainTimes Xcode project

Everything the app needs from the design side, ready to drop into Xcode.
Source of truth for behaviour: the Claude Doc "Train Times v1 — Screen Requirements".
Source of truth for look: the design canvas "Train Times (GO train app) — iPhone v1".
Share both with anyone who builds; the doc's "Acceptance checks" section is the QA list.

## What is in this folder

| File | Put it where | Notes |
|---|---|---|
| AppIcon.appiconset/ | Assets.xcassets (replace the empty AppIcon set) | 1024 px light, dark and tinted (iOS 18). Dark and tinted have a transparent background, as Apple asks. |
| AppIcon.svg, Symbol.svg | Design/ in the repo (not a target) | Vector masters. Symbol.svg takes the current text colour; use it for the About row and the website. |
| Colors.xcassets/ | Project root, add to the app target | 21 colour sets, light and dark. Names match DesignTokens.swift. |
| DesignTokens.swift | Sources/Design/ | Colours, spacing, radii, type styles, timeline geometry. |
| Localizable.strings | en-CA.lproj (Base) | Every user-facing string from the doc, with %@ for formatted times. |
| Fixtures.json | Tests/ or Preview Content/ | The canvas fixtures (7:32 AM Oakville to Union etc.) for previews and UI tests. |
| AppIcon-Dark-Preview.png | nowhere, just to look at | What the dark icon looks like on its system background. |

Xcode setup that matches the design: iOS 17 minimum, SwiftUI, Swift 6 language mode, one target, no login, no third-party UI kits.
Set Display Name = "Train Times"; the App Store name "Train Times: GO train schedule" is set in App Store Connect, not in the project.

## Build order (each step ships something you can tap)

1. **Shell and tokens (day 1).** New SwiftUI app, tab bar with Schedule and Alerts, Settings pushed from a gear, Colors.xcassets and DesignTokens.swift in, the icon in. Appearance and Time format settings working (they only touch the environment). Nothing else.
2. **Timeline screen on fixtures (week 1).** Build the Schedule screen from Fixtures.json before any network code. This is the hardest and most distinctive screen: to-scale vertical axis (7 pt/min), gridlines every 15 min, Now line, markers with minute pills, 14 pt connectors, cards that never touch (local zoom when two trains are under 16 pt apart), folds for gaps over 30 min, the next-train card with "in N min", the 7-day strip and the Now button. Do the delayed, cancelled, offline, loading, empty, large-text and compact states here too; the fixtures carry the first three. Snapshot-test every state (you already have swift-snapshot-testing on this machine).
3. **Route form and station search (week 2).** First-use empty state, From/To pickers, swap, favourites, saved on device (SwiftData or a small JSON store; no account). Route header on Schedule reads from it.
4. **Static schedule data (week 2–3).** GO Transit GTFS static from Metrolinx Open Data: import stops, routes, trips, stop_times, calendar for rail only, build "direct trains between A and B on service date D". Cache the feed on device, refresh weekly, keep the last good copy for offline. This replaces the fixtures behind the same view model.
5. **Live status (week 3–4).** GTFS-realtime TripUpdates from the same provider, polled every 30 s while Schedule is in the foreground: delays as a slip (scheduled stays, expected moves), cancellations, platforms, the freshness row ("Updated just now"), the watched-trip strip. Line notices from the Alerts feed. Trip identity = service date + trip id, never departure time. You will need an API key from Metrolinx's open data portal; check the current endpoints and terms there and keep the attribution page in Settings, it is a condition of use.
6. **Alerts (week 4–6).** The only part that needs a server, because a closed app cannot watch a feed. Smallest version: a tiny service (Cloudflare Worker, Supabase edge function on a cron, or a Vapor app) that stores device tokens plus alert rules, polls TripUpdates every 30 s, and sends APNs pushes using the notification strings in Localizable.strings. The app side: permission flow (the bell is one tap, the sheet opens only the first time), This trip and Repeat rules, the Alerts tab, deep links from a notification to Trip details for that exact trip and service date.
7. **Polish and release (week 6–7).** VoiceOver labels per the doc, Dynamic Type to xxxLarge, dark mode pass, the 3-second test with five GO riders, App Store screenshots from the real app with the captions in the doc, privacy and data pages live on traintimes.ca, the title reserved in App Store Connect.

Steps 2 and 3 need no network and no key, so start there even if the data access takes time to arrange.

## Rules that are easy to break in code

- A train keeps its name: the 7:32 AM train stays the 7:32 AM train when its estimate moves to 7:41 AM. Sort by scheduled time, anchor the card at the expected time.
- Every arrival is labelled, "Scheduled arrival" or "Est. arrival"; never a bare arrival time.
- Missing or stale data must never produce an On time badge. No live data means "Scheduled".
- Every delay or cancellation shown carries the time it was reported.
- Green is the brand, so On time is a neutral badge; only delays (amber) and cancellations (red) carry colour.
- All times go through one formatter that honours the Time format setting; all digits monospaced.
- No GO Transit or Metrolinx logos anywhere in the app; "GO train" only as description.
