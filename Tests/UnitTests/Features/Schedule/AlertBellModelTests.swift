import XCTest
@testable import TrainTimes

/// The one-tap bell (TT-141) and its glass capsule (TT-191): a tap turns the alert on with Repeat, a second turns it off
/// with Undo; without permission it opens the setup sheet; repeated taps send one request; nothing is half-kept when the
/// server cannot be reached; Repeat grows the capsule into the day panel, where each tile saves by itself.
@MainActor
final class AlertBellModelTests: XCTestCase {
    private let route = AlertFixtures.route
    private let trip = AlertFixtures.trip()
    /// Saturday Nov 7.
    private let saturday = AlertFixtures.trip("LW-0732-20261107", day: 7)

    func testTapTurnsTheAlertOnWithRepeatThenOffWithUndo() async {
        let server = FakeAlertServer()
        let bells = AlertBellModel(rules: AlertFixtures.rules(server))

        let request = await bells.tap(trip, on: route)
        XCTAssertNil(request)
        XCTAssertEqual(bells.bell(for: trip, on: route), .on)
        XCTAssertEqual(bells.capsule?.kind, .on)
        XCTAssertEqual(bells.capsule?.actionKey, "alert.repeat")
        XCTAssertEqual(bells.enabledCount, 1)
        let saved = await server.saved
        XCTAssertEqual(saved.map(\.kind), [.thisTrip])

        _ = await bells.tap(trip, on: route)
        XCTAssertEqual(bells.bell(for: trip, on: route), .off)
        XCTAssertEqual(bells.capsule?.kind, .off)
        XCTAssertEqual(bells.capsule?.actionKey, "button.undo")
        XCTAssertEqual(bells.enabledCount, 1)
        await eventually { await server.deleted == saved.map(\.id) }
    }

    /// Paused on the Alerts tab (TT-143): the bell is outlined, and a tap resumes the alert instead of deleting it.
    func testAPausedAlertShowsAnOutlinedBellAndATapResumesIt() async throws {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let bells = AlertBellModel(rules: rules)
        _ = await bells.tap(trip, on: route)
        var rule = try XCTUnwrap(rules.alert(for: trip, on: route))
        rule.paused = true
        await rules.save(rule)
        XCTAssertEqual(bells.bell(for: trip, on: route), .off)

        _ = await bells.tap(trip, on: route)
        XCTAssertEqual(bells.bell(for: trip, on: route), .on)
        XCTAssertEqual(bells.capsule?.kind, .on)
        XCTAssertEqual(rules.rules.map(\.id), [rule.id], "the same rule, not deleted")
        XCTAssertEqual(rules.rules.first?.paused, false)
        let deleted = await server.deleted
        XCTAssertTrue(deleted.isEmpty)
    }

    func testWithoutPermissionTheTapOpensTheSetupSheet() async {
        for permission in [NotificationPermission.notAsked, .off] {
            let server = FakeAlertServer()
            let bells = AlertBellModel(rules: AlertFixtures.rules(server, permission: permission))

            let request = await bells.tap(trip, on: route)
            XCTAssertEqual(request, AlertSetupRequest(route: route, trip: trip, kind: .thisTrip))
            XCTAssertNil(bells.capsule)
            let saved = await server.saved
            XCTAssertEqual(saved, [])
        }
    }

    /// While the server has not answered the bell is Setting up and no capsule shows; repeated taps send nothing more.
    func testRepeatedTapsSendOneRequest() async {
        let server = FakeAlertServer()
        await server.holdSaves()
        let bells = AlertBellModel(rules: AlertFixtures.rules(server))

        let first = Task { await bells.tap(trip, on: route) }
        await server.waitUntilHolding()
        XCTAssertEqual(bells.bell(for: trip, on: route), .settingUp)
        XCTAssertNil(bells.capsule)
        _ = await bells.tap(trip, on: route)
        _ = await bells.tap(trip, on: route)
        await server.release()
        _ = await first.value

        let saved = await server.saved
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(bells.bell(for: trip, on: route), .on)
        XCTAssertEqual(bells.capsule?.kind, .on)
    }

    /// Nothing half-kept (D71): a new alert the server cannot take is gone, the bell outlined; Try again saves it.
    func testAFailedNewAlertLeavesNoAlertAndTryAgainSavesIt() async {
        let server = FakeAlertServer()
        await server.setFailing(true)
        let bells = AlertBellModel(rules: AlertFixtures.rules(server))

        _ = await bells.tap(trip, on: route)
        XCTAssertEqual(bells.capsule?.kind, .failed(.turnOn))
        XCTAssertEqual(bells.capsule?.actionKey, "button.try_again")
        XCTAssertEqual(bells.bell(for: trip, on: route), .off)
        XCTAssertEqual(bells.rules.rules, [], "no alert kept as Could not save")
        XCTAssertEqual(bells.enabledCount, 0)

        await server.setFailing(false)
        let request = await bells.tryAgain()
        XCTAssertNil(request)
        XCTAssertEqual(bells.bell(for: trip, on: route), .on)
        XCTAssertEqual(bells.rules.rules.count, 1)
        XCTAssertEqual(bells.capsule?.kind, .on)
    }

    // MARK: Repeat and the day panel

    /// Repeat makes the same alert repeat Mon to Fri and opens the panel, which has no timer.
    func testRepeatMakesTheSameAlertRepeatMonToFriAndOpensThePanel() async throws {
        let rules = AlertFixtures.rules(FakeAlertServer())
        let bells = AlertBellModel(rules: rules, actionDuration: .milliseconds(50))
        _ = await bells.tap(trip, on: route)
        let id = try XCTUnwrap(rules.rules.first?.id)

        bells.repeatTapped()
        XCTAssertEqual(bells.capsule?.panelDays, [1, 2, 3, 4, 5])
        XCTAssertEqual(bells.capsule?.isPanelOpen, true)
        await eventually { rules.rules.first?.kind == .repeating }
        XCTAssertEqual(rules.rules.map(\.id), [id], "the same alert")
        XCTAssertEqual(rules.rules.first?.weekdays, [1, 2, 3, 4, 5])
        XCTAssertEqual(bells.bell(for: trip, on: route), .on)

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(bells.capsule?.isPanelOpen, true, "the panel stays until it is closed")
        bells.closePanel()
        XCTAssertNil(bells.capsule)
    }

    /// On a weekend train Repeat starts with that day alone.
    func testRepeatOnAWeekendTrainStartsWithThatDay() async {
        let rules = AlertFixtures.rules(FakeAlertServer())
        let bells = AlertBellModel(rules: rules)
        _ = await bells.tap(saturday, on: route)

        bells.repeatTapped()
        XCTAssertEqual(bells.capsule?.panelDays, [6])
        await eventually { rules.rules.first?.weekdays == [6] }
        XCTAssertEqual(rules.rules.first?.kind, .repeating)
    }

    /// Each tile saves by itself; lighting one plays the selection haptic; none lit makes it the one-day alert again.
    func testEachTileSavesByItselfAndNoDayLitMakesItAOneDayAlert() async throws {
        let rules = AlertFixtures.rules(FakeAlertServer())
        let bells = AlertBellModel(rules: rules)
        _ = await bells.tap(saturday, on: route)
        let id = try XCTUnwrap(rules.rules.first?.id)
        bells.repeatTapped()
        await eventually { rules.rules.first?.weekdays == [6] }

        bells.toggleDay(7)
        XCTAssertEqual(bells.capsule?.panelDays, [6, 7])
        XCTAssertEqual(bells.dayOnCount, 1)
        await eventually { rules.rules.first?.weekdays == [6, 7] }

        bells.toggleDay(6)
        bells.toggleDay(7)
        XCTAssertEqual(bells.capsule?.panelDays, [])
        XCTAssertEqual(bells.dayOnCount, 1, "turning a day off plays no haptic")
        await eventually { rules.rules.first?.kind == .thisTrip }
        XCTAssertEqual(rules.rules.map(\.id), [id])
        XCTAssertEqual(rules.rules.first?.trip, saturday.key)
        XCTAssertEqual(bells.bell(for: saturday, on: route), .on)
    }

    /// A day change the server cannot take goes back to the saved days, and "Couldn't change days" takes the panel's place;
    /// Try again saves the days asked for.
    func testAFailedDayChangeRollsBackAndTryAgainSavesIt() async throws {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let bells = AlertBellModel(rules: rules)
        _ = await bells.tap(trip, on: route)
        bells.repeatTapped()
        await eventually { rules.rules.first?.weekdays == [1, 2, 3, 4, 5] }

        await server.setFailing(true)
        bells.toggleDay(6)
        await eventually { bells.capsule?.kind == .failed(.changeDays) }
        XCTAssertEqual(bells.capsule?.isPanelOpen, false)
        XCTAssertEqual(rules.rules.first?.weekdays, [1, 2, 3, 4, 5], "back to what was saved")
        XCTAssertEqual(bells.bell(for: trip, on: route), .on, "the saved alert still works")

        await server.setFailing(false)
        _ = await bells.tryAgain()
        XCTAssertEqual(rules.rules.first?.weekdays, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(bells.capsule?.kind, .on)
        XCTAssertEqual(bells.capsule?.repeats, [1, 2, 3, 4, 5, 6])
        XCTAssertNil(bells.capsule?.actionKey, "a repeating alert's capsule has no action")
    }

    /// A bell tapped while the panel is open closes it first.
    func testABellTapClosesThePanel() async {
        let rules = AlertFixtures.rules(FakeAlertServer())
        let bells = AlertBellModel(rules: rules)
        _ = await bells.tap(trip, on: route)
        bells.repeatTapped()
        XCTAssertEqual(bells.capsule?.isPanelOpen, true)
        await eventually { rules.rules.first?.kind == .repeating }

        let later = AlertFixtures.trip("LW-0805-20261105", departure: "13:05")
        _ = await bells.tap(later, on: route)
        XCTAssertEqual(bells.capsule?.kind, .on)
        XCTAssertEqual(bells.capsule?.isPanelOpen, false)
    }

    // MARK: Undo and Try again

    /// Undo on a one-day alert puts it back with the same id.
    func testUndoPutsBackTheOneDayAlertWithTheSameID() async throws {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let bells = AlertBellModel(rules: rules)
        _ = await bells.tap(trip, on: route)
        let id = try XCTUnwrap(rules.rules.first?.id)
        _ = await bells.tap(trip, on: route)
        XCTAssertEqual(rules.rules, [])

        await bells.undo()
        XCTAssertEqual(rules.rules.map(\.id), [id])
        XCTAssertEqual(bells.bell(for: trip, on: route), .on)
        XCTAssertEqual(bells.capsule?.kind, .on)
        let deleted = await server.deleted
        XCTAssertEqual(deleted, [id], "the delete landed before the save")
        let saved = await server.saved
        XCTAssertEqual(saved.map(\.id), [id, id])
    }

    /// A repeating alert goes off with its days kept ("…, all days"), and Undo switches it back on.
    func testUndoSwitchesTheRepeatingAlertBackOnWithItsDays() async throws {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let bells = AlertBellModel(rules: rules)
        await rules.save(AlertRule(kind: .repeating, trip: trip, route: route, weekdays: [1, 2, 3, 4, 5]))
        let id = try XCTUnwrap(rules.rules.first?.id)

        _ = await bells.tap(trip, on: route)
        XCTAssertEqual(bells.capsule?.kind, .off)
        XCTAssertEqual(bells.capsule?.repeats, [1, 2, 3, 4, 5])
        XCTAssertEqual(rules.rules.first?.paused, true)

        await bells.undo()
        XCTAssertEqual(rules.rules.map(\.id), [id])
        XCTAssertEqual(rules.rules.first?.paused, false)
        XCTAssertEqual(rules.rules.first?.weekdays, [1, 2, 3, 4, 5])
        XCTAssertEqual(bells.bell(for: trip, on: route), .on)
    }

    /// A repeating alert the server cannot switch off stays on, and Try again switches it off.
    func testAFailedTurnOffKeepsTheAlertOnAndTryAgainTurnsItOff() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let bells = AlertBellModel(rules: rules)
        await rules.save(AlertRule(kind: .repeating, trip: trip, route: route, weekdays: [1, 2, 3, 4, 5]))

        await server.setFailing(true)
        _ = await bells.tap(trip, on: route)
        XCTAssertEqual(bells.capsule?.kind, .failed(.turnOff))
        XCTAssertEqual(rules.rules.first?.paused, false)
        XCTAssertEqual(bells.bell(for: trip, on: route), .on)

        await server.setFailing(false)
        _ = await bells.tryAgain()
        XCTAssertEqual(rules.rules.first?.paused, true)
        XCTAssertEqual(bells.capsule?.kind, .off)
    }

    // MARK: One alert per card (TT-189)

    /// A repeating alert fills the bell on each of its days; a tap switches it off, days kept, and the next tap brings it
    /// back. Never a second alert.
    func testARepeatingAlertFillsTheBellOnItsDaysAndATapSwitchesItOffKeepingItsDays() async throws {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let bells = AlertBellModel(rules: rules)
        await rules.save(AlertRule(kind: .repeating, trip: trip, route: route, weekdays: [1, 2, 3, 4, 5]))
        let id = try XCTUnwrap(rules.rules.first?.id)
        let friday = AlertFixtures.trip("LW-0732-20261106", day: 6)
        XCTAssertEqual(bells.bell(for: trip, on: route), .on)
        XCTAssertEqual(bells.bell(for: friday, on: route), .on)
        XCTAssertEqual(bells.bell(for: saturday, on: route), .off)

        _ = await bells.tap(friday, on: route)
        XCTAssertEqual(bells.capsule?.kind, .off)
        XCTAssertEqual(bells.bell(for: friday, on: route), .off)
        XCTAssertEqual(bells.bell(for: trip, on: route), .off, "every day is off")
        XCTAssertEqual(rules.rules.map(\.id), [id])
        XCTAssertEqual(rules.rules.first?.paused, true)
        XCTAssertEqual(rules.rules.first?.weekdays, [1, 2, 3, 4, 5])

        _ = await bells.tap(trip, on: route)
        XCTAssertEqual(bells.capsule?.kind, .on)
        XCTAssertEqual(bells.capsule?.repeats, [1, 2, 3, 4, 5])
        XCTAssertEqual(bells.bell(for: friday, on: route), .on)
        XCTAssertEqual(rules.rules.map(\.id), [id])
        XCTAssertEqual(rules.rules.first?.paused, false)
        let deleted = await server.deleted
        XCTAssertEqual(deleted, [])
    }

    /// A bell on a day the repeating alert leaves out adds that day to it.
    func testABellOnADayTheRepeatingAlertLeavesOutAddsThatDay() async throws {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let bells = AlertBellModel(rules: rules)
        await rules.save(AlertRule(kind: .repeating, trip: trip, route: route, weekdays: [1, 2, 3, 4, 5]))

        _ = await bells.tap(saturday, on: route)

        XCTAssertEqual(rules.rules.count, 1)
        XCTAssertEqual(rules.rules.first?.kind, .repeating)
        XCTAssertEqual(rules.rules.first?.weekdays, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(bells.bell(for: saturday, on: route), .on)
        XCTAssertEqual(bells.capsule?.kind, .on)
    }

    /// Without permission the sheet opens on the card's own alert, so a repeating one opens on Repeat.
    func testWithoutPermissionTheSheetOpensOnTheCardsAlert() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server, permission: .off)
        await rules.save(AlertRule(kind: .repeating, trip: trip, route: route, weekdays: [4]))
        let bells = AlertBellModel(rules: rules)

        let request = await bells.tap(trip, on: route)
        XCTAssertEqual(request, AlertSetupRequest(route: route, trip: trip, kind: .repeating))
        XCTAssertEqual(rules.rules.count, 1)
    }

    // MARK: Time on screen

    /// A capsule with an action shows for its action time; one without for the plain time.
    func testACapsuleWithAnActionAndOneWithoutHideAfterTheirTimes() async throws {
        let rules = AlertFixtures.rules(FakeAlertServer())
        let quick = AlertBellModel(rules: rules, actionDuration: .milliseconds(50), plainDuration: .seconds(60))
        _ = await quick.tap(trip, on: route)
        XCTAssertNotNil(quick.capsule)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(quick.capsule, "Alert on with Repeat")

        await rules.save(AlertRule(kind: .repeating, trip: saturday, route: route, weekdays: [6], paused: true))
        let plain = AlertBellModel(rules: rules, actionDuration: .seconds(60), plainDuration: .milliseconds(50))
        _ = await plain.tap(saturday, on: route)
        XCTAssertNil(plain.capsule?.actionKey)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(plain.capsule, "a repeating alert's Alert on, no action")
    }

    /// A finger on the capsule holds it; lifted, its time starts again.
    func testAFingerOnTheCapsuleHoldsIt() async throws {
        let bells = AlertBellModel(rules: AlertFixtures.rules(FakeAlertServer()), actionDuration: .milliseconds(100))
        _ = await bells.tap(trip, on: route)
        bells.holdCapsule(true)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNotNil(bells.capsule)

        bells.holdCapsule(false)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(bells.capsule)
    }

    func testTheHintShowsForItsTime() async throws {
        let bells = AlertBellModel(rules: AlertFixtures.rules(FakeAlertServer()), hintDuration: .milliseconds(50))
        bells.showHint()
        XCTAssertEqual(bells.capsule?.kind, .hint)
        XCTAssertNil(bells.capsule?.actionKey)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(bells.capsule)
    }

    // MARK: Words

    func testTheCapsuleWords() {
        let formatter = TimeFormatter(format: .twelveHour)
        let today = trip.key.serviceDay
        func words(_ kind: AlertBellModel.Capsule.Kind, _ trip: Trip, repeats: [Int] = []) -> String {
            AlertBellModel.Capsule(id: 1, kind: kind, trip: trip, route: route, repeats: repeats).words(formatter, today: today)
        }
        XCTAssertEqual(words(.on, trip), "Alert on · 7:32 AM")
        XCTAssertEqual(words(.on, saturday), "Alert on · Sat 7:32 AM", "a train on another day names the day")
        XCTAssertEqual(words(.on, trip, repeats: [1, 2, 3, 4, 5]), "Alert on · 7:32 AM, Mon to Fri")
        XCTAssertEqual(words(.off, trip), "Alert off · 7:32 AM")
        XCTAssertEqual(words(.off, trip, repeats: [1, 2, 3, 4, 5]), "Alert off · 7:32 AM, all days")
        XCTAssertEqual(words(.failed(.turnOn), trip), "Couldn’t turn alert on")
        XCTAssertEqual(words(.failed(.changeDays), trip), "Couldn’t change days")
        XCTAssertEqual(words(.failed(.turnOff), trip), "Couldn’t turn alert off")
        XCTAssertEqual(words(.notificationsOff, trip), "Notifications are off")
        XCTAssertEqual(AlertBellModel.Capsule(id: 1, kind: .hint, trip: nil, route: nil).words(formatter, today: today), "Tap the bell on a train")
    }

    func testThePanelWords() {
        let formatter = TimeFormatter(format: .twelveHour)
        let today = trip.key.serviceDay
        func words(_ trip: Trip, _ days: [Int]) -> String {
            AlertBellModel.Capsule(id: 1, kind: .on, trip: trip, route: route, panelDays: days).panelWords(formatter, today: today)
        }
        XCTAssertEqual(words(trip, [1, 2, 3, 4, 5]), "7:32 AM · Mon to Fri")
        XCTAssertEqual(words(trip, [6, 7]), "7:32 AM · Sat and Sun")
        XCTAssertEqual(words(trip, []), "7:32 AM · Today only")
        XCTAssertEqual(words(AlertFixtures.trip("LW-0732-20261106", day: 6), []), "7:32 AM · Tomorrow only")
        XCTAssertEqual(words(saturday, []), "7:32 AM · Sat 7 only")
    }

    /// Waits up to 3 s for work the model runs in its own task (the panel's saves, a delete).
    private func eventually(
        _ condition: () async -> Bool, file: StaticString = #filePath, line: UInt = #line
    ) async {
        for _ in 0..<300 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out", file: file, line: line)
    }
}
