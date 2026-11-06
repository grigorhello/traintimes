# Train Times v1 — build decisions and open questions

The one list every ticket relies on. Decisions are numbered and never renumbered; to change one, strike it through, add the replacement as a new number and say which ticket changed it.

Sources: [`design/handoff/README.md`](../design/handoff/README.md) and [`design/Screen-Requirements.md`](../design/Screen-Requirements.md) (§ Purpose and scope, § Navigation and shared rules, § Assumptions and open questions). Ticket: TT-100 (#1).

## Decisions

### Platform and project

- **D1. iOS 17 minimum.** No back-deployment shims for older systems.
- **D2. SwiftUI** for every screen. UIKit only where SwiftUI has no equivalent, wrapped in a representable.
- **D3. Swift 6 language mode** with complete concurrency checking; zero warnings.
- **D4. One app target.** Tests live in their own test targets; no frameworks or extensions in v1 (the alert server in TT-140 is a separate project, not an app target).
- **D5. No login and no account.** Route, favourites and settings stay on device; alerts use an anonymous installation id.
- **D6. No third-party UI kits.** Every screen is built from `Sources/Design` tokens and components (TT-102). Test-only dependencies such as swift-snapshot-testing are allowed.
- **D7. Display Name is "Train Times".** The App Store name "Train Times: GO train schedule" is set in App Store Connect, not in the project.

### Product

- **D8. The requirements doc wins over the brief.** Where `Screen-Requirements.md` and the Product Design Brief v1 differ, the requirements doc is the source of truth for behaviour; the Schedule screen is a to-scale vertical timeline, not the brief's row list. The design frames in `design/frames/` are the source of truth for look.
- **D9. Trip identity = service date + feed trip id**, never departure time. A train keeps its name: the 7:32 AM train stays the "7:32 AM train" when its estimate moves to 7:41 AM. Sort by scheduled time, anchor the card at the expected time.
- **D10. No GO Transit or Metrolinx marks** anywhere in the app, its icon, screenshots or website. "GO train" appears only as a description (App Store title, subtitle, description). The app is independent and not affiliated with GO Transit or Metrolinx.
- **D11. Two tabs only, Schedule and Alerts.** Settings is pushed from a gear in the Schedule header; everything else opens as a sheet. No splash, tutorial, permission request or carousel before the first timetable.
- **D12. Status is colour + word + icon from a closed set:** On time, Delayed N min, Cancelled, Stop skipped, Scheduled, Last reported HH:MM, Offline. On time is a neutral badge (green is the brand); only delays (amber) and cancellations (red) carry colour.
- **D13. Missing or stale data never shows On time.** No live data means "Scheduled"; data older than the freshness threshold means "Last reported HH:MM".
- **D14. Every arrival is labelled** "Scheduled arrival" or "Est. arrival"; never a bare arrival time. Destination arrival stays Scheduled until the feed is shown to support an estimate (Q3).
- **D15. Every delay or cancellation shown carries the time it was reported.**
- **D16. One time formatter** for every time in the app, honouring the 12/24-hour setting, in America/Toronto with DST, all digits tabular (TT-106).
- **D17. The GO service day:** trips after midnight belong to the previous service day and sort after 11:59 PM.
- **D18. Copy:** sentence case, Canadian spelling, no exclamation marks, no emoji, no promises. All strings come from `Localizable.strings`.
- **D19. Fixtures stay fixtures.** Station names, times, platforms and stop lists on the canvas are illustrative; fixtures are isolated from production data and never shown as live service. M0 and M1 are built on fixtures with no network and no API key.
- **D20. Express is a tag, not a status,** and appears only when the feed verifies it (Q4).

## Open questions

Each question blocks the ticket named on its line; it must be answered (and the answer added here as a decision) before that ticket starts. Owner is Grigor unless noted; the deadline is the start of the blocked ticket's build step from [`BUILD-ORDER.md`](BUILD-ORDER.md).

- [ ] **Q1. Metrolinx GO API access and terms.** Confirm credentials, permitted refresh rate, trip identifiers, cancellation semantics, platform availability and timestamps for the real-time feed. Live endpoints were not validated in the research behind the brief. **Blocks TT-130 (#19)** and TT-131 (#20). Deadline: before step 19.
- [ ] **Q2. Freshness threshold.** 3 min is the proposed point where live data is demoted to "Last reported"; tune against observed feed update intervals. **Blocks TT-131 (#20).** Deadline: before step 20.
- [ ] **Q3. Estimated arrival support.** Confirm the feed provides a reliable destination estimate; until it does, destination arrival is always labelled Scheduled. **Blocks TT-131 (#20).** Deadline: before step 20.
- [ ] **Q4. Express flag.** Confirm how express or limited-stop services are marked; show the tag only when verified. **Blocks TT-130 (#19).** Deadline: before step 19.
- [ ] **Q5. Line notice scoping.** Confirm the service-alert feed and how a notice is scoped to a line; shown as a link in the freshness row, never as a trip status. **Blocks TT-132 (#21).** Deadline: before step 21.
- [ ] **Q6. Schedule horizon.** The day strip assumes at least 7 days of published schedule; confirm the GTFS validity window and how far the strip may scroll. **Blocks TT-130 (#19).** Deadline: before step 19.
- [ ] **Q7. Attribution wording.** Data attribution and independent-app wording from the provider's current terms, for the Settings data page and traintimes.ca/data. **Blocks TT-151 (#28)** (the in-app copy in TT-105 uses a placeholder until then). Deadline: before step 28.
- [ ] **Q8. Server retention.** Alert service keyed by anonymous installation id; proposed: rules deleted 24 h after their last service date, device tokens on uninstall or after 30 days of inactivity. **Blocks TT-140 (#22).** Deadline: before step 22.
- [ ] **Q9. Compact phone test.** Two full departures plus the next time are accepted on 667 pt screens; confirm on an iPhone SE. **Blocks TT-116 (#14)** (layout) and is signed off in TT-153 (#30). Deadline: before step 14.
- [ ] **Q10. Minimum-gap zoom mapping.** Local stretch of the affected segment; confirm the scroll position mapping stays stable when live estimates move trains across the 16 pt threshold. **Blocks TT-131 (#20)** (first ticket where estimates move trains; the static engine is TT-111). Deadline: before step 20.
- [ ] **Q11. Usability round.** Measure time to identify the next train on the timeline (three cards visible) against the earlier row list (four to five visible), and the one-tap bell against the sheet. **Blocks TT-153 (#30)**, before the public release. Deadline: before step 30.

## Metrolinx open data API key

Gates M2 (TT-130 onward) and can take time, so it is requested now.

| | |
|---|---|
| Owner | Grigor (the application is made under his name and contact details) |
| Where | Metrolinx / GO Transit open data portal (check the current URL and terms there) |
| Request sent | **Not yet — pending Grigor.** Record the date here when sent: `YYYY-MM-DD` |
| Key received | — (store it as a secret, never in the repo) |
