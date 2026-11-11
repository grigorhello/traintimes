import XCTest
@testable import TrainTimes

/// The one-tap bell (TT-141): arms with permission, turns off on a second tap, sends one request for repeated taps, and says
/// Could not save when the server is down. Permission from the bell (TT-190): the first tap asks iOS, a refusal saves
/// nothing and explains, and Turn on brings the tapped bell back on.
@MainActor
final class AlertBellModelTests: XCTestCase {
    private let route = AlertFixtures.route
    private let trip = AlertFixtures.trip()

    func testTapArmsAThisTripAlertThenTurnsItOff() async {
        let server = FakeAlertServer()
        let bells = AlertBellModel(rules: AlertFixtures.rules(server))

        await bells.tap(trip, on: route)
        XCTAssertEqual(bells.bell(for: trip, on: route), .on)
        XCTAssertEqual(bells.toast?.kind, .on)
        XCTAssertEqual(bells.enabledCount, 1)
        let saved = await server.saved
        XCTAssertEqual(saved.map(\.kind), [.thisTrip])

        await bells.tap(trip, on: route)
        XCTAssertEqual(bells.bell(for: trip, on: route), .off)
        XCTAssertEqual(bells.toast?.kind, .off)
        XCTAssertEqual(bells.enabledCount, 1)
        let deleted = await server.deleted
        XCTAssertEqual(deleted, saved.map(\.id))
    }

    /// Paused on the Alerts tab (TT-143): the bell is outlined, and a tap resumes the alert instead of deleting it.
    func testAPausedAlertShowsAnOutlinedBellAndATapResumesIt() async throws {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        let bells = AlertBellModel(rules: rules)
        await bells.tap(trip, on: route)
        var rule = try XCTUnwrap(rules.alert(for: trip, on: route))
        rule.paused = true
        await rules.save(rule)
        XCTAssertEqual(bells.bell(for: trip, on: route), .off)

        await bells.tap(trip, on: route)
        XCTAssertEqual(bells.bell(for: trip, on: route), .on)
        XCTAssertEqual(bells.toast?.kind, .on)
        XCTAssertEqual(rules.rules.map(\.id), [rule.id], "the same rule, not deleted")
        XCTAssertEqual(rules.rules.first?.paused, false)
        let deleted = await server.deleted
        XCTAssertTrue(deleted.isEmpty)
    }

    // MARK: Permission from the bell (TT-190)

    /// The first tap ever is the request: the bell holds while iOS asks, and Allow turns the alert on.
    func testTheFirstTapAsksIOSAndAllowTurnsTheAlertOn() async {
        let server = FakeAlertServer()
        let permission = SettableNotificationPermission(.notAsked, answer: .allowed)
        let rules = AlertRules(server: server, push: FixturePushRegistration(), permissions: permission, defaults: nil)
        let seen = FaceRecorder(trip: trip, route: route)
        let bells = AlertBellModel(rules: rules, refusalDelay: .zero, afterPrompt: { seen.record() })
        seen.bells = bells

        await bells.tap(trip, on: route)

        XCTAssertEqual(seen.faces, [.asking], "the bell holds while iOS asks")
        let asked = await permission.requests
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(bells.bell(for: trip, on: route), .on)
        XCTAssertEqual(bells.toast?.kind, .on)
        XCTAssertEqual(bells.enabledCount, 1)
        XCTAssertEqual(bells.shakes(for: trip), 0)
        let saved = await server.saved
        XCTAssertEqual(saved.count, 1)
    }

    /// Don't Allow saves nothing: the bell stays an outline and shakes, the warning haptic plays, and the toast says
    /// Notifications are off with Turn on. A later tap does not ask again: it explains again.
    func testDontAllowSavesNothingTheBellShakesAndTheToastExplains() async {
        let server = FakeAlertServer()
        let permission = SettableNotificationPermission(.notAsked, answer: .off)
        let rules = AlertRules(server: server, push: FixturePushRegistration(), permissions: permission, defaults: nil)
        let bells = AlertBellModel(rules: rules, refusalDelay: .zero, afterPrompt: {})

        await bells.tap(trip, on: route)
        XCTAssertEqual(bells.bell(for: trip, on: route), .off)
        XCTAssertEqual(bells.shakes(for: trip), 1)
        XCTAssertEqual(bells.refusedCount, 1)
        XCTAssertEqual(bells.toast?.kind, .notificationsOff)
        XCTAssertTrue(rules.rules.isEmpty)

        await bells.tap(trip, on: route)
        let asked = await permission.requests
        XCTAssertEqual(asked, 1, "iOS asks once")
        XCTAssertEqual(bells.shakes(for: trip), 2)
        XCTAssertEqual(bells.toast?.kind, .notificationsOff)
        XCTAssertEqual(bells.enabledCount, 0)
        let saved = await server.saved
        XCTAssertEqual(saved, [])
    }

    /// With notifications off a tap makes no alert; Turn on remembers the bell, and back with notifications on it turns on.
    func testTurnOnInSettingsTurnsTheTappedBellOnWhenBackAllowed() async {
        let server = FakeAlertServer()
        let permission = SettableNotificationPermission(.off)
        let rules = AlertRules(server: server, push: FixturePushRegistration(), permissions: permission, defaults: nil)
        let bells = AlertBellModel(rules: rules, refusalDelay: .zero, afterPrompt: {})
        let other = AlertFixtures.trip("LW-0758-20261105")

        await bells.tap(trip, on: route)
        XCTAssertEqual(bells.toast?.kind, .notificationsOff)
        bells.turnOnInSettings()
        XCTAssertNil(bells.toast)

        await permission.set(.allowed)
        await bells.cameBack()
        XCTAssertEqual(bells.bell(for: trip, on: route), .on)
        XCTAssertEqual(bells.bell(for: other, on: route), .off)
        XCTAssertEqual(bells.toast?.kind, .on)
        XCTAssertEqual(rules.rules.count, 1)

        // Once only: a later return does nothing more.
        await bells.tap(trip, on: route)
        await bells.cameBack()
        XCTAssertEqual(bells.bell(for: trip, on: route), .off)
    }

    /// Back from iOS Settings still off: nothing is saved, and the bell is forgotten.
    func testComingBackWithNotificationsStillOffSavesNothing() async {
        let server = FakeAlertServer()
        let permission = SettableNotificationPermission(.off)
        let rules = AlertRules(server: server, push: FixturePushRegistration(), permissions: permission, defaults: nil)
        let bells = AlertBellModel(rules: rules, refusalDelay: .zero, afterPrompt: {})

        await bells.tap(trip, on: route)
        bells.turnOnInSettings()
        await bells.cameBack()
        XCTAssertTrue(rules.rules.isEmpty)

        await permission.set(.allowed)
        await bells.cameBack()
        XCTAssertTrue(rules.rules.isEmpty, "forgotten after the first return")
        XCTAssertEqual(bells.bell(for: trip, on: route), .off)
    }

    func testRepeatedTapsSendOneRequest() async {
        let server = FakeAlertServer()
        await server.holdSaves()
        let bells = AlertBellModel(rules: AlertFixtures.rules(server))

        let first = Task { await bells.tap(trip, on: route) }
        await server.waitUntilHolding()
        XCTAssertEqual(bells.bell(for: trip, on: route), .waiting, "half strength, no words (TT-190)")
        XCTAssertNil(bells.toast)
        await bells.tap(trip, on: route)
        await bells.tap(trip, on: route)
        await server.release()
        _ = await first.value

        let saved = await server.saved
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(bells.bell(for: trip, on: route), .on)
    }

    func testAnUnreachableServerSaysCouldNotSaveAndTheBellStaysOff() async {
        let server = FakeAlertServer()
        await server.setFailing(true)
        let bells = AlertBellModel(rules: AlertFixtures.rules(server), refusalDelay: .zero)

        await bells.tap(trip, on: route)
        XCTAssertEqual(bells.toast?.kind, .couldNotSave)
        XCTAssertEqual(bells.bell(for: trip, on: route), .off)
        XCTAssertEqual(bells.shakes(for: trip), 1, "a failed save shakes the bell too (TT-190)")
        XCTAssertEqual(bells.enabledCount, 0)

        // Try again saves the same rule.
        await server.setFailing(false)
        await bells.tap(trip, on: route)
        XCTAssertEqual(bells.bell(for: trip, on: route), .on)
        XCTAssertEqual(bells.rules.rules.count, 1)
    }

    func testRepeatOpensTheSetupSheetOnRepeatForTheSameTrain() async {
        let bells = AlertBellModel(rules: AlertFixtures.rules(FakeAlertServer()))
        await bells.tap(trip, on: route)

        XCTAssertEqual(bells.repeatRequest(), AlertSetupRequest(route: route, trip: trip, kind: .repeating))
        XCTAssertNil(bells.toast)
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
        XCTAssertEqual(bells.bell(for: AlertFixtures.trip("LW-0732-20261107", day: 7), on: route), .off, "Saturday")

        await bells.tap(friday, on: route)
        XCTAssertEqual(bells.toast?.kind, .off)
        XCTAssertEqual(bells.bell(for: friday, on: route), .off)
        XCTAssertEqual(bells.bell(for: trip, on: route), .off, "every day is off")
        XCTAssertEqual(rules.rules.map(\.id), [id])
        XCTAssertEqual(rules.rules.first?.paused, true)
        XCTAssertEqual(rules.rules.first?.weekdays, [1, 2, 3, 4, 5])

        await bells.tap(trip, on: route)
        XCTAssertEqual(bells.toast?.kind, .on)
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
        let saturday = AlertFixtures.trip("LW-0732-20261107", day: 7)

        await bells.tap(saturday, on: route)

        XCTAssertEqual(rules.rules.count, 1)
        XCTAssertEqual(rules.rules.first?.kind, .repeating)
        XCTAssertEqual(rules.rules.first?.weekdays, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(bells.bell(for: saturday, on: route), .on)
        XCTAssertEqual(bells.toast?.kind, .on)
    }

    /// Crossed (TT-190): an alert covers the train but notifications are off. A tap explains and never deletes.
    func testACrossedBellExplainsAndNeverDeletes() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server, permission: .off)
        await rules.save(AlertRule(kind: .repeating, trip: trip, route: route, weekdays: [4]))
        let bells = AlertBellModel(rules: rules, refusalDelay: .zero)
        await rules.refreshPermission()
        XCTAssertEqual(bells.bell(for: trip, on: route), .crossed)

        await bells.tap(trip, on: route)
        XCTAssertEqual(bells.bell(for: trip, on: route), .crossed)
        XCTAssertEqual(bells.toast?.kind, .notificationsOff)
        XCTAssertEqual(bells.shakes(for: trip), 1)
        XCTAssertEqual(rules.rules.count, 1)
        XCTAssertEqual(rules.rules.first?.paused, false)
        let deleted = await server.deleted
        XCTAssertEqual(deleted, [])
    }

    func testTheToastHidesAfterItsTime() async throws {
        let bells = AlertBellModel(rules: AlertFixtures.rules(FakeAlertServer()), toastDuration: .milliseconds(50))
        await bells.tap(trip, on: route)
        XCTAssertNotNil(bells.toast)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(bells.toast)
    }
}

/// Records the bell's face each time iOS's answer comes in (the model's `afterPrompt`).
@MainActor
private final class FaceRecorder {
    let trip: Trip
    let route: Route
    weak var bells: AlertBellModel?
    private(set) var faces: [AlertBellModel.Bell] = []

    init(trip: Trip, route: Route) {
        self.trip = trip
        self.route = route
    }

    func record() {
        if let bells { faces.append(bells.bell(for: trip, on: route)) }
    }
}
