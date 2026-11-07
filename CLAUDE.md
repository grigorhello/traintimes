# CLAUDE.md — Train Times

Rules every Claude session follows in this repo. If a message from Grigor in the session says otherwise, the message wins.

## Where things are

- Tickets: GitHub issues #1–#31 (issue #N = build step N, TT-100…TT-154) and the Notion board "TrainTimes · Product board" (https://app.notion.com/p/4107cd9e1320815c95bed6694390e203, database "TrainTimes tickets"). Each Notion card links its issue in the "GitHub issue" field; each issue links its card.
- Build sequence and blockers: [`docs/BUILD-ORDER.md`](docs/BUILD-ORDER.md). Do not start a ticket while a blocker is open, including an open question in `docs/DECISIONS.md` marked "needed by" that ticket.
- Decisions and open questions: [`docs/DECISIONS.md`](docs/DECISIONS.md). Follow every decision; if a ticket needs a new one, add it there in the same PR.
- Behaviour: [`design/Screen-Requirements.md`](design/Screen-Requirements.md) (its Acceptance checks are the QA list). Look: [`design/frames/`](design/frames/). Handoff files: [`design/handoff/`](design/handoff/).

## Per-ticket workflow

**Speed first (Grigor, 2026-11-07): startup style.** Build only what the ticket's acceptance criteria need; no extras, no gold-plating. Keep both reviews to a quick pass, one round unless something is actually broken, and keep PR bodies and reports short.

1. **Before writing code**, move the Notion card Status to `In progress` and make sure the GitHub issue is open and assigned, so Grigor can follow progress on the board.
2. Read the issue, its Notion card, the frames and the requirements sections it names, and `docs/DECISIONS.md`.
3. Implement on a branch. Open a PR whose body starts with `Closes #N` (or `Part of #N` while an acceptance criterion only Grigor can meet is still open), links the Notion card, and (for UI tickets) shows simulator screenshots next to the frame images.
4. Run **two separate review passes** on the PR:
   - **QA review:** correctness, edge cases, tests, build and CI pass, the ticket's acceptance criteria and Definition of done.
   - **Design review:** compare the result against the ticket's design frames and the requirements doc (layout, tokens, copy, states, light and dark).
   - **Device scope (Grigor, 2026-11-07):** test and review on **iPhone 17 Pro only**. Skip accessibility (VoiceOver, Dynamic Type, large text) and iPad layout in reviews and tests, even where an issue's Definition of done lists them (D23).
5. Fix the findings. If the first round found major issues, run one more round of both reviews. **Two rounds maximum**, then ship.
6. Comment the review outcome on the issue, then **merge the PR yourself** (squash) once the reviews are done and CI is green, and move the Notion card to `Done` (Grigor, 2026-11-07: "merge all PRs, do not wait for me"). Then continue with the next ticket in build order. Stop and tell Grigor only when you hit a blocker you cannot clear (an open "needed by" question, something only he can do, or a red CI you cannot fix).
7. Report back after each ticket: Notion card status, PR link, and the outcome of each review round.
8. **One ticket per session.** A session implements exactly one ticket. When its PR is merged, report back and stop; the next ticket starts in a new session so each one begins with a fresh context (Grigor, 2026-11-07, to save tokens). Anything the next session needs goes in this file, `docs/DECISIONS.md` or the issue, not in chat.

Notion Status values, in order: Backlog, Needs design, Design review, To do, In progress, PR review, Feature QA, Done.

## Code conventions

Set up in TT-101. Every ticket follows these; a reviewer checks them in the QA pass.

### Project

- `TrainTimes.xcodeproj`: one app target `TrainTimes`, `TrainTimesTests` (unit and snapshot, hosted in the app) and `TrainTimesUITests` (XCUITest). iOS 17 minimum, Swift 6 language mode, complete strict concurrency, warnings are errors (D1–D4).
- The project uses **Xcode 16 synchronized folders**: adding, moving or deleting a file under `Sources/`, `Resources/`, `Preview Content/` or `Tests/` needs no project edit. Do not put non-code files such as READMEs in those folders; they would be bundled (`.gitkeep`, which holds empty folders, is excluded by `EXCLUDED_SOURCE_FILE_NAMES`; delete it once a folder has files).
- To change targets, build settings or packages, edit `scripts/generate-xcodeproj.rb` and re-run it (`gem install xcodeproj`, then `ruby scripts/generate-xcodeproj.rb`; works on Linux), and commit the regenerated project. Do not hand-edit `project.pbxproj`.
- Bundle id `ca.traintimes.TrainTimes`; Display Name "Train Times" (D7).
- Info.plist keys come from `INFOPLIST_KEY_*` settings in the generator; a key with no such setting goes in `Config/Info.plist`, which Xcode merges with them (today `UIDesignRequiresCompatibility`, D25, and `MetrolinxAPIKey` from the `METROLINX_API_KEY` build setting, D36).
- Asset catalogs live in `Resources/`: `AppIcon.xcassets` (TT-103) and `Colors.xcassets` (TT-102, the 21 token colours; `Accent` is the global accent colour). Both build settings are set in `scripts/generate-xcodeproj.rb`.
- Shared components (TT-102) are in `Sources/Design`: `StatusBadge`/`TripStatus`, `ExpressTag`, `TimePill`, `.ttPrimary`/`.ttSecondary`/`.ttText` button styles, `IconButton`, `DayCell`, `DayChip`, `SegmentedControl`, `Card`, `FreshnessLine`, `Toast`, `EmptyStateCard`, `SkeletonCard`, and `TabBarStyle` (TT-104: tab bar look and tab icons). Components take times already formatted by the one formatter. Token fonts are fixed sizes (no Dynamic Type scaling, D23).
- Packages: swift-snapshot-testing (exact version, test target only). No third-party UI kits or runtime dependencies (D6).

### Folders

| Folder | Holds |
|---|---|
| `Sources/App` | `TrainTimesApp`, the root view, app-wide environment and dependency wiring. |
| `Sources/Design` | Tokens and shared components (TT-102). Screens use these only: no raw colours, fonts, spacing or radii in feature code. |
| `Sources/Core` | Domain models, repository protocols and implementations, the one time formatter (TT-106), service-day rules. No SwiftUI imports except where a type is environment glue. |
| `Sources/Features/<Feature>` | One folder per feature (`Schedule`, `TripDetails`, `Route`, `Stations`, `Alerts`, `Settings`): its views and view models. |
| `Resources/en-CA.lproj/Localizable.strings` | Every user-facing string (D19). Copy of `design/handoff/Localizable.strings`. |
| `Preview Content/Fixtures.json` | Canvas fixtures, in Debug builds and the unit test bundle; excluded from Release (D20). Copy of `design/handoff/Fixtures.json`. |
| `Tests/UnitTests`, `Tests/UITests` | Tests, mirroring the `Sources` folders. Snapshot references live in `__Snapshots__` beside each test file. |

`scripts/check-handoff-sync.sh` fails CI when a copy drifts from `design/handoff/`; change both in the same PR.

### Architecture

- **MVVM.** Views hold layout only, no business logic. Each screen has an `@Observable @MainActor final class` view model that gets its dependencies as protocols through `init` (repositories, clock, formatter), so tests inject fakes.
- **Repositories return domain types** from `Sources/Core`, never feed or JSON types. Fixture and live implementations sit behind the same protocol (D20).
- **One time formatter** (TT-106) for every time on screen, in VoiceOver and in notifications (D17); tabular digits.
- **Schedule data** (TT-130, D35): the app reads GO Transit's GTFS feed through `GTFSScheduleRepository` (`Sources/Core/Schedule/GTFS`), which also serves the station list. `GTFSFeedStore` downloads the feed on first use, imports rail only, keeps the last good import in Application Support and refreshes it weekly. `ScheduleDependencies.app()` picks it; Xcode previews, the unit test host and UI tests get the fixtures instead. Line notices are still empty (TT-132).
- **Live status** (TT-131, D36): `GTFSRealtimeStore` (`Sources/Core/Schedule/Realtime`) fetches GO's GTFS-realtime TripUpdates feed and `GTFSScheduleRepository` maps it onto the route's trips. The Metrolinx key comes from the `METROLINX_API_KEY` build setting in `Config/Secrets.xcconfig` (git-ignored, included by `Config/App.xcconfig`); never commit it. A build without the key shows the schedule only. Until the key arrives, tests replay the samples in `Tests/UnitTests/Core/Realtime` (`FeedReplay`, written by `scripts/make-realtime-samples.py`).
- **Alert server** (TT-140, D37): `server/`, a Cloudflare Worker with D1 in TypeScript, its own project outside the Xcode project. Test with `cd server && npm ci && npm test && npm run typecheck` (Node 22.18 or later, works on Linux); CI runs `.github/workflows/server.yml` when `server/`, the handoff strings or the sample feeds change. Its `notif.*` copy must match `design/handoff/Localizable.strings` word for word (a test checks). Setup, secrets and deploy: `server/README.md`.
- **Settings** (TT-105): `AppSettings` (`Sources/Core/Settings`) stores Appearance and Time format in `UserDefaults`. `RootView` applies Appearance with `preferredColorScheme` and puts `settings.timeFormatter` in the environment as `\.timeFormatter`. Screens format times with that value, never a `TimeFormatter` of their own, so a Time format change updates every time at once. A view model must not keep a formatter from `init` (a view model held in `@State` would keep the old one): the view passes `\.timeFormatter` on each formatting call, or the view model reads `settings.timeFormatter` each time. Tests pass `AppSettings(defaults: .ephemeral())` (`Tests/UnitTests/Support`), never `.standard`.
- **Strings** come from `Localizable.strings` by key (`Text("tab.schedule")`, `String(localized:)`); no literal copy in code. Keys that take values (`%@`, `%d`) are formatted, not interpolated: `String(format: String(localized: "status.delayed"), minutes)`; `Text("status.delayed \(minutes)")` looks up a key that does not exist. Times are formatted by the one formatter first and passed as `%@`.
- Swift 6 concurrency: no `@unchecked Sendable` or `nonisolated(unsafe)` without a comment saying why it is safe.

### Tests (from each issue's Definition of done)

- Unit tests for every view model and rule.
- Snapshot tests (`assertSnapshot(of:as: .image(layout: .device(config: .iPhone17Pro), traits:))`, config in `Tests/UnitTests/Support`) for every screen state the ticket touches, in light and dark. iPhone 17 Pro only; no large-text or iPad snapshots (D23). Test methods that touch views are `@MainActor`.
- Snapshots of anything inside the `TabView` or a `NavigationStack` pass `drawHierarchyInKeyWindow: true` (see `Tests/UnitTests/App/AppShellTests.swift`); the default layer render draws the bars and safe areas wrong (TT-104).
- An XCUITest flow added or updated when a user flow changes. Find elements by `accessibilityIdentifier`.
- UI tests create the app with `XCUIApplication.onFixtures()` (`Tests/UITests/LaunchArguments.swift`), so they run on the fixture schedule and clock and never download the feed. Tests that need real GO data read `Tests/UnitTests/Core/GTFS/go-gtfs-sample.zip` (the Nov 4 feed cut down to two lines and three days).
- A UI test that needs the Schedule timeline launches with `LaunchArguments.fixtureRoute` (`Tests/UITests/LaunchArguments.swift`); with no saved route the app opens on the route form (TT-120). `LaunchArguments.freshInstall` starts with no route and no favourites; `LaunchArguments.noFavourites` clears the favourites (TT-122). Unit and snapshot tests pass `Favourites(defaults: .ephemeral())` to anything that reads favourites, never `.standard`.

### Building and CI

- CI (`.github/workflows/ci.yml`) runs `scripts/ci-test.sh` on the iPhone 17 Pro simulator on the latest GitHub macOS runner on every pull request and on main. Run the same script on a Mac to test locally.
- **Snapshot references are recorded by CI**, since cloud sessions run on Linux without Xcode. Add a snapshot test without a reference and push: CI records the missing image, commits it to the PR branch as "Record reference snapshots… [skip ci]", re-runs the tests against it in the same job and posts the result as the "CI / Build and test" status on that commit, so the PR head shows green or red without a new run. Pull before pushing again, and look at the recorded PNGs in the PR diff during the design review. A changed snapshot is never re-recorded automatically: delete the old reference in the PR to have CI record the new one. References are excluded from the test bundle (`*.png` in `EXCLUDED_SOURCE_FILE_NAMES`).
- **Squash-merge with your own commit message** (the PR title and `Closes #N`): the default squash message lists the bot's `[skip ci]` commit, and GitHub would then skip CI on main.
- **Never write a skip marker in your own commit messages**, not even to describe one: `[skip ci]`, `[ci skip]`, `[no ci]`, `[skip actions]` or `[actions skip]` anywhere in the message makes GitHub create no CI run for that push, so the PR head has no check. After every push, confirm a run started.
- When the runner image moves to a new iOS version, snapshots may drift; re-record them in one PR by deleting the `__Snapshots__` folders.
