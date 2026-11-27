import XCTest
@testable import TrainTimes

/// The Alerts tab as cards (TT-253, D129): each alert's next train as Schedule's card under its route, the days row, the
/// bell switching it off and on in place, See trains, the empty tab's next trains, notifications off and the tab dot.
@MainActor
final class AlertsViewModelTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)
    private let thursday = ServiceDay(year: 2026, month: 11, day: 5)

    override func tearDown() async throws {
        Analytics.tracker = nil
        try await super.tearDown()
    }

    // MARK: Cards

    func testCardsSitUnderTheirRouteInTimeOrder() async {
        let rules = await AlertsFixtures.rules(
            FakeAlertServer(), on: [AlertsFixtures.evening, AlertsFixtures.today, AlertsFixtures.morning],
            reviewNeeded: [AlertsFixtures.burlington]
        )
        let model = await AlertsFixtures.model(rules)

        let sections = model.sections(formatter)
        XCTAssertEqual(sections.map(\.id), ["OA>UN", "BU>UN", "UN>OA"])
        XCTAssertEqual(sections.map(\.from), ["Oakville", "Burlington", "Union"])
        XCTAssertEqual(sections.map(\.to), ["Union", "Union", "Oakville"])
        XCTAssertEqual(sections.first?.line?.id, "LW")
        XCTAssertEqual(sections.map { $0.cards.map(\.id) }, [["morning", "today"], ["burlington"], ["evening"]])
        XCTAssertEqual(sections.first?.cards.first?.testID, "alerts.rule.LW-0732-20261105")
        XCTAssertFalse(model.isEmpty)
        XCTAssertTrue(model.hasLoaded)
    }

    func testTodaysTrainCountsDownOnceItsPlatformIsPosted() async {
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [AlertsFixtures.morning, AlertsFixtures.today])
        let model = await AlertsFixtures.model(rules, repository: AlertsFixtures.trains(live: ["OA>UN": AlertsFixtures.live()]))

        let morning = card(model, "morning")
        XCTAssertEqual(morning?.time, "7:32 AM")
        XCTAssertEqual(morning?.relativeTime, "in 11 min")
        XCTAssertNil(morning?.dayWord)
        XCTAssertEqual(morning?.status, .onTime)
        XCTAssertEqual(morning?.platformValue, "2")
        XCTAssertEqual(morning?.isNext, false, "no card on the tab is the lead")
        let today = card(model, "today")
        XCTAssertNil(today?.relativeTime, "an hour out, but no platform yet (D125)")
        XCTAssertEqual(today?.dayWord, "Today")
        XCTAssertEqual(today?.isExpress, true)
    }

    func testTheCountdownStartsAnHourBefore() {
        let trip = AlertsFixtures.train("LW-0850", "08:50", platform: "3")
        let departure = Departure(trip: trip, status: .scheduled, expectedDeparture: nil, expectedArrival: nil)
        let at750 = AlertsFixtures.now.addingTimeInterval(29 * 60)

        XCTAssertNil(AlertsViewModel.countdown(departure, hasPlatform: true, now: AlertsFixtures.now, formatter: formatter), "89 min out")
        XCTAssertEqual(AlertsViewModel.countdown(departure, hasPlatform: true, now: at750, formatter: formatter), "in 1 h", "an hour out reads in hours (D123)")
        XCTAssertNil(AlertsViewModel.countdown(departure, hasPlatform: false, now: at750, formatter: formatter))
    }

    func testTheDayWordSaysWhenTheTrainRuns() {
        XCTAssertEqual(AlertsViewModel.dayWord(thursday, today: thursday, isOneDay: false), "Today")
        XCTAssertEqual(AlertsViewModel.dayWord(thursday.adding(days: 1), today: thursday, isOneDay: false), "Tomorrow")
        XCTAssertEqual(AlertsViewModel.dayWord(thursday.adding(days: 4), today: thursday, isOneDay: false), "Monday")
        XCTAssertEqual(AlertsViewModel.dayWord(thursday.adding(days: 6), today: thursday, isOneDay: true), "Wednesday")
        XCTAssertEqual(AlertsViewModel.dayWord(thursday.adding(days: 8), today: thursday, isOneDay: true), "Fri 13")
    }

    func testTheDaysRowWords() {
        XCTAssertEqual(AlertDays.cardWords(of: [1, 2, 3, 4, 5]), "Mon to Fri")
        XCTAssertEqual(AlertDays.cardWords(of: [1, 2, 3, 4]), "Mon to Thu")
        XCTAssertEqual(AlertDays.cardWords(of: Array(1...7)), "Every day")
        XCTAssertEqual(AlertDays.cardWords(of: [5]), "Every Fri")
        XCTAssertEqual(AlertDays.cardWords(of: [6, 7]), "Sat and Sun")
        XCTAssertEqual(AlertDays.cardWords(of: [1, 3, 5]), "Mon, Wed, Fri")
        XCTAssertEqual(AlertDays.cardWords(of: [1, 2, 4, 5]), "4 days")
        XCTAssertEqual(AlertDays.cardWords(of: [1, 2, 3, 4, 6, 7]), "6 days")
        XCTAssertNil(AlertDays.cardWords(of: []))
    }

    func testTheDaysRowShowsItsDaysOnceOrOff() async {
        let rules = await AlertsFixtures.rules(
            FakeAlertServer(), on: [AlertsFixtures.morning, AlertsFixtures.today, AlertsFixtures.evening]
        )
        let model = await AlertsFixtures.model(rules)

        XCTAssertEqual(item(model, "morning")?.words, "Mon to Fri")
        XCTAssertEqual(item(model, "morning")?.dots, [.on, .on, .on, .on, .on, .off, .off])
        XCTAssertEqual(item(model, "morning")?.bell, .on)
        XCTAssertEqual(item(model, "today")?.words, "Once")
        XCTAssertEqual(item(model, "today")?.dots, [.off, .off, .off, .ring, .off, .off, .off], "its own day, Thursday")
        XCTAssertEqual(item(model, "evening")?.words, "Off")
        XCTAssertEqual(item(model, "evening")?.dots, [.on, .on, .on, .on, .off, .off, .off])
        XCTAssertEqual(item(model, "evening")?.greysDays, true)
        XCTAssertEqual(item(model, "evening")?.bell, .off)
        XCTAssertEqual(card(model, "evening")?.isQuiet, true, "the time in grey")
        XCTAssertEqual(card(model, "evening")?.dayWord, "Today")
        XCTAssertEqual(card(model, "morning")?.isQuiet, false)
    }

    func testATrainThatHasLeftHandsOverToTheNextDayTheAlertRings() async {
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [AlertsFixtures.morning])

        let thursday8 = await AlertsFixtures.model(rules, clock: FixedClock(now: AlertsFixtures.now.addingTimeInterval(39 * 60)))
        XCTAssertEqual(card(thursday8, "morning")?.dayWord, "Tomorrow")
        XCTAssertNil(card(thursday8, "morning")?.relativeTime)
        XCTAssertEqual(thursday8.trip("morning")?.key.tripId, "LW-0732-20261106")

        let friday8 = await AlertsFixtures.model(rules, clock: FixedClock(now: AlertsFixtures.now.addingTimeInterval(86_400 + 39 * 60)))
        XCTAssertEqual(card(friday8, "morning")?.dayWord, "Monday", "Mon to Fri skips the weekend")
        XCTAssertEqual(friday8.trip("morning")?.key.tripId, "LW-0732-20261109")
    }

    func testALateTrainStaysPastItsTime() async {
        let at735 = AlertsFixtures.now.addingTimeInterval(14 * 60)
        let live = AlertsFixtures.live(delays: ["LW-0732": 9], at: at735)
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [AlertsFixtures.morning])
        let model = await AlertsFixtures.model(
            rules, repository: AlertsFixtures.trains(live: ["OA>UN": live]), clock: FixedClock(now: at735)
        )

        XCTAssertEqual(card(model, "morning")?.time, "7:41 AM")
        XCTAssertEqual(card(model, "morning")?.status, .delayed(minutes: 9))
        XCTAssertEqual(card(model, "morning")?.relativeTime, "in 6 min")
        XCTAssertEqual(model.trip("morning")?.key.tripId, "LW-0732-20261105")
    }

    func testAOneDayAlertLeavesTheTabOnceItsTrainHasLeft() async {
        let clock = TestClock(now: AlertsFixtures.now)
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [AlertsFixtures.today])
        let model = await AlertsFixtures.model(rules, clock: clock)
        XCTAssertEqual(ids(model), ["today"])

        clock.advance(minutes: 61)
        await model.load()
        XCTAssertTrue(model.isEmpty)
        XCTAssertEqual(rules.rules.map(\.id), ["today"], "hidden, not deleted")
    }

    func testALateOneDayAlertStaysUntilItsTrainLeaves() async {
        let at822 = AlertsFixtures.now.addingTimeInterval(61 * 60)
        let live = AlertsFixtures.live(delays: ["LW-0821": 5], at: at822)
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [AlertsFixtures.today])
        let model = await AlertsFixtures.model(
            rules, repository: AlertsFixtures.trains(live: ["OA>UN": live]), clock: FixedClock(now: at822)
        )

        XCTAssertEqual(ids(model), ["today"])
        XCTAssertEqual(card(model, "today")?.time, "8:26 AM")
    }

    func testOneDayAlertsWhoseTrainHasLeftAreNotListedBeforeTheFirstLoad() async {
        let yesterday = AlertRule(
            kind: .thisTrip, trip: AlertFixtures.trip("LW-0732-20261104", day: 4), route: AlertsFixtures.oakvilleToUnion
        )
        let left = AlertRule(
            kind: .thisTrip, trip: AlertFixtures.trip("LW-0700-20261105", departure: "12:00"), route: AlertsFixtures.oakvilleToUnion
        )
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [yesterday, left])
        let model = await AlertsFixtures.model(rules, loads: false)

        XCTAssertTrue(model.isEmpty)
    }

    func testCardsDrawnFromTheAlertAlone() async {
        // Its own usual train: a second alert for the 7:32 AM would be saved over "morning" (`AlertRules.save`).
        let sunday = AlertRule(
            id: "sunday", kind: .repeating, trip: AlertsFixtures.train("LW-0850", "08:50"), route: AlertsFixtures.oakvilleToUnion,
            weekdays: [7]
        )
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [AlertsFixtures.morning, sunday])

        let pending = await AlertsFixtures.model(rules, loads: false)
        XCTAssertFalse(pending.hasLoaded)
        XCTAssertTrue(isPending(item(pending, "morning")))
        XCTAssertEqual(item(pending, "morning")?.time, "7:32 AM")
        XCTAssertNil(pending.trip("morning"), "nothing to open yet")

        let failed = await AlertsFixtures.model(rules, repository: AlertsFixtures.trains(failing: true))
        XCTAssertTrue(isPending(item(failed, "morning")), "no timetable: the skeleton rows stay")

        let loaded = await AlertsFixtures.model(rules)
        guard case .noTrain? = item(loaded, "sunday")?.body else { return XCTFail("no Sunday trains in the next week") }
        XCTAssertEqual(item(loaded, "sunday")?.words, "Every Sun")
        XCTAssertEqual(item(loaded, "sunday")?.bell, .on)
    }

    func testATimeChangedCardHasNoBellAndGreyDays() async {
        let rules = await AlertsFixtures.rules(FakeAlertServer(), reviewNeeded: [AlertsFixtures.burlington])
        let model = await AlertsFixtures.model(rules)

        let changed = item(model, "burlington")
        guard case .changed? = changed?.body else { return XCTFail("the card says Time changed") }
        XCTAssertNil(changed?.bell)
        XCTAssertNil(changed?.words)
        XCTAssertEqual(changed?.greysDays, true)
        XCTAssertEqual(changed?.time, "8:05 AM")
        XCTAssertNil(model.tapBell("burlington"))
    }

    func testOfflineCardsReadScheduledWithALineUnderTheTitle() async {
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [AlertsFixtures.morning])
        let model = await AlertsFixtures.model(
            rules, repository: AlertsFixtures.trains(live: ["OA>UN": AlertsFixtures.live(delays: ["LW-0732": 9], offline: true)])
        )

        XCTAssertEqual(model.offlineLine(formatter), "Offline · last updated 6:52 AM")
        XCTAssertEqual(card(model, "morning")?.status, .scheduled)
        XCTAssertEqual(card(model, "morning")?.time, "7:32 AM")
        XCTAssertNil(card(model, "morning")?.relativeTime, "offline, the platform reads pending")

        let online = await AlertsFixtures.model(rules)
        XCTAssertNil(online.offlineLine(formatter))

        let never = await AlertsFixtures.model(
            rules, repository: AlertsFixtures.trains(live: ["OA>UN": LiveSnapshot(updatedAt: nil, isOffline: true)])
        )
        XCTAssertEqual(never.offlineLine(formatter), "Offline · showing saved schedule", "offline since launch")
    }

    // MARK: The bell

    func testTheBellSwitchesTheAlertOffInPlaceAndOnAgain() async {
        let server = FakeAlertServer()
        let haptics = FakeHaptics()
        let rules = await AlertsFixtures.rules(server, on: [AlertsFixtures.morning, AlertsFixtures.today])
        let model = await AlertsFixtures.model(rules, haptics: haptics)

        let off = model.tapBell("morning")
        XCTAssertEqual(item(model, "morning")?.bell, .off, "the new face at once")
        await off?.value
        XCTAssertEqual(ids(model), ["morning", "today"], "the card stays where it is")
        XCTAssertEqual(item(model, "morning")?.words, "Off")
        XCTAssertEqual(card(model, "morning")?.isQuiet, true)
        var saved = await server.saved
        XCTAssertEqual(saved.last?.id, "morning")
        XCTAssertEqual(saved.last?.paused, true)
        XCTAssertEqual(haptics.played, [.tap])
        XCTAssertNil(model.capsule, "no capsule for a bell on the tab")

        await model.tapBell("morning")?.value
        XCTAssertEqual(item(model, "morning")?.bell, .on)
        XCTAssertEqual(item(model, "morning")?.words, "Mon to Fri")
        saved = await server.saved
        XCTAssertEqual(saved.last?.paused, false)
        XCTAssertEqual(haptics.played, [.tap, .railJoint])
        XCTAssertEqual(rules.rules.count, 2, "the same alert, the same id")
    }

    func testTurningOnAsksThePermissionRuleFirst() async {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(server, on: [AlertsFixtures.evening])
        let asked = PermissionRecorder()
        let model = await AlertsFixtures.model(rules, mayAlert: { trip, _ in
            asked.trains.append(trip.key.tripId)
            return false
        })
        let before = await server.saved.count

        await model.tapBell("evening")?.value
        XCTAssertEqual(asked.trains, ["LW-1710-20261105"])
        XCTAssertEqual(item(model, "evening")?.bell, .off, "refused: nothing saved")
        let after = await server.saved.count
        XCTAssertEqual(after, before)
    }

    func testABellTheServerCannotTakeGoesBackAndOffersTryAgain() async {
        let server = FakeAlertServer()
        let haptics = FakeHaptics()
        let rules = await AlertsFixtures.rules(server, on: [AlertsFixtures.morning])
        let model = await AlertsFixtures.model(rules, haptics: haptics)

        await server.setFailing(true)
        await model.tapBell("morning")?.value
        XCTAssertEqual(item(model, "morning")?.bell, .on, "back to what was saved")
        XCTAssertEqual(model.capsule?.kind, .failed(.turnOff))
        XCTAssertEqual(haptics.played, [.fail])

        await server.setFailing(false)
        await model.tryAgain()
        XCTAssertEqual(item(model, "morning")?.bell, .off)
        XCTAssertNil(model.capsule)
        XCTAssertEqual(haptics.played.last, .tap)
    }

    func testWithNotificationsOffABellNudgesTheCard() async {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(server, permission: .off, on: [AlertsFixtures.morning])
        let model = await AlertsFixtures.model(rules)
        let before = await server.saved.count

        XCTAssertEqual(item(model, "morning")?.bell, .crossed)
        XCTAssertNil(model.tapBell("morning"))
        XCTAssertEqual(model.nudges, 1)
        let after = await server.saved.count
        XCTAssertEqual(after, before)
    }

    // MARK: Opening

    func testSeeTrainsOpensTheAlertsRouteOnItsTrainsDay() async {
        let analytics = RecordingAnalytics.install()
        let haptics = FakeHaptics()
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [AlertsFixtures.morning, AlertsFixtures.evening])
        let model = await AlertsFixtures.model(rules, nextTrains: AlertsFixtures.nextTrains, haptics: haptics)

        XCTAssertEqual(
            model.seeTrains("morning"),
            AlertsViewModel.Jump(key: TripKey(serviceDay: thursday, tripId: "LW-0732-20261105"), originId: "OA", destinationId: "UN")
        )
        XCTAssertEqual(haptics.played, [.tick])
        XCTAssertEqual(analytics.events.last, AnalyticsEvent.alertShownInSchedule(isToday: true, routeChanged: false, isOn: true))

        let evening = model.seeTrains("evening")
        XCTAssertEqual(evening?.originId, "UN")
        XCTAssertEqual(evening?.destinationId, "OA")
        XCTAssertEqual(analytics.events.last, AnalyticsEvent.alertShownInSchedule(isToday: true, routeChanged: true, isOn: false))
        XCTAssertEqual(analytics.names, ["alert_shown_in_schedule", "alert_shown_in_schedule"])
    }

    func testSeeTrainsOpensTheNextDayOnceTodaysTrainHasLeft() async {
        let analytics = RecordingAnalytics.install()
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [AlertsFixtures.morning])
        let model = await AlertsFixtures.model(rules, clock: FixedClock(now: AlertsFixtures.now.addingTimeInterval(39 * 60)))

        XCTAssertEqual(model.seeTrains("morning")?.key.serviceDay, thursday.adding(days: 1))
        XCTAssertEqual(analytics.events.last?.properties["is_today"], .bool(false))
        XCTAssertEqual(analytics.events.last?.properties["route_changed"], .bool(true), "no route on Schedule")
    }

    // MARK: Empty

    func testTheEmptyTabOffersTheNextThreeTrainsAsCards() async {
        let model = await AlertsFixtures.model(AlertFixtures.rules(FakeAlertServer()), nextTrains: AlertsFixtures.nextTrains)

        XCTAssertTrue(model.isEmpty)
        XCTAssertTrue(model.showsSuggestions)
        let next = model.suggestions(formatter)
        XCTAssertEqual(next?.route.from.id, "OA")
        XCTAssertEqual(next?.trains.map(\.card.time), ["7:32 AM", "7:58 AM", "8:21 AM"])
        XCTAssertEqual(next?.trains.map(\.card.relativeTime), ["in 11 min", nil, nil])
        XCTAssertEqual(next?.trains.compactMap(\.alert).count, 0)
    }

    func testWithNoRouteTheEmptyTabHasNoTrains() async {
        let model = await AlertsFixtures.model(AlertFixtures.rules(FakeAlertServer()))
        XCTAssertNil(model.suggestions(formatter))
    }

    func testABellOnASuggestionKeepsTheTrainsUpUntilTheRiderLeaves() async throws {
        let rules = AlertFixtures.rules(FakeAlertServer())
        let next = AlertsFixtures.nextTrains
        let model = await AlertsFixtures.model(rules, nextTrains: next, loads: false)
        let running = Task { await model.run() }
        let loaded = await poll { model.hasLoaded }
        XCTAssertTrue(loaded)

        let trip = next.nextTrains?.departures.first { $0.trip.key.tripId == "LW-0732-20261105" }?.trip
        await rules.save(AlertRule(kind: .thisTrip, trip: try XCTUnwrap(trip), route: AlertsFixtures.oakvilleToUnion))
        XCTAssertFalse(model.isEmpty)
        XCTAssertTrue(model.showsSuggestions, "the cards stay, the tapped one grows its days row")
        XCTAssertEqual(model.suggestions(formatter)?.trains.first?.alert?.kind, .thisTrip)
        XCTAssertEqual(model.suggestions(formatter)?.trains.first?.words, "Once")

        running.cancel()
        model.leftTab()
        XCTAssertFalse(model.showsSuggestions)
    }

    func testLeavingTheTabRemovesAOneDayAlertSwitchedOff() async {
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [AlertsFixtures.today, AlertsFixtures.evening])
        let model = await AlertsFixtures.model(rules)

        await model.tapBell("today")?.value
        XCTAssertEqual(ids(model), ["today", "evening"], "still listed while the tab shows")

        model.leftTab()
        XCTAssertEqual(rules.rules.map(\.id), ["evening"], "a switched-off repeating alert keeps its days")
    }

    // MARK: Remove and Undo (TT-254's Remove alert)

    func testRemoveThenUndoBringsTheSameAlertBack() async {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(server, on: [AlertsFixtures.evening, AlertsFixtures.morning])
        let model = await AlertsFixtures.model(rules)

        let removing = model.remove("evening")
        XCTAssertEqual(ids(model), ["morning"], "gone at once")
        XCTAssertEqual(model.capsule?.kind, .removed)
        await removing?.value
        let deleted = await server.deleted
        XCTAssertEqual(deleted, ["evening"])

        await model.undo()
        XCTAssertNil(model.capsule)
        XCTAssertEqual(ids(model), ["morning", "evening"])
        let saved = await server.saved
        XCTAssertEqual(saved.last, AlertsFixtures.evening, "saved again with the same id and days")
    }

    // MARK: Tab dot

    func testTheTabDotShowsWhileASwitchedOnAlertsTrainIsLate() async {
        let late = AlertsFixtures.trains(live: ["OA>UN": AlertsFixtures.live(delays: ["LW-0732": 9])])
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [AlertsFixtures.morning])

        let quiet = await AlertsFixtures.model(rules)
        XCTAssertNil(quiet.tabDot(isSelected: false, hasNewUpdate: false))
        XCTAssertEqual(quiet.tabDot(isSelected: false, hasNewUpdate: true), .accent)

        let model = await AlertsFixtures.model(rules, repository: late)
        XCTAssertTrue(model.hasChangedTrain)
        XCTAssertEqual(model.tabDot(isSelected: false, hasNewUpdate: false), .accent)
        XCTAssertNil(model.tabDot(isSelected: true, hasNewUpdate: false), "none while Alerts shows")

        var paused = AlertsFixtures.morning
        paused.paused = true
        let off = await AlertsFixtures.model(await AlertsFixtures.rules(FakeAlertServer(), on: [paused]), repository: late)
        XCTAssertFalse(off.hasChangedTrain, "an alert switched off says nothing")
    }

    func testTheDotGoesOnceTheLateTrainHasLeftBeforeTheNextRead() async {
        let at735 = AlertsFixtures.now.addingTimeInterval(14 * 60)
        let clock = TestClock(now: at735)
        let live = AlertsFixtures.live(delays: ["LW-0732": 9], at: at735)
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [AlertsFixtures.morning])
        let model = await AlertsFixtures.model(rules, repository: AlertsFixtures.trains(live: ["OA>UN": live]), clock: clock)
        XCTAssertTrue(model.hasChangedTrain)

        clock.advance(minutes: 7)
        XCTAssertFalse(model.hasChangedTrain, "7:42 AM: the 7:41 has left")
    }

    func testTheRedDotWinsOverTheAccentDotAndHidesOnAlerts() async {
        let rules = await AlertsFixtures.rules(FakeAlertServer(), permission: .off, on: [AlertsFixtures.morning])
        let model = await AlertsFixtures.model(rules)
        XCTAssertEqual(model.tabDot(isSelected: false, hasNewUpdate: true), .warning)
        XCTAssertNil(model.tabDot(isSelected: true, hasNewUpdate: true))
    }

    // MARK: Notifications off (TT-169, D58)

    func testTheWarningNeedsDeniedNotificationsAndASwitchedOnAlert() async {
        let cases: [(NotificationPermission, [AlertRule], Bool)] = [
            (.off, [AlertsFixtures.morning], true),
            (.off, [AlertsFixtures.evening], false),
            (.off, [], false),
            (.notAsked, [AlertsFixtures.morning], false),
            (.allowed, [AlertsFixtures.morning], false),
        ]
        for (permission, on, warns) in cases {
            let rules = await AlertsFixtures.rules(FakeAlertServer(), permission: permission, on: on)
            let model = await AlertsFixtures.model(rules)
            XCTAssertEqual(model.warnsNotificationsOff, warns, "\(permission) with \(on.map(\.id))")
        }
    }

    func testTheCardCountsAlertsSwitchedOn() async {
        let rules = await AlertsFixtures.rules(
            FakeAlertServer(), permission: .off, on: [AlertsFixtures.morning, AlertsFixtures.evening, AlertsFixtures.today]
        )
        let model = await AlertsFixtures.model(rules)

        XCTAssertEqual(model.switchedOnCount, 2, "evening is switched off")
        XCTAssertEqual(AlertsViewModel.offLine(count: 3), "3 alerts can’t reach you.")
        XCTAssertEqual(AlertsViewModel.offLine(count: 1), "1 alert can’t reach you.")
        XCTAssertEqual(AlertsViewModel.offDetail(count: 2), "Your 2 alerts are saved, but they can't reach you.")
        model.nudge()
        XCTAssertEqual(model.nudges, 1)
    }

    /// Returning with notifications allowed clears the warning and shows "Notifications are on" once, after a moment.
    func testAllowingNotificationsShowsNotificationsAreOn() async {
        let permission = SwitchablePermission(.off)
        let rules = AlertRules(server: FakeAlertServer(), push: FixturePushRegistration(), permissions: permission, defaults: nil)
        await rules.save(AlertsFixtures.morning)
        let model = AlertsViewModel(
            rules: rules, repository: AlertsFixtures.trains(), clock: FixedClock(now: AlertsFixtures.now),
            plainDuration: .seconds(1), notificationsOnDelay: .milliseconds(10), haptics: FakeHaptics()
        )
        XCTAssertTrue(model.warnsNotificationsOff)

        await model.refresh()
        XCTAssertNil(model.capsule, "still denied: nothing changes")

        await permission.set(.allowed)
        await model.refresh()
        XCTAssertFalse(model.warnsNotificationsOff)
        let shown = await poll { model.capsule?.kind == .notificationsOn }
        XCTAssertTrue(shown)
        let gone = await poll { model.capsule == nil }
        XCTAssertTrue(gone, "and leaves by itself")
    }

    // MARK: Helpers

    private func items(_ model: AlertsViewModel) -> [AlertsViewModel.Item] {
        model.sections(formatter).flatMap(\.cards)
    }

    private func ids(_ model: AlertsViewModel) -> [String] {
        items(model).map(\.id)
    }

    private func item(_ model: AlertsViewModel, _ id: String) -> AlertsViewModel.Item? {
        items(model).first { $0.id == id }
    }

    /// The Schedule card an alert's item draws, when it has its train.
    private func card(_ model: AlertsViewModel, _ id: String) -> DepartureCard? {
        guard case .train(let card, _, _)? = item(model, id)?.body else { return nil }
        return card
    }

    private func isPending(_ item: AlertsViewModel.Item?) -> Bool {
        if case .pending? = item?.body { return true }
        return false
    }

    /// Polls for up to 3 s.
    private func poll(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<300 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

/// What the bell's permission rule was asked, and its answer.
@MainActor
private final class PermissionRecorder {
    var trains: [String] = []
}

/// A permission the test turns on by hand, as the rider does in iOS Settings.
actor SwitchablePermission: NotificationPermissionProviding {
    private var value: NotificationPermission

    init(_ value: NotificationPermission) {
        self.value = value
    }

    func set(_ new: NotificationPermission) { value = new }

    func current() async -> NotificationPermission { value }
}
