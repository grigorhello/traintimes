# Build order

The 31 Train Times v1 tickets in the order to build them. Each row links to its GitHub issue; the Notion board "TrainTimes · Product board" mirrors it (Order = build step).

M0 and M1 need no network and no API key, so start there even while Metrolinx data access is being arranged.


## M0 · Foundations

Decisions, Xcode project, design tokens and components, app icon, app shell, Settings, the one time formatter (TT-100 to TT-106). README build step 1.

| # | Ticket | Issue | Priority | Size | Blocked by |
|---|---|---|---|---|---|
| 1 | TT-100 · Record the v1 build decisions and open questions | [#1](https://github.com/grigorhello/traintimes/issues/1) | P0 | 1 | — |
| 2 | TT-101 · Set up the iOS app project | [#2](https://github.com/grigorhello/traintimes/issues/2) | P0 | 2 | TT-100 (#1) |
| 3 | TT-102 · Port the design tokens and components to SwiftUI | [#3](https://github.com/grigorhello/traintimes/issues/3) | P0 | 3 | TT-101 (#2) |
| 4 | TT-103 · App icon and brand mark | [#4](https://github.com/grigorhello/traintimes/issues/4) | P1 | 1 | TT-101 (#2) |
| 5 | TT-104 · App shell with Schedule and Alerts tabs | [#5](https://github.com/grigorhello/traintimes/issues/5) | P0 | 2 | TT-102 (#3) |
| 6 | TT-106 · One time formatter and the GO service day | [#6](https://github.com/grigorhello/traintimes/issues/6) | P0 | 2 | TT-101 (#2) |
| 7 | TT-105 · Settings: appearance, time format, data and about | [#7](https://github.com/grigorhello/traintimes/issues/7) | P1 | 2 | TT-104 (#5), TT-106 (#6) |

## M1 · Timeline Alpha

The Schedule timeline on fixtures with every state, trip details, route form, station search and favourites. No network, no key (TT-110 to TT-122). README build steps 2 and 3.

| # | Ticket | Issue | Priority | Size | Blocked by |
|---|---|---|---|---|---|
| 8 | TT-110 · Schedule data model, fixtures and repository protocol | [#8](https://github.com/grigorhello/traintimes/issues/8) | P0 | 2 | TT-106 (#6) |
| 9 | TT-111 · Timeline layout engine | [#9](https://github.com/grigorhello/traintimes/issues/9) | P0 | 5 | TT-110 (#8) |
| 10 | TT-112 · Schedule screen: route header, day strip and freshness row | [#10](https://github.com/grigorhello/traintimes/issues/10) | P0 | 3 | TT-104 (#5), TT-110 (#8) |
| 11 | TT-113 · Timeline cards, markers and the next train | [#11](https://github.com/grigorhello/traintimes/issues/11) | P0 | 5 | TT-111 (#9), TT-112 (#10) |
| 12 | TT-114 · Delayed and cancelled trains on the timeline | [#12](https://github.com/grigorhello/traintimes/issues/12) | P0 | 3 | TT-113 (#11) |
| 13 | TT-115 · Offline, stale, loading, future day and empty states | [#13](https://github.com/grigorhello/traintimes/issues/13) | P0 | 3 | TT-113 (#11) |
| 14 | TT-116 · Compact phone, large text and dark appearance | [#14](https://github.com/grigorhello/traintimes/issues/14) | P1 | 3 | TT-114 (#12), TT-115 (#13) |
| 15 | TT-118 · Trip details sheet | [#15](https://github.com/grigorhello/traintimes/issues/15) | P0 | 3 | TT-113 (#11) |
| 16 | TT-120 · Route form and first use | [#16](https://github.com/grigorhello/traintimes/issues/16) | P0 | 3 | TT-104 (#5) |
| 17 | TT-121 · Station search | [#17](https://github.com/grigorhello/traintimes/issues/17) | P0 | 2 | TT-120 (#16) |
| 18 | TT-122 · Favourites and the saved route | [#18](https://github.com/grigorhello/traintimes/issues/18) | P1 | 3 | TT-120 (#16), TT-112 (#10) |

## M2 · Live Data

GO Transit GTFS static schedule on device, GTFS-realtime live status, line notices (TT-130 to TT-132). README build steps 4 and 5.

| # | Ticket | Issue | Priority | Size | Blocked by |
|---|---|---|---|---|---|
| 19 | TT-130 · Import the GO Transit GTFS static schedule | [#19](https://github.com/grigorhello/traintimes/issues/19) | P0 | 8 | TT-110 (#8), TT-100 (#1) |
| 20 | TT-131 · Live status from GTFS-realtime trip updates | [#20](https://github.com/grigorhello/traintimes/issues/20) | P0 | 5 | TT-130 (#19) |
| 21 | TT-132 · Line notices | [#21](https://github.com/grigorhello/traintimes/issues/21) | P1 | 2 | TT-131 (#20) |

## M3 · Alerts

Alert server with APNs, one-tap bell, alert setup and permission, Alerts tab, deep links and the watched-trip strip (TT-140 to TT-144). README build step 6.

| # | Ticket | Issue | Priority | Size | Blocked by |
|---|---|---|---|---|---|
| 22 | TT-140 · Alert server: rules, device tokens and APNs | [#22](https://github.com/grigorhello/traintimes/issues/22) | P0 | 8 | TT-131 (#20) |
| 23 | TT-141 · One-tap bell and alert toast | [#23](https://github.com/grigorhello/traintimes/issues/23) | P0 | 3 | TT-140 (#22), TT-113 (#11) |
| 24 | TT-142 · Alert setup sheet and notification permission | [#24](https://github.com/grigorhello/traintimes/issues/24) | P0 | 3 | TT-140 (#22) |
| 25 | TT-143 · Alerts tab | [#25](https://github.com/grigorhello/traintimes/issues/25) | P0 | 3 | TT-142 (#24) |
| 26 | TT-144 · Notification deep links and the watched-trip strip | [#26](https://github.com/grigorhello/traintimes/issues/26) | P1 | 3 | TT-140 (#22), TT-118 (#15) |

## M4 · V1 Launch

Accessibility pass, website and required pages, App Store listing, acceptance QA and release (TT-150 to TT-154). README build step 7.

| # | Ticket | Issue | Priority | Size | Blocked by |
|---|---|---|---|---|---|
| 27 | TT-150 · VoiceOver, Dynamic Type and motion pass | [#27](https://github.com/grigorhello/traintimes/issues/27) | P0 | 3 | TT-116 (#14), TT-143 (#25) |
| 28 | TT-151 · Website traintimes.ca with privacy, data and support pages | [#28](https://github.com/grigorhello/traintimes/issues/28) | P1 | 2 | TT-100 (#1) |
| 29 | TT-152 · App Store listing and screenshots | [#29](https://github.com/grigorhello/traintimes/issues/29) | P1 | 2 | TT-150 (#27) |
| 30 | TT-153 · Acceptance QA and the three-second test | [#30](https://github.com/grigorhello/traintimes/issues/30) | P0 | 2 | TT-150 (#27), TT-144 (#26) |
| 31 | TT-154 · Ship to TestFlight and the App Store | [#31](https://github.com/grigorhello/traintimes/issues/31) | P0 | 2 | TT-152 (#29), TT-153 (#30), TT-151 (#28) |

## TestFlight feedback tickets

Changes Grigor asks for after testing a TestFlight build. Each gets a GitHub issue and a Notion card (Order after 31) for visibility, and ships in a new TestFlight build.

| Order | Ticket | Issue | Priority | Pts | From |
|---|---|---|---|---|---|
| 32 | TT-155 · Route card, Settings tab and Recent routes | [#67](https://github.com/grigorhello/traintimes/issues/67) | P1 | 3 | TestFlight 1.0 (3), D48 |
| 33 | TT-156 · Schedule refresh | [#69](https://github.com/grigorhello/traintimes/issues/69) | P1 | 8 | TestFlight 1.0 (4), D49 |
| 34 | TT-157 · Departure card redesign | [#71](https://github.com/grigorhello/traintimes/issues/71) | P1 | 5 | TestFlight 1.0 (11), D50 |
| 35 | TT-158 · Settings › Testing: mock time | [#73](https://github.com/grigorhello/traintimes/issues/73) | P1 | 3 | Grigor, 2026-11-09, D51 |
| 36 | TT-159 · Schedule opens at Now and rolls over at midnight | [#74](https://github.com/grigorhello/traintimes/issues/74) | P0 | 3 | Grigor, 2026-11-09 |
| 37 | TT-160 · Day strip shows the previous 7 days | [#75](https://github.com/grigorhello/traintimes/issues/75) | P2 | 2 | Grigor, 2026-11-09 |
| 38 | TT-161 · Inline station picker and glass route form | [#78](https://github.com/grigorhello/traintimes/issues/78) | P1 | 5 | Grigor, 2026-11-10, D54 |
| 40 | TT-163 · Trip details sheet: journey card, stop list and floating alert button | [#83](https://github.com/grigorhello/traintimes/issues/83) | P1 | 5 | Grigor, 2026-11-10, D56 |
| 42 | TT-165 · Swap button animation: the station names trade places | [#91](https://github.com/grigorhello/traintimes/issues/91) | P1 | 2 | Grigor, 2026-11-10, D59 |
| 43 | TT-166 · Bell pop, toast spring and the Enable-alerts confirmation | [#92](https://github.com/grigorhello/traintimes/issues/92) | P2 | 1 | Grigor, 2026-11-10, D60 |
| 45 | TT-168 · Settings redesign: five-row main view, glass switches, Notifications, About and Testing pages | [#85](https://github.com/grigorhello/traintimes/issues/85) | P1 | 8 | Grigor, 2026-11-10, D57 |
