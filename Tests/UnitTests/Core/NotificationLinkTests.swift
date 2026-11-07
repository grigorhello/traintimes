import XCTest
@testable import TrainTimes

private final class BundleToken {}

/// Notification taps (TT-144): the alert server's payload (D38) and where a tap lands (rule 10).
final class NotificationLinkTests: XCTestCase {
    private let thursday = ServiceDay(year: 2026, month: 11, day: 5)
    private let key = TripKey(serviceDay: ServiceDay(year: 2026, month: 11, day: 5), tripId: "LW-0758-20261105")

    /// The payload `server/src/monitor.ts` sends beside `aps`.
    func testTripPayload() {
        let link = NotificationLink(userInfo: [
            "aps": ["sound": "default"],
            "tripId": "LW-0758-20261105", "serviceDate": "20261105", "originId": "OA", "destinationId": "UN",
        ])
        XCTAssertEqual(link, .trip(key, originId: "OA", destinationId: "UN"))
    }

    func testTripPayloadWithoutStations() {
        XCTAssertEqual(
            NotificationLink(userInfo: ["tripId": "LW-0758-20261105", "serviceDate": "2026-11-05"]),
            .trip(key, originId: nil, destinationId: nil)
        )
    }

    func testRulePayload() {
        XCTAssertEqual(NotificationLink(userInfo: ["ruleId": "r1"]), .rule(id: "r1"))
    }

    func testOtherPayloadsOpenNothing() {
        XCTAssertNil(NotificationLink(userInfo: [:]))
        XCTAssertNil(NotificationLink(userInfo: ["tripId": "LW-0758-20261105"]))
        XCTAssertNil(NotificationLink(userInfo: ["tripId": "LW-0758-20261105", "serviceDate": "tomorrow"]))
        XCTAssertNil(NotificationLink(userInfo: ["tripId": "LW-0758-20261105", "serviceDate": "20261341"]))
        XCTAssertNil(NotificationLink(json: "not json"))
    }

    func testJSONPayload() {
        XCTAssertEqual(
            NotificationLink(json: #"{"tripId":"LW-0758-20261105","serviceDate":"20261105","originId":"OA","destinationId":"UN"}"#),
            .trip(key, originId: "OA", destinationId: "UN")
        )
    }

    func testTodayOpensTheTrip() {
        let link = NotificationLink.trip(key, originId: "OA", destinationId: "UN")
        XCTAssertEqual(link.target(today: thursday), .trip(key))
    }

    func testPastServiceDateOpensAlerts() {
        let link = NotificationLink.trip(key, originId: "OA", destinationId: "UN")
        XCTAssertEqual(link.target(today: thursday.adding(days: 1)), .alerts)
    }

    func testRuleOpensAlerts() {
        XCTAssertEqual(NotificationLink.rule(id: "r1").target(today: thursday), .alerts)
    }

    /// The alert's stations win over the saved route, so the trip opens on the route it is watched on.
    func testRouteFromTheAlertsStations() async throws {
        let fixture = try FixtureScheduleRepository(bundle: Bundle(for: BundleToken.self))
        let saved = Route(from: fixture.route.to, to: fixture.route.from, line: fixture.route.line)
        let route = await NotificationLink.trip(key, originId: "OA", destinationId: "UN").route(stations: fixture, saved: saved)
        XCTAssertEqual(route?.from.id, "OA")
        XCTAssertEqual(route?.to.id, "UN")
        XCTAssertEqual(route?.line?.id, "LW")
    }

    func testUnknownStationsFallBackToTheSavedRoute() async throws {
        let fixture = try FixtureScheduleRepository(bundle: Bundle(for: BundleToken.self))
        let link = NotificationLink.trip(key, originId: "XX", destinationId: "UN")
        let route = await link.route(stations: fixture, saved: fixture.route)
        XCTAssertEqual(route, fixture.route)
        let noStations = await NotificationLink.trip(key, originId: nil, destinationId: nil).route(stations: fixture, saved: nil)
        XCTAssertNil(noStations)
    }
}
