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
        XCTAssertEqual(AnalyticsEvent.rideEnded(.byRider).properties["at_stop"], .bool(false))
        XCTAssertEqual(AnalyticsEvent.rideEnded(.byRider, atStop: true).properties["at_stop"], .bool(true))
        XCTAssertEqual(AnalyticsEvent.rideEnded(.arrived, watchedSeconds: 95, opens: 2).properties["watched_seconds"], .int(95))
        XCTAssertEqual(AnalyticsEvent.rideEnded(.arrived, watchedSeconds: 95, opens: 2).properties["opens"], .int(2))
    }

    func testLaunchSplashEnded() {
        let event = AnalyticsEvent.launchSplashEnded(scheduleReady: true, full: false)
        XCTAssertEqual(event.name, "launch_splash_ended")
        XCTAssertEqual(event.properties, ["schedule_ready": .bool(true), "full": .bool(false)])
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

    // MARK: - TT-217: a saved route counted at launch, offline views

    private let oakville = Route(
        from: Station(id: "OA", name: "Oakville GO"), to: Station(id: "UN", name: "Union Station"),
        line: Line(id: "LW", name: "Lakeshore West", colorHex: nil)
    )

    func testASavedRouteIsCountedOnceAtLaunch() {
        let recorder = RecordingAnalytics.install()
        let count = RouteCount(defaults: .ephemeral())
        count.launched(with: oakville)
        count.launched(with: oakville)
        XCTAssertEqual(recorder.events, [.routeSet(oakville, isFirst: true, restored: true)])
        XCTAssertEqual(recorder.events.first?.properties["restored"], .bool(true))
        XCTAssertNil(AnalyticsEvent.routeSet(oakville, isFirst: false).properties["restored"], "Only the launch count says restored")
    }

    func testNoRouteAtLaunchSendsNothing() {
        let recorder = RecordingAnalytics.install()
        RouteCount(defaults: .ephemeral()).launched(with: nil)
        XCTAssertEqual(recorder.events, [])
    }

    func testARunWithoutAnalyticsLeavesTheRouteUncounted() {
        let defaults = UserDefaults.ephemeral()
        RouteCount(defaults: defaults).launched(with: oakville)
        XCTAssertFalse(defaults.bool(forKey: RouteCount.key), "A Debug run never marks the install")
        let recorder = RecordingAnalytics.install()
        RouteCount(defaults: defaults).launched(with: oakville)
        XCTAssertEqual(recorder.names, ["route_set"])
    }

    func testARouteSetInTheAppIsNotCountedAgainAtLaunch() async {
        let recorder = RecordingAnalytics.install()
        let defaults = UserDefaults.ephemeral()
        let model = ScheduleViewModel(
            route: nil, repository: OfflineTimetable(), clock: FixedClock(now: .now), routeCount: RouteCount(defaults: defaults)
        )
        await model.show(oakville)
        RouteCount(defaults: defaults).launched(with: oakville)
        XCTAssertEqual(recorder.events, [.routeSet(oakville, isFirst: true)])
    }

    func testOfflineScheduleIsTrackedOncePerTurn() async throws {
        let recorder = RecordingAnalytics.install()
        let model = try await ScheduleViewModel.loadedFixture(.offline)
        await model.retry()
        XCTAssertEqual(recorder.events, [.offlineShown(.live)], "A refresh that stays offline sends nothing more")
    }

    func testATimetableThatCannotDownloadIsTracked() async {
        let model = ScheduleViewModel(route: oakville, repository: OfflineTimetable(), clock: FixedClock(now: .now))
        let recorder = RecordingAnalytics.install()
        await model.loadIfNeeded()
        XCTAssertEqual(model.content, .failed)
        XCTAssertEqual(recorder.events, [AnalyticsEvent("offline_shown", ["kind": .string("timetable")])])
    }

    /// No timetable on device and none can be downloaded.
    private struct OfflineTimetable: ScheduleRepository {
        func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] { throw URLError(.notConnectedToInternet) }
        func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot { .empty }
        func lineNotices(for line: Line) async throws -> [LineNotice] { [] }
    }
}
