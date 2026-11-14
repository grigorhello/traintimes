import XCTest
@testable import TrainTimes

/// TT-132 feed replay (D37): GTFS-realtime Alerts samples written with the official protobuf bindings
/// (`scripts/make-realtime-samples.py`) for real GO routes in the TT-130 feed sample, read at 7:02 and 7:05 AM on Monday
/// Nov 9, 2026. They stand in for GO's Alerts feed until the Metrolinx key arrives (Q5).
final class LineNoticeReplayTests: XCTestCase {
    private let monday = ServiceDay(year: 2026, month: 11, day: 9)
    private let lakeshore = Line(id: "LW", name: "Lakeshore West", colorHex: "#98002e")
    private let kitchener = Line(id: "KI", name: "Kitchener", colorHex: "#00853e")
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        monday.date(hour: hour, minute: minute).addingTimeInterval(TimeInterval(second))
    }

    func testDecodesTheAlerts() throws {
        let feed = try GTFSRealtimeFeed(protobuf: FeedReplay.sample("alerts-0702"))
        XCTAssertEqual(feed.timestamp, at(7, 2))
        XCTAssertTrue(feed.tripUpdates.isEmpty)
        XCTAssertEqual(feed.alerts.map(\.id), ["LW-1001", "KI-2001", "OA-3001", "TRIP-4001", "LW-0900", "LW-0901"])
        let notice = try XCTUnwrap(feed.alerts.first)
        XCTAssertEqual(notice.header, "Delays of up to 15 min near Port Credit", "English, not the French translation listed first")
        XCTAssertEqual(notice.description?.hasPrefix("Trains are moving slowly"), true)
        XCTAssertEqual(notice.activePeriods, [GTFSRealtimeFeed.ActivePeriod(start: at(7, 0), end: nil)])
        XCTAssertEqual(notice.informedEntities, [GTFSRealtimeFeed.InformedEntity(routeId: "09261126-LW", stopId: "PO", hasTrip: false)])
        XCTAssertEqual(feed.alerts[3].informedEntities.first?.hasTrip, true)
    }

    /// A notice reaches only its own line, while it is active; a station or trip alert is not a line notice.
    func testScopesNoticesToTheLine() async throws {
        let clock = TestClock(now: at(7, 2, 30))
        let repository = try GTFSScheduleRepository.replaying(nil, alerts: FeedReplay("alerts-0702"), clock: clock, directory: directory)

        let notices = try await repository.lineNotices(for: lakeshore)
        XCTAssertEqual(notices.map(\.id), ["LW-1001"], "Not the station, trip, ended or later notices")
        XCTAssertEqual(notices.first?.lineName, "Lakeshore West")
        XCTAssertEqual(notices.first?.text, "Delays of up to 15 min near Port Credit")
        XCTAssertEqual(notices.first?.details?.hasSuffix("Allow extra travel time."), true)
        XCTAssertEqual(notices.first?.reportedAt, at(7, 0), "The start of its active period")

        let kitchenerNotices = try await repository.lineNotices(for: kitchener)
        XCTAssertEqual(kitchenerNotices.map(\.id), ["KI-2001"], "Route 09261126-GT is the Kitchener line")
    }

    func testRouteCodeIgnoresTheSchedulePeriod() {
        XCTAssertEqual(GTFSFeed.routeCode("09261126-LW"), "LW")
        XCTAssertEqual(GTFSFeed.routeCode("11271231-LW"), "LW")
        XCTAssertEqual(GTFSFeed.routeCode("LW"), "LW")
    }

    /// No key, no Alerts feed: no notices, as before TT-132.
    func testNoAlertsFeedHasNoNotices() async throws {
        let repository = try GTFSScheduleRepository.replaying(nil, clock: TestClock(now: at(7, 2)), directory: directory)
        let notices = try await repository.lineNotices(for: lakeshore)
        XCTAssertTrue(notices.isEmpty)
    }

    /// A notice alone never marks a trip cancelled, even one that says so with NO_SERVICE (TRIP-4001 for the 7:21 AM
    /// train): only TripUpdates change a status.
    func testANoticeAloneNeverMarksATripCancelled() async throws {
        let route = Route(from: Station(id: "OA", name: "Oakville GO"), to: Station(id: "UN", name: "Union Station GO"), line: lakeshore)
        let clock = TestClock(now: at(7, 2, 30))
        let key = TripKey(serviceDay: monday, tripId: "20261109-LW-1108")

        let alertsOnly = try GTFSScheduleRepository.replaying(nil, alerts: FeedReplay("alerts-0702"), clock: clock, directory: directory)
        let trips = try await alertsOnly.trips(for: route, on: monday)
        let noLive = try await alertsOnly.liveStatus(for: route, on: monday)
        let notices = try await alertsOnly.lineNotices(for: lakeshore)
        XCTAssertFalse(notices.isEmpty)
        XCTAssertEqual(noLive, .empty)
        let scheduled = Departure.resolve(trips, live: noLive, freshness: Freshness(noLive, now: clock.now), isToday: true)
        XCTAssertFalse(scheduled.isEmpty)
        XCTAssertTrue(scheduled.allSatisfy { $0.status == .scheduled })

        let withLive = try GTFSScheduleRepository.replaying(
            FeedReplay("tripupdates-0700"), alerts: FeedReplay("alerts-0702"), clock: clock, directory: directory
        )
        let live = try await withLive.liveStatus(for: route, on: monday)
        let departures = Departure.resolve(trips, live: live, freshness: Freshness(live, now: clock.now), isToday: true)
        XCTAssertEqual(departures.first { $0.id == key }?.status, .delayed(minutes: 5, reportedAt: at(7, 0)))
        XCTAssertFalse(departures.contains { if case .cancelled = $0.status { true } else { false } })
    }

    /// GO's real Alerts feed (D90), modelled in `alerts-go-real.pb`: every informed entity sets agency, route, route
    /// type and stop, the unused ones empty; a line notice names its route with an empty stop, and its active period
    /// starts when GO posted it. Station and trip alerts, a bus route and other lines are not Lakeshore West notices.
    func testRealGoFeedScopesNoticesToTheLine() async throws {
        let feed = try GTFSRealtimeFeed(protobuf: FeedReplay.sample("alerts-go-real"))
        XCTAssertEqual(feed.alerts.first?.informedEntities, [GTFSRealtimeFeed.InformedEntity(routeId: "09261126-LW", stopId: "", hasTrip: false)])

        let clock = TestClock(now: at(7, 2, 30))
        let repository = try GTFSScheduleRepository.replaying(nil, alerts: FeedReplay("alerts-go-real"), clock: clock, directory: directory)
        let notices = try await repository.lineNotices(for: lakeshore)
        XCTAssertEqual(notices.map(\.id), ["532843", "533119"])
        XCTAssertEqual(notices.first?.text, "Lakeshore West - Track speed reductions")
        XCTAssertEqual(notices.first?.reportedAt, ServiceDay(year: 2026, month: 11, day: 7).date(hour: 13, minute: 57))
        XCTAssertEqual(notices.last?.reportedAt, at(6, 40))

        let kitchenerNotices = try await repository.lineNotices(for: kitchener)
        XCTAssertEqual(kitchenerNotices.map(\.id), ["532102"], "Named with Barrie, by route GT")
    }
}
