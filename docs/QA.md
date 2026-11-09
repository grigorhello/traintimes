# Acceptance QA (TT-153, D46)

Every check in [`design/Screen-Requirements.md`](../design/Screen-Requirements.md) § Acceptance checks, plus the brand, the three-second test, the usability round (Q11) and the compact phone (Q9). The requirements accept the build when every check passes **on a physical iPhone in light and dark**.

Each check says what the **iPhone 17 Pro simulator and CI** already prove (unit, snapshot and UI tests, run on every PR and on main by `scripts/ci-test.sh`; the alert server's tests by `.github/workflows/server.yml`), then what to do **on the iPhone**. Grigor ticks Light and Dark once the phone shows it. Skipped under D23/D45: VoiceOver, Dynamic Type and large text, iPad.

Simulator and CI results are for main at TT-153's merge (PR #65). Status words: **passes** (tests assert the whole check), **partly** (what is not covered is named), **phone only** (needs the phone, riders, real APNs or the Metrolinx feed).

## Before you start on the iPhone

- **Build from Xcode** (until TestFlight, TT-154): open `TrainTimes.xcodeproj` on the Mac, pick your team under Signing & Capabilities (automatic signing), plug in the iPhone and press Run. This is the real app on GO's timetable.
- **Fixture runs** show the states GO's feed cannot show yet: in Xcode, Product › Scheme › Edit Scheme › Run › Arguments › Environment Variables, add `TT_FIXTURES` with one of `1` (on time, "Updated just now"), `delayed`, `cancelled`, `eveningDark` or `offline`, and Run. Remove the variable to go back to the real app. Fixture runs are on the canvas clock (Thu Nov 5, 7:21 AM; 5:03 PM for `eveningDark`).
- **No Metrolinx key yet** (D36): the real app shows On time badges for every train (D49) with no live status or line notices; Trip details says "Scheduled times only". The checks marked *needs the key* are done once the key build exists.
- **Light and dark**: Settings › Appearance (in the app) switches without leaving it.
- **Alerts** need the alert server live at alerts.traintimes.ca with its push key (thread "Deploy alert server and set up push key"). Until then a bell or "Enable alerts" ends in "Could not save", which is the right behaviour for an unreachable server.

## Design acceptance

### 1. A new rider selects From and To and sees the timeline without any permission prompt.
- Simulator and CI: **passes.** `RouteTests.testFirstUseShowsTrainsAndRelaunchOpensTheRoute` (fresh install, search, two picks, Show trains, timeline); `AlertSetupViewModelTests.testLaunchAndForegroundNeverAsk` (launch and foreground read the permission, never ask); the only call that asks is "Enable alerts" (`AlertRules.requestPermission`, D41). The first real download of GO's timetable is not exercised (UI tests run on fixtures).
- iPhone: delete the app, Run, tap From, type "oak", pick Oakville GO; the sheet turns to To by itself; pick Union Station GO, Show trains. No pop-up of any kind appears, and the timeline shows. Note how long the station list takes to fill the very first time (the app is downloading GO's timetable).
- [ ] Light
- [ ] Dark

### 2. A returning rider sees the remembered route and reads the next usable train and its status in about three seconds.
- Simulator and CI: **passes** for the behaviour: `RouteTests` and `RecentRoutesTests` relaunch onto the saved route and direction; `ScheduleViewModelTests.testTodayIsSelectedFirstWithTheRouteAndLiveFreshness` (opens on Today, D30); `TimelineCardsTests.testNextUsableTrainLeadsWithMinutesUntilDeparture`; `AppShellTests` snapshots (34 pt lead card, badge, "in 11 min"). Fixed in TT-153: coming back to the app on a new day left yesterday selected (`ScheduleViewModelTests.testANewServiceDayMovesTheScheduleToToday`). The three seconds are a phone test.
- iPhone: with a route saved, swipe the app away and open it again. Within about three seconds you can read the route and the big green next train with "in N min" and its badge. Pick another day, quit, reopen: it comes back on Today. Also leave the app in the background overnight and open it in the morning: Today, with the Now line.
- [ ] Light
- [ ] Dark

### 3. Swapping direction is explicit; full station names stay readable.
- Simulator and CI: **passes.** Swap only on tap and remembered: `RecentRoutesTests.testRecentRouteOpensFromTheRouteSheetAndSurvivesRelaunch`, `ScheduleRouteTests.testSwapIsRemembered`, `RouteFormViewModelTests.testSwapReversesTheStations`. Fixed in TT-153: the route header cut long names off after two lines; it now shrinks them to fit (`WatchedStripSnapshotTests.testLongNamesLight/Dark`, Union Station GO to Brampton Innovation District GO).
- iPhone: tap the arrows beside the route: the names flip and the trains reload; reopen the app, the direction stays. Pick Brampton Innovation District GO to Union Station GO and swap: both names read in full.
- [ ] Light
- [ ] Dark

### 4. Scheduled, live, delayed, cancelled, stale and offline states are visibly different on the timeline.
- Simulator and CI: **passes.** Snapshots light and dark: `ScheduleSnapshotTests` (today live, delayed, cancelled, another day), `ScheduleStatesSnapshotTests` (stale, offline, future day, loading), `ScheduleGTFSSnapshotTests` (real schedule); rules in `ScheduleStatesTests`. Stale, scheduled-only and live cards look the same on Schedule on purpose (D13, D33, D49); the status row tells stale from live.
- iPhone: real app: every badge On time, no status row. Then fixture runs `1`, `delayed`, `cancelled`, `offline`: each looks different (on time; amber Delayed 9 min; red struck 7:32 AM; "Offline · last updated 6:52 AM" and Platform pending). Stale needs the key.
- [ ] Light
- [ ] Dark

### 5. A delay moves the card to the expected time, draws the amber slip from the scheduled time, and keeps the 7:32 AM identity.
- Simulator and CI: **passes.** `TimelineCardsTests.testDelayedTrainSitsAtItsExpectedTimeAndKeepsItsName`, `TimelineLayoutTests.testNineMinuteDelayDrawsASixtyThreePointBar`, `ScheduleLiveTests.testPollingFollowsTheFeedAndKeepsTheScroll` (replayed delay 5 then 9 min, same train), snapshots `testDelayedLight/Dark`. A real delay needs the key.
- iPhone: fixture run `delayed`: the first card reads 7:41 AM with "Scheduled 7:32 AM", amber Delayed 9 min, a struck amber 7:32 on the rail and an amber bar down to the green 7:41 dot.
- [ ] Light
- [ ] Dark

### 6. A cancelled train keeps its slot with a red marker and is never the lead.
- Simulator and CI: **passes.** `TimelineCardsTests.testCancelledTrainIsNeverTheNext`, `testCancelledCardKeepsItsSlotAndPointsBelow`, `testCancelledTrainBetweenUsableTrains`; snapshots `testCancelledLight/Dark`, `testEveningDark`.
- iPhone: fixture run `cancelled`: 7:32 AM struck with a red x, Cancelled, "Next usable below", no bell; 7:58 AM is the big green next train.
- [ ] Light
- [ ] Dark

### 7. Cards never touch; where trains are closer than the 16 pt gap allows, only that segment zooms.
- Simulator and CI: **passes.** `TimelineLayoutTests.testTwoTrainsOneMinuteApartZoomOnlyThatSegment`, `testGridlinesFollowTheZoom`, `testTrainsAtTheSameMinuteStillGetTheGap`; `TimelineCardsTests.testMeasuredCardSizeFeedsTheLayout`.
- iPhone: real app, Union Station GO to Oakville GO on a weekday, scroll through 4 to 7 PM: always a gap between cards; the time labels on the left spread apart only where trains bunch up.
- [ ] Light
- [ ] Dark

### 8. Gaps of 20 min or more are labelled; gaps over 30 min fold with the real duration shown.
- Simulator and CI: **passes**, read with § Timeline geometry (D46): no label between cards, only a fold carries one, as the frames show. `TimelineLayoutTests.testFortyEightMinuteGapFolds`, `testFoldLabelSkipsACancelledTrain`, `testLongWaitBeforeTheFirstTrainFolds`. Fixed in TT-153: a cancelled train at the start of a gap was counted, a gap followed only by cancelled trains named a cancelled train as next, and a tall card could cover the pill (`testFoldLabelCountsFromTheLastUsableTrain`, `testFoldBeforeOnlyCancelledTrainsHasNoLabel`, `testFoldPillClearsATallCardAbove`).
- iPhone: fixture run `eveningDark`, scroll below 5:52 PM: dashed rail and "No trains for 48 min · next 6:40 PM", fully readable. Real app: a station with hourly midday service (Kitchener line) to Union: the pill gives the real gap and the right next train.
- [ ] Light
- [ ] Dark

### 9. Three departures are visible on a 390 pt phone at default text size in the normal state; two on a compact phone.
- Simulator and CI: **passes** on the iPhone 17 Pro: `ScheduleSnapshotTests.testTodayLight/Dark` show the 7:32, 7:58 and 8:21 cards whole above the tab bar at the launch position. The compact phone is Q9 (below).
- iPhone: fixture run `1`, without scrolling: three whole cards above the tab bar.
- [ ] Light
- [ ] Dark

### 10. The day strip switches days in one tap; tapping the Schedule tab again returns to the present and Today in one tap (D49).
- Simulator and CI: **passes** for one-tap day and back: `ScheduleTests.testAnotherDayThenScheduleTabReturnsToNow`, `ScheduleViewModelTests.testReTappingTheScheduleTabReturnsToTodayAndNow`, `testBackToNowScrollsToThePresentOnToday`, `testScrollSettlesOnceEveryCardIsMeasured`; the day strip covers the feed's calendar (`ScheduleHorizonTests`). **Partly** for Now after scrolling on Today: the model asks for the scroll, but no UI test scrolls away first.
- iPhone: tap a later day: it switches at once and "Today" turns green; tap the Schedule tab again: back to Today with the Now line near the top. On Today, scroll well down and tap the Schedule tab once: it scrolls back to the Now line. Open the app cold: it is already scrolled to Now.
- [ ] Light
- [ ] Dark

### 11. Enabling, repeating, pausing and deleting alerts is understandable without instructions.
- Simulator and CI: **passes** for the flows: `AlertSetupTests.testEnableAsksPermissionThenOn`, `AlertBellTests.testBellArmsThenTurnsOffTheAlert`, `AlertsTabTests.testPauseDeleteAndUndo`, `testAddAlertShowsTheBellHintOnSchedule`; `AlertSetupViewModelTests` (Repeat days, This trip and Repeat as separate rules), `AlertsViewModelTests` (pause, delete, undo), snapshots light and dark. Fixed in TT-153: deleting your only alert with no connection was never sent to the server, so it kept notifying (`AlertRulesTests.testRefreshSendsAMissedDeleteWhenNoRuleIsLeft`). Whether it is understandable needs people: the usability round below.
- iPhone (server live): tap a bell, then Repeat on its message, pick days, Enable alerts, close. Alerts tab: flip a switch off (Paused) and on, swipe a row left and Delete, then Undo. Each step makes sense without help.
- [ ] Light
- [ ] Dark

### 12. A denied notification permission never looks like an active alert.
- Simulator and CI: **passes.** `AlertSetupTests.testDeniedShowsNotificationsOff`, `AlertRulesTests.testNotificationsOffIsNeverOnButTheRuleIsStillSaved`, `AlertSetupViewModelTests.testDeniedPermissionShowsNotificationsOffNeverOn`, `AlertBellModelTests.testWithoutPermissionTheTapOpensTheSetupSheet`, snapshots `testNotificationsOffLight/Dark` (sheet and Alerts tab). Turning permission off after an alert is On, in iOS Settings, is a phone check (the app reads it again on every return to the foreground).
- iPhone: fresh install, tap a bell, Enable alerts, Don't Allow: the sheet shows the red "Notifications off" box with Open Settings, never On. With an alert On, turn Train Times notifications off in iOS Settings and come back: the bell is an outline and the row reads "Notifications off · Open Settings"; turn them on again: On, with nothing to redo.
- [ ] Light
- [ ] Dark

### 13. Long names, dark appearance and accessibility text sizes do not clip critical information.
- Simulator and CI: **passes** for dark (every screen has dark snapshots) and long names in the route form, station search, Trip details and the Alerts tab, which wrap. Fixed in TT-153: the Schedule route header and the watched-trip strip cut long names off (`WatchedStripSnapshotTests.testLongNamesLight/Dark`). Accessibility text sizes are skipped (D45).
- iPhone: Brampton Innovation District GO to Union Station GO, and Union Station GO to Durham College Oshawa GO: the Schedule route card, Recent, station search, Trip details and an alert row read in full.
- [ ] Light
- [ ] Dark

### 14. The next usable train shows minutes until departure, updating each minute; no other card shows a relative time.
- Simulator and CI: **passes.** `TimelineCardsTests.testNextUsableTrainLeadsWithMinutesUntilDeparture` (only the lead has "in N min"), `testMinuteTickMovesNowAndCountsDown`, `testNextTrainMovesOnOnceItsTimePasses`.
- iPhone: real app, Today: keep the screen on two minutes; "in N min" drops by one each minute, no other card shows "in"; near departure "Departing", then the next train leads.
- [ ] Light
- [ ] Dark

### 15. Once permission exists, one bell tap arms an alert and a toast confirms it; a cancelled train has no bell.
- Simulator and CI: **passes.** `AlertBellTests.testBellArmsThenTurnsOffTheAlert`, `testBellWithoutPermissionOpensAlertSetup`; `AlertBellModelTests.testTapArmsAThisTripAlertThenTurnsItOff`, `testRepeatedTapsSendOneRequest`, `testAnUnreachableServerSaysCouldNotSaveAndTheBellStaysOff`; snapshots `AlertBellSnapshotTests.testAlertOnLight/Dark` and `ScheduleSnapshotTests.testCancelledLight/Dark` (no bell on the cancelled card). Fixed in TT-153: with no connection to Apple's push service the first save could stay on Setting up; it now ends in Could not save after 10 s.
- iPhone (server live, notifications allowed): tap a bell once: Setting up, then "Alert on for the … train · Repeat", the bell fills, a light tap. Tap again: Alert off. In Airplane mode a bell tap ends in "Could not save" with Try again and the bell stays an outline. The cancelled card's missing bell is in fixture run `cancelled`.
- [ ] Light
- [ ] Dark

### 16. First use shows empty fields and a disabled Show trains button; picking From opens To.
- Simulator and CI: **passes.** `RouteTests.testFirstUseShowsTrainsAndRelaunchOpensTheRoute`, `RouteFormViewModelTests.testFirstUseTakesTwoPicksAndOneTap`, `testUnionIsSuggestedFirstWhenChoosingTo`, snapshots `RouteFormSnapshotTests.testFirstUseLight/Dark`.
- iPhone: fresh install: the rows read "Choose starting station" and "Choose destination" in grey, Show trains grey and inert; pick From: the sheet turns to To with Union Station GO first.
- [ ] Light
- [ ] Dark

## Development release checks

### 17. Direct stopping patterns, express services, holidays, DST and after-midnight service dates validated against real schedules.
- Simulator and CI: **partly.** Against GO's real Nov 4 feed (`Tests/UnitTests/Core/GTFS/go-gtfs-sample.zip`): `GTFSTimetableTests.testDirectTrainsOnAWeekday`, `testStopsOfOneTrain`, `testExpressFollowsTheStoppingPattern`, `testSundayHasItsOwnTimetable`, `testAfterMidnightTrainsStayOnTheirServiceDay`. Holidays and DST are tested on hand-written feeds only (`GTFSFeedTests.testHolidayFollowsCalendarDates`, `testDSTDays`, `ServiceDayTests`, `TimeFormatterTests`): the feed GO publishes now (to Nov 27) holds no holiday and no clock change.
- iPhone: compare tomorrow's trains and Express tags for your usual pair with GO's online schedule; on a later day, trains after midnight come last. From about Dec 11, check Fri Dec 25 against GO's holiday schedule; from about Feb 28, check Sun Mar 14, 2027 (clocks go forward) against GO's times.
- [ ] Stopping patterns, express, after midnight
- [ ] Holiday (Dec 25)
- [ ] DST (Mar 14, 2027)

### 18. A delayed train remains visible past its scheduled departure until an actual or reliable estimated departure is resolved.
- Simulator and CI: **passes** on sample feeds: `TimelineCardsTests.testDelayedTrainStaysTheLeadPastItsScheduledTime`, `GTFSRealtimeReplayTests.testDelayIncreaseAndRecovery`. *Needs the key* on the phone.
- iPhone (key build): on a morning with a delay, keep Schedule open past the scheduled time: the card stays at the expected time and stays the lead until then.
- [ ] Checked with the key

### 19. Missing live data cannot produce an On time badge; cached data cannot appear freshly live.
- Simulator and CI: **passes** on sample feeds: `ScheduleStatesTests.testOnlyFreshLiveDataShowsOnTime`, `testStaleFallsBackToScheduledTimes`, `testOfflineKeepsTheCachedScheduleUsable`; `GTFSRealtimeReplayTests.testStaleFeedIsNeverLive`, `testOfflineKeepsTheLastFeedAsOffline`; `ScheduleLiveTests.testDataLeftOnScreenAgesBeforeTheFetch`.
- iPhone: today's build: every badge reads On time (D49), with no status row; Trip details says "Scheduled times only". Key build: Airplane mode with Schedule open shows "Offline · last updated …" within 30 s; leave the app over 3 min and reopen: "Last reported …", never "Updated just now".
- [ ] Without the key
- [ ] With the key

### 20. Timeline positions are computed from expected time, scale and the minimum-gap rule, and recomputed on every refresh without resetting scroll.
- Simulator and CI: **passes** for the layout and identity: `TimelineLayoutTests` (expected time, scale, minimum gap, `testLayoutIsDeterministicAndKeyedByTrip`), `ScheduleViewModelTests.testRefreshKeepsCardIdentityAndScrollPosition`, `ScheduleLiveTests.testPollingFollowsTheFeedAndKeepsTheScroll` (a poll never scrolls). The on-screen scroll position through a refresh is a phone check; Q10 waits for the key.
- iPhone: scroll so a train is mid-screen and wait two minutes: no jump back to Now, the Now line creeps down. Pull to refresh: no jump.
- [ ] Light
- [ ] Dark

### 21. Real APNs delivery exercised on a physical device while backgrounded and locked; disabled permission, expired token and registration failure tested separately.
- Simulator and CI: **partly**, everything short of Apple. Server (`apns.test.ts`, `replay.test.ts`, `api.test.ts`): the signed provider token, sandbox and production hosts, topic, expiry and payload; an expired token (410) removes the installation and its rules; a bad token is cleared until the app registers again; throttling and outages are retried. App: notifications off never shows On (`AlertRulesTests.testNotificationsOffIsNeverOnButTheRuleIsStillSaved`); an unknown installation registers again (`testAnUnknownInstallationRegistersAgain`). Fixed in TT-153: the app sent its push token only with a save, so after a new token (a restored backup, or a TestFlight build installed over an Xcode one) or after the server dropped the installation, alerts read On while nothing could arrive. It now sends the token and Time format on each launch and return to the foreground, and saves its rules again when the server no longer knows it (`testRefreshAfterTheServerDroppedTheInstallationRegistersAndSavesAgain`, `testRefreshSendsANewTimeFormat`). Real delivery needs the phone.
- iPhone (server live with its push key; Debug build from Xcode or TestFlight, never Release from Xcode): allow notifications and set an alert. Until the Metrolinx key, the only push the server can send is "Your usual train has changed" for a Repeat rule (D38): on a weekend day pick a weekend-only train, Alert me › Repeat Mon to Fri › Enable alerts; on the next weekday, in the hour before that time, lock the phone with the app in the background: the notification shows on the lock screen. Then separately: notifications off in iOS Settings (reads Notifications off); Airplane mode and tap a bell (Could not save); delete and reinstall the app (no old alerts come back, nothing more arrives for them).
- [ ] Delivered while backgrounded and locked
- [ ] Notifications off, reinstall (expired token) and no connection (registration failure) each behave

### 22. Feed replays verify one initial alert, meaningful updates, recovery, cancellation, expiry and no duplicates.
- Simulator and CI: **passes** on sample feeds: server `replay.test.ts` (initial delay, no update under 5 min, cancellation, recovery, skipped stop, no duplicates, wobbling delays, coalescing within 60 s, expiry, a reliable departure ends alerts, stale data sends nothing, overlapping cycles, This trip and Repeat for one train send one message, deleted or paused rules stop), `realtime.test.ts`. 49 server tests pass. The real feed waits for the key.
- iPhone (key build): tap the bell on a train already Delayed: one notification, and another only if the delay moves 5 min or more, the train is cancelled or it is back on time.
- [ ] Checked with the key

### 23. A repeating rule is set to Review needed when its usual train moves or disappears; tapping a notification opens the correct service date.
- Simulator and CI: **passes** for the rules and the tap: server `timetable.test.ts` ("a changed train sets Review needed and sends one notification", moved or removed trains, exceptions); `AlertRulesTests.testRefreshReadsReviewNeededFromTheServerAndBackToOnOnceCleared`; `AlertsViewModelTests` and `AlertsSnapshotTests.testRuleStatesLight/Dark` (amber Review needed); `DeepLinkTests.testNotificationOpensTheTripFromAColdStart` (opens Trip details on Thu, Nov 5), `testPastServiceDateOpensAlerts`; `NotificationLinkTests`. A real notification tap and a real timetable change are phone checks.
- iPhone (server live): with an alert set, lock the phone; when a notification comes, tap it: Trip details opens on that train and date; closing shows its route. If "Your usual train has changed" comes, tapping it opens the Alerts tab with an amber Review needed row.
- [ ] Notification tap opens the right train and date
- [ ] Review needed seen

### 24. VoiceOver reads each card as one element and each bell as a separate button; Dynamic Type xxxLarge and AX3 reflow without truncating a time.
- **Skipped** under D23 (D45). Nothing to do.

## Brand (§ Brand: Train Times)

- Simulator and CI: **passes** in the bundle: `ResourcesTests.testDisplayNameIsTrainTimes`, `testCopyHasNoExclamationMarks`; `BrandAssetsTests` (icon compiled, symbol is a template); `LaunchTests` (title "Train Times"); `SettingsSnapshotTests` (About). The asset catalogs hold no GO or Metrolinx mark; GO and Metrolinx appear only as words (D10).
- Known: About reads **Version 0.1.0 (1)** until TT-154 sets the version to 1.0.
- iPhone: home screen label "Train Times" in full under the green icon with a white train head and no letters; long-press the home screen › Edit › Customize › Dark and Tinted: mint train on dark, white train. In the app, top left plain "Train Times"; Settings › About: icon, name, version line. No GO or Metrolinx logo anywhere.
- [ ] Light
- [ ] Dark and tinted icons

## Compact phone (Q9)

Two full departures plus the next time are accepted on 667 pt screens. The compact layout was not built (D34), so this is the iPhone 17 Pro layout on a smaller screen.

- iPhone SE (any generation, 667 pt): fixture run `1`, no scrolling: at least two whole cards, and note whether the third train's time shows. Check that a card's bell is not squeezed.
- [ ] Two full departures (and the next time: yes / no)

## Three-second test (§ Brand)

Five GO riders. Show the home-screen icon and the app's first screen (Schedule on a real route) for three seconds, then ask "What does this app do?". Pass when four of five say GO train times or delays. If it fails, change the first App Store screenshot caption first, not the mark.

| Rider | Answer | GO train times or delays? |
|---|---|---|
| 1 | | |
| 2 | | |
| 3 | | |
| 4 | | |
| 5 | | |

- [ ] Passed (4 of 5)

## Usability round (Q11)

With the same or other riders, before the public release:

1. **Next train.** Open Schedule on their usual route and ask "When is your next train?". Time from the screen appearing to the answer (the requirements compare the timeline, three cards visible, with the earlier row list, four to five visible; target about three seconds).
2. **Bell or sheet.** Ask them to get an alert for the next train. Note whether they tap the bell on the card (one tap) or open the train and use "Alert me" (the sheet), and how long it takes.

| Rider | Next train (seconds) | Alert: bell or sheet, seconds | Notes |
|---|---|---|---|
| 1 | | | |
| 2 | | | |
| 3 | | | |
| 4 | | | |
| 5 | | | |

- [ ] Done; findings noted (closes Q11)

## TT-156 · Schedule refresh (D49)

Checks for the Liquid Glass look and the Schedule changes of TestFlight 1.0 (5). Simulator and CI: `ScheduleViewModelTests`, `TimelineCardsTests`, `TimelineLayoutTests`, `ScheduleStatesTests`, `ScheduleHorizonTests`, `DemoScheduleRepositoryTests`, `SettingsViewModelTests`, `AppSettingsTests`, the Schedule, Settings and shell snapshots, and the UI tests `LaunchTests`, `ScheduleTests`, `NoTrainsTests` and `SettingsTests.testDemoTrainsOfflineShowsTheOfflineRow`.

- iPhone, iOS 26, light and dark: the glass tab bar floats with icons only and the timeline scrolls under it; the swap button is glass; sheets look right.
- The line tile and name use the GO colour (Lakeshore West is the wine red); a line with a notice shows the amber Notice chip, which opens the notice sheet.
- No train times in the left column; a time every 15 min; the Now line sits 5 min below the top when the app opens.
- Cards read "Arrival", a green "On time" badge (grey "Scheduled" only offline) and a bigger bell that is easy to hit.
- Settings › Testing › Demo trains (TestFlight): Delays shows a late train, a cancelled train and the Notice chip; Offline shows the Offline row; Off restores live data.
