import XCTest
@testable import TrainTimes

/// Boarding at the platform (TT-233, D114): what the schedule reads from GO's feeds about a train at the route's origin.
/// How far the train feed places it from the station (never its `stopped` flag, which flickered to moving while a train
/// stood at Union), and whether the station has dropped out of the trip's TripUpdates. Oakville GO to Union Station GO on
/// the TT-131 samples, Monday Nov 9, 2026.
final class OriginSightingTests: XCTestCase {
    private let monday = ServiceDay(year: 2026, month: 11, day: 9)
    private let route = Route(from: Station(id: "OA", name: "Oakville GO"), to: Station(id: "UN", name: "Union Station GO"), line: nil)
    /// Leaves Oakville at 7:14 AM, on time in the 7:00 sample.
    private let train = "20261109-LW-1256"
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

    /// Oakville GO's place in the feed sample.
    private func oakville(_ repository: GTFSScheduleRepository) async throws -> GeoPoint {
        let stations = try await repository.stations()
        return try XCTUnwrap(stations.first { $0.id == "OA" }?.place)
    }

    /// `metres` north of `place`.
    private func north(of place: GeoPoint, metres: Double) -> GeoPoint {
        GeoPoint(latitude: place.latitude + metres / 111_195.08, longitude: place.longitude)
    }

    /// The alert server's `/v1/trains` with the 7:14 train at `point`, as the app reads it.
    private func relay(at point: GeoPoint, stopped: Bool, seen: Date, clock: TestClock) -> RelayTrainPositions {
        let time = Int(seen.timeIntervalSince1970)
        let body = Data("""
        {"timestamp":\(time),"trains":[
          {"tripId":"\(train)","startDate":"20261109","latitude":\(point.latitude),"longitude":\(point.longitude),"stopped":\(stopped),"timestamp":\(time)}
        ]}
        """.utf8)
        return RelayTrainPositions(clock: clock, download: { body })
    }

    private func departure(_ live: LiveSnapshot, _ repository: GTFSScheduleRepository, now: Date) async throws -> Departure {
        let trips = try await repository.trips(for: route, on: monday)
        let departures = Departure.resolve(trips, live: live, freshness: Freshness(live, now: now), isToday: true)
        return try XCTUnwrap(departures.first { $0.id.tripId == train })
    }

    func testATrainStandingAtTheOriginBoardsWhateverItsStoppedFlagSays() async throws {
        let clock = TestClock(now: at(7, 0, 30))
        var repository = try GTFSScheduleRepository.replaying(try FeedReplay("tripupdates-0700"), clock: clock, directory: directory)
        let place = try await oakville(repository)

        for stopped in [true, false] {
            repository.trains = relay(at: north(of: place, metres: 150), stopped: stopped, seen: at(7, 0, 20), clock: clock)
            var live = try await repository.liveStatus(for: route, on: monday)
            let fix = try XCTUnwrap(live.originFixes[train])
            XCTAssertEqual(fix.metres, 150, accuracy: 2)
            XCTAssertEqual(fix.reportedAt, at(7, 0, 20))
            XCTAssertEqual(live.originFixes.count, 1, "a train the feed does not carry gets no fix")
            XCTAssertFalse(live.leftOrigin.contains(train), "Oakville is still in its update")

            let waiting = try await departure(live, repository, now: clock.now)
            XCTAssertEqual(BoardingRule.phase(of: waiting, now: clock.now), .waiting, "no platform posted yet")
            live.platforms[train] = "3"
            let boarding = try await departure(live, repository, now: clock.now)
            XCTAssertEqual(BoardingRule.phase(of: boarding, now: clock.now), .boarding, "stopped: \(stopped)")
        }
    }

    func testATrainAwayFromTheOriginIsRollingInUntilItsTimeThenHasLeft() async throws {
        let clock = TestClock(now: at(7, 0, 30))
        var repository = try GTFSScheduleRepository.replaying(try FeedReplay("tripupdates-0700"), clock: clock, directory: directory)
        let place = try await oakville(repository)
        let away = north(of: place, metres: 900)
        repository.trains = relay(at: away, stopped: false, seen: at(7, 0, 20), clock: clock)

        var live = try await repository.liveStatus(for: route, on: monday)
        XCTAssertEqual(try XCTUnwrap(live.originFixes[train]).metres, 900, accuracy: 5)
        let rolling = try await departure(live, repository, now: clock.now)
        XCTAssertEqual(BoardingRule.phase(of: rolling, now: clock.now), .waiting, "14 min before its time it is still rolling in")

        // 7:14:10, the train feed placed it away from the station 5 s ago.
        clock.advance(seconds: 13 * 60 + 40)
        repository.trains = relay(at: away, stopped: false, seen: at(7, 14, 5), clock: clock)
        live = try await repository.liveStatus(for: route, on: monday)
        let gone = try await departure(live, repository, now: clock.now)
        XCTAssertEqual(BoardingRule.phase(of: gone, now: clock.now), .departed(.moved))
    }

    func testOnlyTrainsNearTheirTimeAreLookedUp() async throws {
        let clock = TestClock(now: at(7, 0, 30))
        var repository = try GTFSScheduleRepository.replaying(try FeedReplay("tripupdates-0700"), clock: clock, directory: directory)
        let place = try await oakville(repository)
        // A feed that places every train it is asked about at the station.
        let everywhere = FakeTrainPositions()
        await everywhere.set(TrainPosition(coordinate: place, reportedAt: at(7, 0, 20)))
        repository.trains = everywhere

        let live = try await repository.liveStatus(for: route, on: monday)
        let trips = try await repository.trips(for: route, on: monday)
        let near = trips.filter { trip in
            let until = trip.scheduledDeparture.timeIntervalSince(clock.now)
            return until <= GTFSScheduleRepository.sightingLead && until >= -GTFSScheduleRepository.sightingTail
        }
        XCTAssertEqual(Set(live.originFixes.keys), Set(near.map(\.key.tripId)))
        XCTAssertFalse(near.isEmpty)
        XCTAssertLessThan(near.count, trips.count, "the rest of the day is not looked up")
        XCTAssertEqual(try XCTUnwrap(live.originFixes[train]).metres, 0, accuracy: 1)
    }

    func testWithoutATrainFeedThereAreNoFixes() async throws {
        let clock = TestClock(now: at(7, 0, 30))
        let repository = try GTFSScheduleRepository.replaying(try FeedReplay("tripupdates-0700"), clock: clock, directory: directory)
        let live = try await repository.liveStatus(for: route, on: monday)
        XCTAssertTrue(live.originFixes.isEmpty)
    }

    func testFixesAreDroppedOfflineAndOnAnotherDay() async throws {
        let scheduled = at(7, 14)
        let trip = Trip(
            key: TripKey(serviceDay: monday, tripId: train), scheduledDeparture: scheduled,
            scheduledArrival: scheduled.addingTimeInterval(34 * 60), platform: .pending, tags: []
        )
        var live = LiveSnapshot(updatedAt: at(7, 0))
        live.originFixes[train] = OriginFix(metres: 120, reportedAt: at(7, 0))
        live.leftOrigin = [train]

        let today = Departure.resolve([trip], live: live, freshness: .live(updatedAt: at(7, 0)), isToday: true)
        XCTAssertEqual(today.first?.originFix?.metres, 120)
        XCTAssertEqual(today.first?.hasLeftOrigin, true)
        let otherDay = Departure.resolve([trip], live: live, freshness: .live(updatedAt: at(7, 0)), isToday: false)
        XCTAssertNil(otherDay.first?.originFix)
        XCTAssertEqual(otherDay.first?.hasLeftOrigin, false)
        let offline = Departure.resolve([trip], live: live, freshness: .offline(lastUpdated: at(7, 0)), isToday: true)
        XCTAssertNil(offline.first?.originFix, "offline nothing is guessed: the clock")
        XCTAssertEqual(offline.first?.hasLeftOrigin, false)
    }

    // MARK: The station dropping out of TripUpdates (D89)

    /// The trip from Clarkson to Aldershot, ridden from Oakville (OA).
    private var call: GTFSTimetable.Call {
        let times = [at(19, 53), at(20, 0), at(20, 6), at(20, 12), at(20, 19), at(20, 27)]
        return GTFSTimetable.Call(
            tripId: "20261109-LW-1031", stops: ["CL", "OA", "BO", "AP", "BU", "AL"], arrivals: times, departures: times, from: 1, to: 5
        )
    }

    private func update(_ stops: [String], isCancelled: Bool = false) -> GTFSRealtimeFeed.TripUpdate {
        GTFSRealtimeFeed.TripUpdate(
            tripId: "20261109-LW-1031", isCancelled: isCancelled,
            stopTimeUpdates: stops.map { GTFSRealtimeFeed.StopTimeUpdate(stopId: $0, departure: .init(delay: 0)) }
        )
    }

    func testATrainHasLeftTheOriginWhenOnlyLaterStopsAreListed() {
        XCTAssertFalse(update(["CL", "OA", "BO", "AP", "BU", "AL"]).hasLeft(call), "not left Clarkson yet")
        XCTAssertFalse(update(["OA", "BO", "AP", "BU", "AL"]).hasLeft(call), "Oakville is still ahead")
        XCTAssertTrue(update(["BO", "AP", "BU", "AL"]).hasLeft(call))
        XCTAssertTrue(update(["AL"]).hasLeft(call))
        XCTAssertFalse(update([]).hasLeft(call), "an update with no stops says nothing")
        XCTAssertFalse(update(["XX"]).hasLeft(call), "nor one with only stops of another trip")
        XCTAssertFalse(update(["BO", "AP", "BU", "AL"], isCancelled: true).hasLeft(call), "a cancelled trip never leaves")
    }
}
