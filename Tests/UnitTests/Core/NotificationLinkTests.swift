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

    // MARK: - traintimes:// links (TT-182, D107)

    private func link(_ string: String, today: ServiceDay? = nil) -> NotificationLink? {
        NotificationLink(url: URL(string: string)!, today: today ?? thursday)
    }

    func testTripLink() {
        XCTAssertEqual(
            link("traintimes://trip?tripId=LW-0758-20261105&serviceDate=20261105&originId=OA&destinationId=UN&source=widget&widget=next"),
            .trip(key, originId: "OA", destinationId: "UN")
        )
        XCTAssertEqual(link("traintimes://trip?tripId=LW-0758-20261105&serviceDate=20261105"), .trip(key, originId: nil, destinationId: nil))
    }

    /// A widget's train from a past service day opens Schedule at Now on its route, not the Alerts tab.
    func testPastTripLinkOpensItsRoute() {
        let past = link("traintimes://trip?tripId=LW-0758-20261105&serviceDate=20261105&originId=OA&destinationId=UN", today: thursday.adding(days: 1))
        XCTAssertEqual(past, .route(originId: "OA", destinationId: "UN"))
        XCTAssertEqual(past?.target(today: thursday.adding(days: 1)), .schedule)
    }

    func testRouteLinks() {
        let route = link("traintimes://route?originId=UN&destinationId=OA")
        XCTAssertEqual(route, .route(originId: "UN", destinationId: "OA"))
        XCTAssertEqual(route?.target(today: thursday), .schedule)
        XCTAssertEqual(route?.hasStations, true)
        let tab = link("traintimes://route")
        XCTAssertEqual(tab, .route(originId: nil, destinationId: nil))
        XCTAssertEqual(tab?.hasStations, false)
    }

    func testMalformedLinksOpenNothing() {
        XCTAssertNil(link("traintimes://trip?tripId=LW-0758-20261105"))
        XCTAssertNil(link("traintimes://trip?serviceDate=20261105"))
        XCTAssertNil(link("traintimes://trip?tripId=LW-0758-20261105&serviceDate=soon"))
        XCTAssertNil(link("traintimes://trip?ruleId=r1"))
        XCTAssertNil(link("traintimes://station?id=OA"))
        XCTAssertNil(link("traintimes://route/extra"))
        XCTAssertNil(link("https://traintimes.ca/route"))
        // The Live Activity's links are not these.
        XCTAssertNil(link("traintimes://ride"))
    }

    /// The links a widget makes read back as the same train and route.
    func testWidgetLinksRoundTrip() {
        let route = WidgetFile.RouteKey(fromId: "OA", toId: "UN")
        XCTAssertEqual(NotificationLink(url: WidgetLink.trip(key, route: route), today: thursday), .trip(key, originId: "OA", destinationId: "UN"))
        XCTAssertEqual(NotificationLink(url: WidgetLink.route(route), today: thursday), .route(originId: "OA", destinationId: "UN"))
        XCTAssertEqual(NotificationLink(url: WidgetLink.route(nil), today: thursday), .route(originId: nil, destinationId: nil))
    }

    func testRouteLinkOpensOnItsStations() async throws {
        let fixture = try FixtureScheduleRepository(bundle: Bundle(for: BundleToken.self))
        let route = await NotificationLink.route(originId: "UN", destinationId: "OA").route(stations: fixture, saved: fixture.route)
        XCTAssertEqual(route?.from.id, "UN")
        XCTAssertEqual(route?.to.id, "OA")
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
