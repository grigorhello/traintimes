import XCTest
@testable import TrainTimes

/// Recent updates (TT-143): the server's train notifications read from their payload, kept on device for 7 days, newest
/// first, whether still in Notification Center or recorded when they arrived or were tapped.
@MainActor
final class AlertUpdatesTests: XCTestCase {
    func testReadsTheServersTripPayload() throws {
        let update = try XCTUnwrap(AlertUpdate(
            id: "n1", deliveredAt: AlertsFixtures.now, title: "5:10 PM train back on time", body: "Union to Oakville.",
            userInfo: ["tripId": "LW-1710-20261105", "serviceDate": "20261105", "originId": "UN", "destinationId": "OA", "kind": "recovery"]
        ))
        XCTAssertEqual(update.kind, .recovery)
        XCTAssertEqual(
            update.link,
            .trip(TripKey(serviceDay: ServiceDay(year: 2026, month: 11, day: 5), tripId: "LW-1710-20261105"), originId: "UN", destinationId: "OA")
        )
        // "Your usual train has changed" is about a rule, not a train.
        XCTAssertNil(AlertUpdate(id: "n2", deliveredAt: AlertsFixtures.now, title: "", body: "", userInfo: ["ruleId": "r1"]))
    }

    func testKeepsTheLastSevenDaysNewestFirstOnDevice() async {
        let defaults = UserDefaults.ephemeral()
        let old = AlertsFixtures.update(
            "old", title: "7:32 AM train cancelled", body: "", at: "2026-10-29T12:00:00Z", tripId: "LW-0732-20261029", serviceDate: "20261029"
        )
        let tapped = AlertsFixtures.update(
            "tapped", kind: .cancelled, title: "8:05 AM train cancelled", body: "", at: "2026-11-05T11:00:00Z",
            tripId: "LW-0805-20261105", serviceDate: "20261105"
        )
        AlertUpdates.record(tapped, in: defaults)
        let source = FixedDeliveredNotifications(updates: [AlertsFixtures.updates[1], old, AlertsFixtures.updates[0]])
        let updates = AlertUpdates(source: source, clock: FixedClock(now: AlertsFixtures.now), defaults: defaults)
        XCTAssertEqual(updates.updates.map(\.id), ["tapped"])

        await updates.refresh()
        XCTAssertEqual(updates.updates.map(\.id), ["delay", "tapped", "recovery"])

        // Cleared from Notification Center since: still listed, also after a relaunch.
        let relaunched = AlertUpdates(source: FixedDeliveredNotifications(), clock: FixedClock(now: AlertsFixtures.now), defaults: defaults)
        await relaunched.refresh()
        XCTAssertEqual(relaunched.updates.map(\.id), ["delay", "tapped", "recovery"])
    }
}
