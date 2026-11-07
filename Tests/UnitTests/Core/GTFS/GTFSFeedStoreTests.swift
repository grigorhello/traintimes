import XCTest
@testable import TrainTimes

/// TT-130: the feed is downloaded on first use and kept on device, so the timetable shows offline after one import.
final class GTFSFeedStoreTests: XCTestCase {
    private var directory: URL!
    private let route = Route(from: Station(id: "OA", name: "Oakville GO"), to: Station(id: "UN", name: "Union Station GO"), line: nil)
    private let monday = ServiceDay(year: 2026, month: 11, day: 9)
    private let clock = FixedClock(now: ISO8601DateFormatter().date(from: "2026-11-09T12:21:00Z")!)
    private let offline: GTFSFeedStore.Download = { throw URLError(.notConnectedToInternet) }

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func store(_ download: @escaping GTFSFeedStore.Download) -> GTFSFeedStore {
        GTFSFeedStore(directory: directory, clock: clock, download: download)
    }

    /// Acceptance: airplane mode after one import still shows the timetable.
    func testOneImportWorksOffline() async throws {
        let zip = try GTFSTimetableTests.sampleZip()
        let online = GTFSScheduleRepository(store: store { zip })
        let stations = try await online.stations()
        XCTAssertEqual(stations.count, 29)

        // A later launch with no network reads the copy on device.
        let repository = GTFSScheduleRepository(store: store(offline))
        let trips = try await repository.trips(for: route, on: monday)
        XCTAssertEqual(trips.count, 46)
        let lastDay = try await repository.lastServiceDay()
        XCTAssertEqual(lastDay, ServiceDay(year: 2026, month: 11, day: 27))
        let line = try await repository.route(from: route.from, to: route.to).line
        XCTAssertEqual(line?.name, "Lakeshore West")
        let stops = try await repository.stops(for: TripKey(serviceDay: monday, tripId: "20261109-LW-1858"), on: route)
        XCTAssertEqual(stops.map(\.station.id), ["OA", "CL", "UN"])
        let live = try await repository.liveStatus(for: route, on: monday)
        XCTAssertEqual(live, .empty, "Scheduled only until GTFS-realtime (TT-131)")
    }

    func testFirstUseWithNoNetworkHasNoTimetable() async {
        do {
            _ = try await store(offline).timetable()
            XCTFail("There is nothing to show yet")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }

    func testAFailedRefreshKeepsTheLastGoodCopy() async throws {
        let zip = try GTFSTimetableTests.sampleZip()
        _ = try await store { zip }.timetable()

        let failing = store(offline)
        _ = try await failing.timetable()
        do {
            try await failing.refresh()
            XCTFail("The refresh has no network")
        } catch {}
        let timetable = try await failing.timetable()
        XCTAssertEqual(timetable.trips(from: "OA", to: "UN", on: monday).count, 46)
    }

    /// A copy that has run out would show no trains, so the first call after it waits for the new feed; offline it
    /// still answers with the copy.
    func testARunOutCopyWaitsForTheNewFeed() async throws {
        let zip = try GTFSTimetableTests.sampleZip()
        _ = try await store { zip }.timetable()
        // Mon Nov 30, after the feed's last service day (Fri Nov 27).
        let later = FixedClock(now: clock.now.addingTimeInterval(21 * 86_400))

        let offlineTimetable = try await GTFSFeedStore(directory: directory, clock: later, download: offline).timetable()
        XCTAssertEqual(offlineTimetable.feed.importedAt, clock.now, "Offline keeps the copy")

        let online = GTFSFeedStore(directory: directory, clock: later, download: { zip })
        let timetable = try await online.timetable()
        XCTAssertEqual(timetable.feed.importedAt, later.now, "Waited for the new import")
    }

    func testRefreshIsDueWeeklyOrWhenTheFeedRunsOut() throws {
        let imported = clock.now
        let timetable = GTFSTimetable(feed: try GTFSFeed(zip: GTFSTimetableTests.sampleZip(), importedAt: imported))
        XCTAssertFalse(GTFSFeedStore.isDue(timetable, now: imported.addingTimeInterval(6 * 86_400)))
        XCTAssertTrue(GTFSFeedStore.isDue(timetable, now: imported.addingTimeInterval(7 * 86_400)))
        // The feed's last service day is Fri Nov 27: on Nov 28 it no longer covers today, whatever its age.
        let late = GTFSTimetable(feed: try GTFSFeed(zip: GTFSTimetableTests.sampleZip(), importedAt: imported.addingTimeInterval(17 * 86_400)))
        XCTAssertFalse(GTFSFeedStore.isDue(late, now: imported.addingTimeInterval(18 * 86_400)), "Fri Nov 27")
        XCTAssertTrue(GTFSFeedStore.isDue(late, now: imported.addingTimeInterval(19 * 86_400)), "Sat Nov 28")
    }
}
