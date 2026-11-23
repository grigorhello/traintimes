import XCTest
@testable import TrainTimes

/// TT-242 (D120): the trains that could stand beside an alerted one at Oakville on Monday Nov 9, from the TT-130 feed
/// sample with tracks drawn for some of its trains, at the TT-131 TripUpdates replays' expected departures (7:00, 7:01 and
/// 7:02 AM) where they give one, else scheduled.
final class GTFSRivalTrainsTests: XCTestCase {
    private let monday = ServiceDay(year: 2026, month: 11, day: 9)
    private var directory: URL!

    /// Union to Oakville through the line's stations, as On board's fixture track, then on to Bronte.
    private static let westbound: [(Double, Double)] = [
        (43.645195, -79.380600), (43.641500, -79.399000), (43.635549, -79.418927), (43.627500, -79.458000),
        (43.616411, -79.497762), (43.604500, -79.522500), (43.591317, -79.546149), (43.574000, -79.567000),
        (43.555999, -79.586881), (43.535000, -79.611000), (43.513127, -79.633206), (43.455594, -79.682242),
        (43.416774, -79.722294),
    ]

    /// Tracks for the West Harbour trains out of Union and the Appleby, Hamilton and Confederation trains into it (the
    /// other way); the Aldershot trains (ALUN, UNAL) get none.
    private static let shapes: String = {
        var rows = ["shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence"]
        let tracks = [("UNWR", westbound)] + ["APUN", "HAUN", "CFUN"].map { ($0, Array(westbound.reversed())) }
        for (id, points) in tracks {
            for (index, point) in points.enumerated() { rows.append("\(id),\(point.0),\(point.1),\(index + 1)") }
        }
        return rows.joined(separator: "\n")
    }()

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        monday.date(hour: hour, minute: minute).addingTimeInterval(TimeInterval(second))
    }

    /// The sample with those tracks, kept as the store's copy on device (imported now, so no refresh replaces it).
    private func repository(_ replay: FeedReplay?, clock: TestClock) throws -> GTFSScheduleRepository {
        let archive = try ZipArchive(data: GTFSTimetableTests.sampleZip())
        let feed = try GTFSFeed(importedAt: clock.now) { name -> Data? in
            if name == "shapes.txt" { return Data(Self.shapes.utf8) }
            return try archive.data(named: name)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(feed).write(to: directory.appending(path: "feed.json"))
        return try .replaying(replay, clock: clock, directory: directory)
    }

    /// The rivals of an Oakville train ("LW-1858"), by train.
    private func rivals(_ repository: GTFSScheduleRepository, of train: String, around time: Date) async -> [RivalTrain] {
        let ride = Ride(trip: TripKey(serviceDay: monday, tripId: "20261109-\(train)"), from: "OA", to: "UN")
        return await repository.rivals(of: ride, around: time)
    }

    private func names(_ rivals: [RivalTrain]) -> [String] {
        rivals.map { String($0.trip.tripId.dropFirst(9)) }
    }

    func testScheduledTimesWithNoLiveFeed() async throws {
        let repository = try repository(nil, clock: TestClock(now: at(7, 0)))

        // The 7:21 Appleby train and the 7:21 West Harbour train leave together, either way: the rule tells the tracks apart.
        var found = await rivals(repository, of: "LW-1605", around: at(7, 21))
        XCTAssertEqual(names(found), ["LW-1108"], "Never the ride's own train")
        let rival = try XCTUnwrap(found.first)
        XCTAssertEqual(rival.departure, at(7, 21))
        let plan = try await repository.ridePlan(for: Ride(trip: rival.trip, from: "OA", to: "UN"))
        XCTAssertEqual(rival.shape, plan?.track?.shape)
        XCTAssertEqual(rival.originAlong, plan?.track?.stopDistances.first, "Oakville placed as its ride plan places it")
        XCTAssertEqual(rival.originAlong, 5_400, accuracy: 300, "Bronte to Oakville")
        found = await rivals(repository, of: "LW-1108", around: at(7, 21))
        XCTAssertEqual(names(found), ["LW-1605"])

        found = await rivals(repository, of: "LW-1858", around: at(7, 28))
        XCTAssertEqual(names(found), [], "The 7:21 trains are 7 min away")
        found = await rivals(repository, of: "LW-1858", around: at(7, 45))
        XCTAssertEqual(names(found), ["LW-1758"])
        found = await rivals(repository, of: "LW-1108", around: at(7, 15))
        XCTAssertEqual(names(found), [], "The 7:13 Aldershot train has no track")
    }

    func testLiveExpectedDepartures() async throws {
        let clock = TestClock(now: at(7, 0, 30))
        let replay = try FeedReplay("tripupdates-0700")
        let repository = try repository(replay, clock: clock)

        // 7:00: the 7:21 Appleby train is 5 min late, 2 min before the 7:28 Hamilton train and away from the 7:21.
        var found = await rivals(repository, of: "LW-1858", around: at(7, 28))
        XCTAssertEqual(names(found), ["LW-1108"])
        XCTAssertEqual(found.first?.departure, at(7, 26))
        found = await rivals(repository, of: "LW-1605", around: at(7, 21))
        XCTAssertEqual(names(found), [])

        // 7:01: 9 min late, it leaves 2 min after the Hamilton train, which is cancelled and so stands beside no one.
        try await replay.serve("tripupdates-0701")
        clock.advance(minutes: 1)
        found = await rivals(repository, of: "LW-1858", around: at(7, 28))
        XCTAssertEqual(found.map(\.departure), [at(7, 30)])
        found = await rivals(repository, of: "LW-1108", around: at(7, 30))
        XCTAssertEqual(names(found), [])

        // 7:02: the 7:44 Confederation train skips Oakville; the 7:51 Appleby train is 4 min late from Appleby on.
        try await replay.serve("tripupdates-0702")
        clock.advance(minutes: 1)
        found = await rivals(repository, of: "LW-1858", around: at(7, 45))
        XCTAssertEqual(names(found), [])
        found = await rivals(repository, of: "LW-1860", around: at(7, 57))
        XCTAssertEqual(names(found), ["LW-1308"])
        XCTAssertEqual(found.first?.departure, at(7, 55))
    }

    func testScheduledTimesWhileOfflineOrStale() async throws {
        let clock = TestClock(now: at(7, 0, 30))
        let replay = try FeedReplay("tripupdates-0700")
        let repository = try repository(replay, clock: clock)
        var found = await rivals(repository, of: "LW-1858", around: at(7, 28))
        XCTAssertEqual(found.map(\.departure), [at(7, 26)])

        await replay.goOffline()
        clock.advance(seconds: 20)
        found = await rivals(repository, of: "LW-1858", around: at(7, 28))
        XCTAssertEqual(names(found), [], "Offline: the 7:21 is at its scheduled time again")
        found = await rivals(repository, of: "LW-1605", around: at(7, 21))
        XCTAssertEqual(found.map(\.departure), [at(7, 21)])

        try await replay.serve("tripupdates-0700")
        clock.advance(seconds: 20)
        found = await rivals(repository, of: "LW-1858", around: at(7, 28))
        XCTAssertEqual(found.map(\.departure), [at(7, 26)])

        clock.advance(minutes: 3)
        found = await rivals(repository, of: "LW-1858", around: at(7, 28))
        XCTAssertEqual(names(found), [], "A feed over 3 min old is stale: scheduled times")
    }
}
