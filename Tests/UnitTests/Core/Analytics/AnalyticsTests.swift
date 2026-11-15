import XCTest
@testable import TrainTimes

/// Anonymous product analytics (TT-208, D92): the events' names and properties, as `docs/ANALYTICS.md` lists them, and
/// a few of the places that send them.
@MainActor
final class AnalyticsTests: XCTestCase {
    override func tearDown() async throws {
        Analytics.tracker = nil
        try await super.tearDown()
    }

    func testTheTestHostSendsNothing() {
        XCTAssertNil(PostHogAnalytics.start(), "Debug builds, previews and tests never start PostHog")
    }

    func testRouteSetCarriesStationAndLineIdsOnly() {
        let route = Route(
            from: Station(id: "OA", name: "Oakville GO"), to: Station(id: "UN", name: "Union Station"),
            line: Line(id: "LW", name: "Lakeshore West", colorHex: nil)
        )
        let event = AnalyticsEvent.routeSet(route, isFirst: true)
        XCTAssertEqual(event.name, "route_set")
        XCTAssertEqual(event.properties, [
            "from": .string("OA"), "to": .string("UN"), "line": .string("LW"), "is_first": .bool(true)
        ])
    }

    func testRideEndReasonsAreSnakeCase() {
        XCTAssertEqual(AnalyticsEvent.rideEnded(.byRider).properties["reason"], .string("by_rider"))
        XCTAssertEqual(AnalyticsEvent.rideEnded(.leftTheLine).properties["reason"], .string("left_the_line"))
        XCTAssertEqual(AnalyticsEvent.rideEnded(.arrived).properties["reason"], .string("arrived"))
    }

    func testDayOffsetCountsFromToday() {
        let today = ServiceDay(year: 2026, month: 11, day: 1)
        XCTAssertEqual(today.days(to: today), 0)
        XCTAssertEqual(today.days(to: ServiceDay(year: 2026, month: 11, day: 3)), 2, "Across the end of daylight time")
        XCTAssertEqual(today.days(to: ServiceDay(year: 2026, month: 10, day: 25)), -7)
    }

    func testTimeFormatChangeIsTrackedOnce() {
        let recorder = RecordingAnalytics.install()
        let settings = AppSettings(defaults: .ephemeral())
        settings.timeFormat = .twentyFourHour
        settings.timeFormat = .twentyFourHour
        XCTAssertEqual(recorder.events, [.settingChanged("time_format", value: "twentyFourHour")])
    }

    func testSentFeedbackIsTrackedWithoutItsText() async {
        let recorder = RecordingAnalytics.install()
        let model = FeedbackViewModel(
            sender: RecordingFeedbackSender(),
            context: FeedbackContext(appVersion: "1.0 (45)", device: "iPhone18,1", osVersion: "26.1.0")
        )
        model.kind = .question
        model.message = "Does it cover Kitchener?"
        model.email = "rider@example.com"
        await model.send()
        XCTAssertEqual(recorder.events, [AnalyticsEvent("feedback_sent", ["kind": .string("question"), "with_email": .bool(true)])])
    }
}
