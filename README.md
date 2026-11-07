# Train Times

Native SwiftUI iPhone app for GO train riders: your next direct trains on one timeline, delays shown as they are reported, alerts for the trains you watch. Independent app, not affiliated with GO Transit or Metrolinx.

- `design/Screen-Requirements.md`: how every v1 screen behaves (source of truth for behaviour; its Acceptance checks are the QA list)
- `design/frames/`: every artboard of the design canvas "Train Times (GO train app) — iPhone v1" as PNG (source of truth for look)
- `design/canvas/`: the canvas artboard sources (`.dc.html`) and design system tokens
- `design/handoff/`: the Xcode-ready handoff (app icon, colour sets, `DesignTokens.swift`, `Localizable.strings`, `Fixtures.json`) and its README with the build order
- `docs/BUILD-ORDER.md`: the tickets in sequence with their blockers
- `docs/DECISIONS.md`: the v1 build decisions (D1…) and the open questions with the ticket each blocks
- `CLAUDE.md`: the per-ticket workflow every Claude session follows

## Build

Open `TrainTimes.xcodeproj` in Xcode 16 or later and run the TrainTimes scheme, or run `scripts/ci-test.sh` to build and run every test on a simulator. iOS 17 minimum, Swift 6. Conventions are in `CLAUDE.md`.

Tickets live in GitHub issues (TT-100 to TT-154) and on the Notion board "TrainTimes · Product board". Build in the Order shown there.
