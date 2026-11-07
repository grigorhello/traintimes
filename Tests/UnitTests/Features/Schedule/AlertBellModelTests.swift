import XCTest
@testable import TrainTimes

/// The one-tap bell (TT-141): arms with permission, turns off on a second tap, opens the setup sheet without permission,
/// sends one request for repeated taps, and says Could not save when the server is down.
@MainActor
final class AlertBellModelTests: XCTestCase {
    private let route = AlertFixtures.route
    private let trip = AlertFixtures.trip()

    func testTapArmsAThisTripAlertThenTurnsItOff() async {
        let server = FakeAlertServer()
        let bells = AlertBellModel(rules: AlertFixtures.rules(server))

        let request = await bells.tap(trip, on: route)
        XCTAssertNil(request)
        XCTAssertEqual(bells.bell(for: trip, on: route), .on)
        XCTAssertEqual(bells.toast?.kind, .on)
        XCTAssertEqual(bells.enabledCount, 1)
        let saved = await server.saved
        XCTAssertEqual(saved.map(\.kind), [.thisTrip])

        _ = await bells.tap(trip, on: route)
        XCTAssertEqual(bells.bell(for: trip, on: route), .off)
        XCTAssertEqual(bells.toast?.kind, .off)
        XCTAssertEqual(bells.enabledCount, 1)
        let deleted = await server.deleted
        XCTAssertEqual(deleted, saved.map(\.id))
    }

    func testWithoutPermissionTheTapOpensTheSetupSheet() async {
        for permission in [NotificationPermission.notAsked, .off] {
            let server = FakeAlertServer()
            let bells = AlertBellModel(rules: AlertFixtures.rules(server, permission: permission))

            let request = await bells.tap(trip, on: route)
            XCTAssertEqual(request, AlertSetupRequest(route: route, trip: trip, kind: .thisTrip))
            XCTAssertNil(bells.toast)
            let saved = await server.saved
            XCTAssertEqual(saved, [])
        }
    }

    func testRepeatedTapsSendOneRequest() async {
        let server = FakeAlertServer()
        await server.holdSaves()
        let bells = AlertBellModel(rules: AlertFixtures.rules(server))

        let first = Task { await bells.tap(trip, on: route) }
        await server.waitUntilHolding()
        XCTAssertEqual(bells.bell(for: trip, on: route), .settingUp)
        XCTAssertEqual(bells.toast?.kind, .settingUp)
        _ = await bells.tap(trip, on: route)
        _ = await bells.tap(trip, on: route)
        await server.release()
        _ = await first.value

        let saved = await server.saved
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(bells.bell(for: trip, on: route), .on)
    }

    func testAnUnreachableServerSaysCouldNotSaveAndTheBellStaysOff() async {
        let server = FakeAlertServer()
        await server.setFailing(true)
        let bells = AlertBellModel(rules: AlertFixtures.rules(server))

        _ = await bells.tap(trip, on: route)
        XCTAssertEqual(bells.toast?.kind, .couldNotSave)
        XCTAssertEqual(bells.bell(for: trip, on: route), .off)
        XCTAssertEqual(bells.enabledCount, 0)

        // Try again saves the same rule.
        await server.setFailing(false)
        _ = await bells.tap(trip, on: route)
        XCTAssertEqual(bells.bell(for: trip, on: route), .on)
        XCTAssertEqual(bells.rules.rules.count, 1)
    }

    func testRepeatOpensTheSetupSheetOnRepeatForTheSameTrain() async {
        let bells = AlertBellModel(rules: AlertFixtures.rules(FakeAlertServer()))
        _ = await bells.tap(trip, on: route)

        XCTAssertEqual(bells.repeatRequest(), AlertSetupRequest(route: route, trip: trip, kind: .repeating))
        XCTAssertNil(bells.toast)
    }

    func testTheToastHidesAfterItsTime() async throws {
        let bells = AlertBellModel(rules: AlertFixtures.rules(FakeAlertServer()), toastDuration: .milliseconds(50))
        _ = await bells.tap(trip, on: route)
        XCTAssertNotNil(bells.toast)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(bells.toast)
    }
}
