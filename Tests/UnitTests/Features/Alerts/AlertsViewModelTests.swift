import XCTest
@testable import TrainTimes

/// The Alerts tab as one list (TT-193): rows in time order with one line, the switch, the day tiles and Remove alert all
/// acting on the same alert, Undo, the next trains of the empty tab, Recent, notifications off and the tab dot.
@MainActor
final class AlertsViewModelTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)

    func testRowsAreInTimeOrderWithOneLineAndASwitch() async {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(
            server, on: [AlertsFixtures.evening, AlertsFixtures.today, AlertsFixtures.morning], reviewNeeded: [AlertsFixtures.burlington]
        )
        let model = await AlertsFixtures.model(rules)

        let rows = model.rows(formatter)
        XCTAssertEqual(rows.map(\.id), ["morning", "burlington", "today", "evening"])
        XCTAssertEqual(rows.map(\.time), ["7:32 AM", "8:05 AM", "8:21 AM", "5:10 PM"])
        XCTAssertEqual(rows.map(\.line), [
            "Oakville to Union · Mon to Fri", "Burlington to Union · Time changed", "Oakville to Union · Today only",
            "Union to Oakville · Mon to Thu",
        ])
        XCTAssertEqual(rows.map(\.isOn), [true, false, true, false], "Time changed has its switch off; evening is paused")
        XCTAssertEqual(rows.map(\.note), [.none, .timeChanged, .none, .none])
        XCTAssertEqual(rows.map(\.days), [[1, 2, 3, 4, 5], [1, 2, 3, 4, 5], [], [1, 2, 3, 4]])
        XCTAssertEqual(rows.first?.testID, "alerts.rule.LW-0732-20261105")
        XCTAssertFalse(model.isEmpty)
    }

    func testAOneDayAlertNamesItsDay() async {
        let tomorrow = AlertRule(id: "fri", kind: .thisTrip, trip: AlertFixtures.trip("LW-0732-20261106", day: 6), route: AlertsFixtures.oakvilleToUnion)
        let saturday = AlertRule(id: "sat", kind: .thisTrip, trip: AlertFixtures.trip("LW-0821-20261107", day: 7, departure: "13:21"), route: AlertsFixtures.oakvilleToUnion)
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [tomorrow, saturday])
        let model = await AlertsFixtures.model(rules)

        XCTAssertEqual(model.rows(formatter).map(\.line), ["Oakville to Union · Tomorrow only", "Oakville to Union · Sat 7 only"])
    }

    func testARepeatingAlertWithNoTrainTodaySaysSo() async {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(server, on: [AlertsFixtures.morning])
        await server.setStatuses([AlertRuleStatus(id: "morning", state: .on, noMatchingTrainOn: "20261105")])
        await rules.refresh()
        let model = await AlertsFixtures.model(rules)

        let row = model.rows(formatter).first
        XCTAssertEqual(row?.line, "Oakville to Union · No train today")
        XCTAssertEqual(row?.note, .noTrainToday)
        XCTAssertEqual(row?.isOn, true)
    }

    /// A one-day alert goes from the list once its train has left, today's too.
    func testOneDayAlertsWhoseTrainHasLeftAreNotListed() async {
        let yesterday = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip("LW-0732-20261104", day: 4), route: AlertsFixtures.oakvilleToUnion)
        let left = AlertRule(kind: .thisTrip, trip: AlertFixtures.trip("LW-0700-20261105", departure: "12:00"), route: AlertsFixtures.oakvilleToUnion)
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [yesterday, left])
        let model = await AlertsFixtures.model(rules)

        XCTAssertTrue(model.rows(formatter).isEmpty)
        XCTAssertTrue(model.isEmpty)
    }

    func testOneRowOpensAtATime() async {
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [AlertsFixtures.morning, AlertsFixtures.today])
        let model = await AlertsFixtures.model(rules)

        model.toggleOpen("morning")
        XCTAssertEqual(model.openID, "morning")
        model.toggleOpen("today")
        XCTAssertEqual(model.openID, "today")
        model.toggleOpen("today")
        XCTAssertNil(model.openID)
    }

    // MARK: Same alert, same id

    func testTheSwitchSavesTheSameAlertAndTheRowStays() async {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(server, on: [AlertsFixtures.morning, AlertsFixtures.today])
        let model = await AlertsFixtures.model(rules)

        await model.setOn(false, for: "morning")?.value
        XCTAssertEqual(model.rows(formatter).map(\.id), ["morning", "today"], "the row stays where it is")
        XCTAssertEqual(model.rows(formatter).first?.isOn, false)
        var saved = await server.saved
        XCTAssertEqual(saved.last?.id, "morning")
        XCTAssertEqual(saved.last?.paused, true)

        await model.setOn(true, for: "morning")?.value
        XCTAssertEqual(model.rows(formatter).first?.isOn, true)
        saved = await server.saved
        XCTAssertEqual(saved.last?.paused, false)
    }

    func testASwitchTheServerCannotTakeGoesBackAndOffersTryAgain() async {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(server, on: [AlertsFixtures.morning])
        let model = await AlertsFixtures.model(rules)

        await server.setFailing(true)
        await model.setOn(false, for: "morning")?.value
        XCTAssertEqual(model.rows(formatter).first?.isOn, true, "back to what was saved")
        XCTAssertEqual(model.capsule?.kind, .failed(.turnOff))

        await server.setFailing(false)
        await model.tryAgain()
        XCTAssertEqual(model.rows(formatter).first?.isOn, false)
        XCTAssertNil(model.capsule)
    }

    func testADayTileChangesTheSameAlert() async {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(server, on: [AlertsFixtures.morning])
        let model = await AlertsFixtures.model(rules)

        let task = model.toggleDay(6, for: "morning")
        XCTAssertEqual(model.rows(formatter).first?.days, [1, 2, 3, 4, 5, 6], "lit at once")
        XCTAssertEqual(model.dayOnCount, 1)
        await task?.value
        XCTAssertEqual(model.rows(formatter).first?.line, "Oakville to Union · Mon to Sat")
        let saved = await server.saved
        XCTAssertEqual(saved.last?.id, "morning")
        XCTAssertEqual(saved.last?.weekdays, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(rules.rules.count, 1)
    }

    func testTheLastLitDayCannotBeClearedHere() async {
        let weekend = AlertRule(id: "sat", kind: .repeating, trip: AlertFixtures.trip(), route: AlertsFixtures.oakvilleToUnion, weekdays: [6])
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(server, on: [weekend])
        let model = await AlertsFixtures.model(rules)
        let before = await server.saved.count

        XCTAssertNil(model.toggleDay(6, for: "sat"))
        XCTAssertEqual(model.rows(formatter).first?.days, [6])
        XCTAssertEqual(model.lastDayTaps["sat"], 1, "the tile presses and settles back")
        let after = await server.saved.count
        XCTAssertEqual(after, before)
    }

    func testLightingADayOnAOneDayAlertMakesItRepeatUnderItsID() async {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(server, on: [AlertsFixtures.today])
        let model = await AlertsFixtures.model(rules)

        await model.toggleDay(4, for: "today")?.value
        XCTAssertEqual(rules.rules.map(\.id), ["today"])
        XCTAssertEqual(rules.rules.first?.kind, .repeating)
        XCTAssertEqual(rules.rules.first?.weekdays, [4])
        XCTAssertEqual(model.rows(formatter).first?.line, "Oakville to Union · Thu")
    }

    func testADayChangeTheServerCannotTakeGoesBack() async {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(server, on: [AlertsFixtures.morning])
        let model = await AlertsFixtures.model(rules)

        await server.setFailing(true)
        await model.toggleDay(6, for: "morning")?.value
        XCTAssertEqual(model.rows(formatter).first?.days, [1, 2, 3, 4, 5])
        XCTAssertEqual(model.capsule?.kind, .failed(.changeDays))
    }

    func testRemoveThenUndoBringsTheSameAlertBack() async {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(server, on: [AlertsFixtures.evening, AlertsFixtures.morning])
        let model = await AlertsFixtures.model(rules)
        model.toggleOpen("evening")

        let removing = model.remove("evening")
        XCTAssertEqual(model.rows(formatter).map(\.id), ["morning"], "gone at once")
        XCTAssertNil(model.openID)
        XCTAssertEqual(model.capsule?.kind, .removed)
        await removing?.value
        let deleted = await server.deleted
        XCTAssertEqual(deleted, ["evening"])

        await model.undo()
        XCTAssertNil(model.capsule)
        XCTAssertEqual(model.rows(formatter).map(\.id), ["morning", "evening"])
        XCTAssertEqual(model.rows(formatter).last?.isOn, false, "paused as before")
        let saved = await server.saved
        XCTAssertEqual(saved.last, AlertsFixtures.evening, "saved again with the same id and days")
    }

    func testTheRemovedCapsuleGoesAfterItsTime() async throws {
        let rules = await AlertsFixtures.rules(FakeAlertServer(), on: [AlertsFixtures.morning])
        let model = await AlertsFixtures.model(rules, actionDuration: .milliseconds(50))

        await model.remove("morning")?.value
        XCTAssertNotNil(model.capsule)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(model.capsule)
        XCTAssertTrue(model.isEmpty)
    }

    func testLeavingTheTabRemovesAOneDayAlertSwitchedOff() async {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(server, on: [AlertsFixtures.today, AlertsFixtures.evening])
        let model = await AlertsFixtures.model(rules)
        await model.setOn(false, for: "today")?.value
        XCTAssertEqual(model.rows(formatter).map(\.id), ["today", "evening"], "still listed while the tab shows")

        model.leftTab()
        XCTAssertEqual(rules.rules.map(\.id), ["evening"], "a paused repeating alert keeps its days")
    }

    // MARK: Empty

    func testTheEmptyTabOffersTheNextThreeTrains() async {
        let rules = AlertFixtures.rules(FakeAlertServer())
        let model = await AlertsFixtures.model(rules, nextTrains: AlertsFixtures.nextTrains)

        XCTAssertTrue(model.isEmpty)
        let trains = model.nextTrainRows(formatter)
        XCTAssertEqual(trains.map(\.time), ["7:32 AM", "7:58 AM", "8:21 AM"])
        XCTAssertEqual(trains.map(\.line), ["Oakville to Union · in 11 min", "Oakville to Union · in 37 min", "Oakville to Union · in 1 h"])
    }

    func testWithNoRouteTheEmptyTabHasNoTrains() async {
        let model = await AlertsFixtures.model(AlertFixtures.rules(FakeAlertServer()))
        XCTAssertTrue(model.nextTrainRows(formatter).isEmpty)
    }

    // MARK: Recent

    func testRecentIsUpToThreeFromTheLastSevenDays() async {
        let old = AlertsFixtures.update(
            "old", title: "7:32 AM train cancelled", body: "", at: "2026-10-28T12:00:00Z", tripId: "LW-0732-20261028", serviceDate: "20261028"
        )
        let monday = AlertsFixtures.update(
            "monday", kind: .cancelled, title: "5:10 PM train cancelled", body: "", at: "2026-11-02T21:00:00Z",
            tripId: "LW-1710-20261102", serviceDate: "20261102"
        )
        let earlier = AlertsFixtures.update(
            "earlier", title: "6:40 AM train delayed 5 min", body: "", at: "2026-11-01T11:00:00Z", tripId: "LW-0640-20261101", serviceDate: "20261101"
        )
        let updates = await AlertsFixtures.updates([AlertsFixtures.updates[1], old, AlertsFixtures.updates[0], monday, earlier])
        let model = await AlertsFixtures.model(AlertFixtures.rules(FakeAlertServer()), updates: updates)

        let rows = model.recentRows(formatter)
        XCTAssertEqual(rows.map(\.id), ["delay", "recovery", "monday"])
        XCTAssertEqual(rows.map(\.when), ["7:29 AM", "Yesterday", "Mon"])
        XCTAssertEqual(rows.map(\.title), ["7:32 AM train delayed 9 min", "5:10 PM train back on time", "5:10 PM train cancelled"])
        XCTAssertEqual(
            rows.first?.link,
            .trip(TripKey(serviceDay: ServiceDay(year: 2026, month: 11, day: 5), tripId: "LW-0732-20261105"), originId: "OA", destinationId: "UN")
        )
        XCTAssertNil(rows[1].link, "yesterday's trip no longer opens")
    }

    // MARK: Tab dot

    func testTheTabDotShowsForATimeChangeUntilTheTabIsOpened() async {
        let server = FakeAlertServer()
        let rules = await AlertsFixtures.rules(server, on: [AlertsFixtures.morning])
        let model = await AlertsFixtures.model(rules)
        XCTAssertFalse(model.showsTabDot)

        await server.setStatuses([AlertRuleStatus(id: "morning", state: .reviewNeeded)])
        await model.refresh()
        XCTAssertTrue(model.showsTabDot)
        XCTAssertEqual(model.rows(formatter).first?.note, .timeChanged)

        model.markReviewsSeen()
        XCTAssertFalse(model.showsTabDot)
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

        XCTAssertEqual(model.switchedOnCount, 2, "evening is paused")
        XCTAssertEqual(AlertsViewModel.offLine(count: 3), "3 alerts can’t reach you.")
        XCTAssertEqual(AlertsViewModel.offLine(count: 1), "1 alert can’t reach you.")
        XCTAssertEqual(AlertsViewModel.offDetail(count: 2), "Your 2 alerts are saved, but they can't reach you.")
        model.nudge()
        XCTAssertEqual(model.nudges, 1)
    }

    func testTheRedDotWinsOverTheAccentDotAndHidesOnAlerts() async {
        let quiet = await AlertsFixtures.model(await AlertsFixtures.rules(FakeAlertServer(), on: [AlertsFixtures.morning]))
        XCTAssertNil(quiet.tabDot(isSelected: false, hasNewUpdate: false))
        XCTAssertEqual(quiet.tabDot(isSelected: false, hasNewUpdate: true), .accent)

        let rules = await AlertsFixtures.rules(FakeAlertServer(), permission: .off, on: [AlertsFixtures.morning])
        let model = await AlertsFixtures.model(rules)
        XCTAssertEqual(model.tabDot(isSelected: false, hasNewUpdate: true), .warning)
        XCTAssertNil(model.tabDot(isSelected: true, hasNewUpdate: true))
    }

    /// Returning with notifications allowed clears the warning and shows "Notifications are on" once, after a moment.
    func testAllowingNotificationsShowsNotificationsAreOn() async {
        let permission = SwitchablePermission(.off)
        let rules = AlertRules(server: FakeAlertServer(), push: FixturePushRegistration(), permissions: permission, defaults: nil)
        await rules.save(AlertsFixtures.morning)
        let model = AlertsViewModel(
            rules: rules, updates: await AlertsFixtures.updates([]), clock: FixedClock(now: AlertsFixtures.now),
            plainDuration: .seconds(1), notificationsOnDelay: .milliseconds(10)
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

    /// Polls for up to 3 s.
    private func poll(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<300 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
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
