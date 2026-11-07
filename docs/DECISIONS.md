# Train Times v1 — build decisions and open questions

The one list every ticket relies on. Decisions are numbered and never renumbered; to change one, strike it through, add the replacement as a new number and say which ticket changed it.

Sources: [`design/handoff/README.md`](../design/handoff/README.md) and [`design/Screen-Requirements.md`](../design/Screen-Requirements.md) (§ Purpose and scope, § Navigation and shared rules, § Settings, § Brand: Train Times, § Visual tokens and accessibility, § Assumptions and open questions). Ticket: TT-100 (#1).

## Decisions

### Platform and project

- **D1. iOS 17 minimum.**
- **D2. SwiftUI** for every screen.
- **D3. Swift 6 language mode**; zero warnings.
- **D4. One app target.** Test targets are separate; the alert server (TT-140) is its own project, not an app target.
- **D5. No login and no account.** Route, favourites and settings stay on device; alerts use an anonymous installation id. No payment, subscription, advertising, upgrade or rating prompt anywhere, and no hidden debug menu in release builds.
- **D6. No third-party UI kits.** Every screen is built from `Sources/Design` tokens and components (TT-102). Test-only dependencies such as swift-snapshot-testing are allowed.
- **D7. Display Name is "Train Times".** The App Store name "Train Times: GO train schedule" is set in App Store Connect, not in the project.

### Product

- **D8. The requirements doc wins over the brief.** Where `Screen-Requirements.md` and the Product Design Brief v1 differ, the requirements doc is the source of truth for behaviour; the Schedule screen is a to-scale vertical timeline, not the brief's row list. The design canvas "Train Times (GO train app) — iPhone v1", exported as `design/frames/`, is the source of truth for look; token values come from the handoff (`DesignTokens.swift`, `Colors.xcassets`).
- **D9. Trip identity = service date + feed trip id**, never departure time. A train keeps its name: the 7:32 AM train stays the "7:32 AM train" when its estimate moves to 7:41 AM. Sort by scheduled time, anchor the card at the expected time.
- **D10. No GO Transit or Metrolinx marks** anywhere in the app, its icon, the store screenshots or traintimes.ca, and the Train Times lockup is never shown beside them. The icon never carries letters (a G or GO), GO's olive green, status colours, or an added clock or badge; no lockup on the launch screen, the Schedule navigation title, empty states or notifications; the wordmark is never green text on its own. "GO train" is used only descriptively (store listing, the tagline "Your next GO train, at a glance.", the "Official GO service updates" link), never as the brand. No domain containing go or gotrain.
- **D11. Two tabs only, Schedule and Alerts.** Settings is pushed from a gear in the Schedule header. Route editing, station search, trip details, alert setup and line notices open as sheets. No splash, tutorial, permission request or carousel before the first timetable.
- **D12. Status is colour + word + icon from a closed set:** On time, Delayed N min, Cancelled, Stop skipped, Scheduled, Last reported HH:MM, Offline. On time needs fresh live evidence or a fresh applicable prediction with a delay under 3 min; Delayed starts at a reported delay of 3 min or more. On time is a neutral badge (green is the brand); only Delayed (amber) and Cancelled / Stop skipped (red) carry colour.
- **D13. Missing or stale data never shows On time.** No live data, or any day other than today, means "Scheduled"; data older than the freshness threshold (Q2) means "Last reported HH:MM".
- **D14. Freshness is always visible:** one line stating the data mode (live, scheduled only, stale, offline). A refresh keeps row identity and scroll position.
- **D15. Every arrival is labelled** "Scheduled arrival" or "Est. arrival"; never a bare arrival time. Destination arrival stays Scheduled until the feed is shown to support an estimate (Q3).
- **D16. Every delay or cancellation shown carries the time it was reported.**
- **D17. One time formatter** for every time in the app, in notifications and in VoiceOver: device 12/24-hour setting by default, overridable in Settings (Device, 12-hour, 24-hour), America/Toronto with DST, tabular digits (TT-106). The alert server needs each device's time format to write notifications, so TT-140 (#22) stores it with the device token.
- **D18. The GO service day:** trips after midnight belong to the previous service day and sort after 11:59 PM.
- **D19. Copy:** sentence case, Canadian spelling, no exclamation marks, no emoji, one fact per sentence. States, never promises: "expected", never "will arrive"; never claim real-time, instant or guaranteed. All strings come from `Localizable.strings`.
- **D20. Fixtures stay fixtures.** Station names, times, platforms and stop lists on the canvas are illustrative; fixtures are isolated from production data and never shown as live service. M0 and M1 are built on fixtures with no network and no API key.
- **D21. Express is a tag, not a status,** and appears only when the feed verifies it (Q4).
- **D22. Accessibility baseline:** status is never colour alone, 44 pt hit targets, Dynamic Type supported through the accessibility sizes (the requirements doc's AX5 wins over the handoff's xxxLarge, because the handoff README names the requirements doc as the source of truth for behaviour), Reduce Motion respected, no countdowns, pulsing dots or flashing.

- **D23. Device and review scope (Grigor, 2026-11-07, TT-101).** Build, test and review on iPhone 17 Pro only. Accessibility (VoiceOver labels, Dynamic Type and large-text layouts) and iPad layout are not reviewed or tested in ticket work, even where an issue's Definition of done lists them; the app stays iPhone only. D22's colour + word + icon status rule and 44 pt targets still apply because they are part of the design.

## Open questions

Each question has two points: **needed by** is the ticket that cannot start without an answer; **blocks / closes in** is the ticket that answers it, usually because it needs the live feed or the built screen: that ticket ships its feature only once the question is closed. Answering the feed questions is out of TT-100's scope. When a question closes, tick it and add the answer here as a decision. Owner is Grigor unless noted; dates are the start of the named build step in [`BUILD-ORDER.md`](BUILD-ORDER.md).

- [ ] **Q1. Metrolinx GO API access and terms.** Confirm credentials, permitted refresh rate, trip identifiers, cancellation semantics, platform availability and timestamps for the real-time feed. Live endpoints were not validated in the research behind the brief. **Needed by TT-130 (#19)** (credentials and terms, step 19); feed semantics **block and close in TT-131 (#20)**. Owner: Grigor (API key, see below).
- [ ] **Q2. Freshness threshold.** 3 min is the proposed point where live data is demoted to "Last reported"; tune against observed feed update intervals. Build with 3 min; **blocks and closes in TT-131 (#20)**.
- [ ] **Q3. Estimated arrival support.** Confirm the feed provides a reliable destination estimate; until it does, destination arrival is always labelled Scheduled. **Blocks and closes in TT-131 (#20)**.
- [ ] **Q4. Express flag.** Confirm how express or limited-stop services are marked; show the tag only when verified. **Blocks and closes in TT-130 (#19)**.
- [ ] **Q5. Line notice scoping.** Confirm the service-alert feed and how a notice is scoped to a line; shown as a link in the freshness row, never as a trip status. **Blocks and closes in TT-132 (#21)**.
- [ ] **Q6. Schedule horizon.** The day strip assumes at least 7 days of published schedule; confirm the GTFS validity window and how far the strip may scroll. **Blocks and closes in TT-130 (#19)**.
- [x] **Q7. Attribution wording.** Closed in TT-151 (#28), 2026-11-07: traintimes.ca/data ships with the standard Open Government Licence – Ontario – Metrolinx attribution and the independent-app line (`website/data/index.html`). Grigor: recheck the wording against the licence terms that come with the API key in **TT-130 (#19)** and update the page there if it differs.
- [ ] **Q8. Server retention.** Alert service keyed by anonymous installation id; proposed: rules deleted 24 h after their last service date, device tokens on uninstall or after 30 days of inactivity. **Needed by TT-140 (#22)**, step 22. Owner: Grigor (product call).
- [ ] **Q9. Compact phone test.** Two full departures plus the next time are accepted on 667 pt screens; confirm on an iPhone SE. **Blocks and closes in TT-116 (#14)** with the device test, signed off in TT-153 (#30).
- [ ] **Q10. Minimum-gap zoom mapping.** Local stretch of the affected segment; confirm the scroll position mapping stays stable when live estimates move trains across the 16 pt threshold. **Blocks and closes in TT-131 (#20)** (the first ticket where estimates move trains; the static engine is TT-111).
- [ ] **Q11. Usability round.** Measure time to identify the next train on the timeline (three cards visible) against the earlier row list (four to five visible), and the one-tap bell against the sheet. **Blocks and closes in TT-153 (#30)**, before the public release. Owner: Grigor (runs the round with riders).

## Metrolinx open data API key

Gates M2 (TT-130 onward) and can take time, so it is requested now.

| | |
|---|---|
| Owner | Grigor (the application is made under his name and contact details) |
| Where | GO API registration form https://api.openmetrolinx.com/OpenDataAPI/Help/Registration/en (manual review, up to 10 business days). Questions: OpenData.Program@metrolinx.com. Licence: Open Government Licence – Ontario – Metrolinx |
| Request sent | **2026-11-06** (America/Toronto; 2026-11-07 00:17 UTC). Confirmation: "Your request has been received successfully. Please allow for up to ten business days to process." Chase OpenData.Program@metrolinx.com if nothing by 2026-11-20. |
| What it covers | The GO API lists Service at a Glance (in-service trips), Stop & Schedule, Service Update (alerts, Union departures) and Fares. GTFS-realtime trip updates are not named; confirm with the key (Q1). |
| Key received | — (store it as a secret, never in the repo) |
