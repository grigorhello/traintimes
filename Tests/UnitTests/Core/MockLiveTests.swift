import XCTest
@testable import TrainTimes

/// TT-195: Settings › Testing › Live data puts a made-up live feed on the real timetable, through the same repository path
/// as the real feed, so the live states show on a phone before the Metrolinx key arrives.
@MainActor
final class MockLiveTests: XCTestCase {
    private func make(
        _ live: MockLive, demo: DemoTrains = .off, now: Date? = nil
    ) throws -> (repository: DemoScheduleRepository, base: FixtureScheduleRepository, now: Date) {
        let base = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let now = now ?? base.now
        let repository = DemoScheduleRepository(
            base: base, clock: FixedClock(now: now), mode: { demo }, isMockTime: { true }, mockLive: { live }
        )
        return (repository, base, now)
    }

    private func resolved(_ live: MockLive, now: Date? = nil) async throws -> (departures: [Departure], freshness: Freshness) {
        let (repository, base, now) = try make(live, now: now)
        let trips = try await repository.trips(for: base.route, on: base.serviceDay)
        let snapshot = try await repository.liveStatus(for: base.route, on: base.serviceDay)
        let freshness = Freshness(snapshot, now: now)
        return (Departure.resolve(trips, live: snapshot, freshness: freshness, isToday: true), freshness)
    }

    /// On time: every train live and on time, with fresh data, even with Mock time on.
    func testOnTimeIsEveryTrainLiveAndOnTime() async throws {
        let (departures, freshness) = try await resolved(.onTime)
        XCTAssertTrue(freshness.isLive)
        XCTAssertEqual(departures.count, 4)
        XCTAssertTrue(departures.allSatisfy { $0.status == .onTime && $0.expectedDeparture == $0.trip.scheduledDeparture })
    }

    /// Mixed: late 4 min, cancelled, on time, late 22 min on the next four trains, platforms posted and a line notice.
    func testMixedShowsEveryStateOnTheNextTrains() async throws {
        let (departures, freshness) = try await resolved(.mixed)
        XCTAssertTrue(freshness.isLive)
        let byTime = departures.sorted { $0.trip.scheduledDeparture < $1.trip.scheduledDeparture }
        guard case .delayed(4, _) = byTime[0].status else { return XCTFail("Expected 4 min late, got \(byTime[0].status)") }
        guard case .cancelled = byTime[1].status else { return XCTFail("Expected cancelled, got \(byTime[1].status)") }
        XCTAssertEqual(byTime[2].status, .onTime)
        guard case .delayed(22, _) = byTime[3].status else { return XCTFail("Expected 22 min late, got \(byTime[3].status)") }
        XCTAssertTrue(departures.allSatisfy { if case .published = $0.trip.platform { true } else { false } })

        let (repository, base, _) = try make(.mixed)
        let notices = try await repository.lineNotices(for: try XCTUnwrap(base.route.line))
        XCTAssertEqual(notices.count, 1)
    }

    /// Mixed: the fifth train skips your stop.
    func testMixedSkipsTheStopOnTheFifthTrain() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let trips = (0..<6).map { index in
            Trip(
                key: TripKey(serviceDay: ServiceDay(year: 2026, month: 11, day: 5), tripId: "T\(index)"),
                scheduledDeparture: now.addingTimeInterval(TimeInterval(index + 1) * 600),
                scheduledArrival: now.addingTimeInterval(TimeInterval(index + 1) * 600 + 1800),
                platform: .pending, tags: []
            )
        }
        let live = MockLiveFeed.snapshot(.mixed, trips: trips, now: now)
        XCTAssertEqual(live.updates["T4"]?.isStopSkipped, true)
        XCTAssertEqual(live.updates["T5"]?.expectedDeparture, trips[5].scheduledDeparture, "Later trains run on time")
    }

    /// Changing: the next train's delay follows the clock's minute, so each refresh can show a new one.
    func testChangingMovesTheNextTrainsDelayEachMinute() async throws {
        let base = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let start = (base.now.timeIntervalSince1970 / 60).rounded(.down) * 60
        var delays: [Int] = []
        for minute in 0..<4 {
            let now = Date(timeIntervalSince1970: start + TimeInterval(minute * 60))
            let (departures, _) = try await resolved(.changing, now: now)
            let next = try XCTUnwrap(departures.min { $0.trip.scheduledDeparture < $1.trip.scheduledDeparture })
            if case .delayed(let minutes, _) = next.status { delays.append(minutes) } else { delays.append(0) }
        }
        XCTAssertEqual(Set(delays), Set(MockLiveFeed.changingDelays))
    }

    /// Stale: reported 8 min ago, so the late train reads Scheduled and the data mode is Last reported.
    func testStaleFallsBackToScheduled() async throws {
        let (departures, freshness) = try await resolved(.stale)
        guard case .stale = freshness else { return XCTFail("Expected stale, got \(freshness)") }
        XCTAssertTrue(departures.allSatisfy { $0.status == .scheduled })
    }

    /// Trip details' stops carry the delay, so the stop list reads Expected.
    func testStopsCarryTheDelay() async throws {
        let (repository, base, _) = try make(.mixed)
        let trips = try await base.trips(for: base.route, on: base.serviceDay).sorted { $0.scheduledDeparture < $1.scheduledDeparture }
        let stops = try await repository.stops(for: trips[0].key, on: base.route)
        XCTAssertFalse(stops.isEmpty)
        XCTAssertTrue(stops.allSatisfy { $0.expected == $0.scheduled.addingTimeInterval(4 * 60) })
    }

    /// Demo trains Delays, Offline and Platform make their own live status and win over Live data.
    func testDemoTrainsThatMakeLiveStatusWin() async throws {
        let (repository, base, _) = try make(.onTime, demo: .offline)
        let live = try await repository.liveStatus(for: base.route, on: base.serviceDay)
        XCTAssertTrue(live.isOffline)
    }

    // MARK: Board (TT-233, D114)

    /// Board: every train live and on time with its platform posted, and the next one stands at its platform, so the
    /// boarding rule reads Boarding at once, here 11 min before its time.
    func testBoardStandsTheNextTrainAtItsPlatform() async throws {
        let (repository, base, now) = try make(.boarding)
        let trips = try await repository.trips(for: base.route, on: base.serviceDay)
        let live = try await repository.liveStatus(for: base.route, on: base.serviceDay)
        let freshness = Freshness(live, now: now)
        XCTAssertTrue(freshness.isLive)
        let departures = Departure.resolve(trips, live: live, freshness: freshness, isToday: true)
        XCTAssertEqual(departures.count, 4)
        XCTAssertTrue(departures.allSatisfy { $0.status == .onTime && $0.hasPostedPlatform })

        let next = try XCTUnwrap(departures.first)
        let atPlatform = OriginFix(metres: MockLiveFeed.boardingMetres, reportedAt: now)
        XCTAssertEqual(live.originFixes, [next.id.tripId: atPlatform], "one train stands at the station")
        XCTAssertEqual(next.originFix, atPlatform)
        XCTAssertLessThanOrEqual(MockLiveFeed.boardingMetres, BoardingRule.radius)
        XCTAssertEqual(BoardingRule.phase(of: next, now: now), .boarding)
        XCTAssertEqual(departures.dropFirst().map { BoardingRule.phase(of: $0, now: now) }, [.waiting, .waiting, .waiting])
    }

    /// Board: the train stays at its platform for 1 min past its time, then it has moved off and the following train boards.
    func testBoardHoldsTheTrainAMinutePastItsTimeThenItMovesOff() async throws {
        let base = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let trips = try await base.trips(for: base.route, on: base.serviceDay).sorted { $0.scheduledDeparture < $1.scheduledDeparture }
        let leaves = try XCTUnwrap(trips.first).scheduledDeparture

        let held = leaves.addingTimeInterval(30)
        let (atHeld, _) = try await resolved(.boarding, now: held)
        XCTAssertEqual(atHeld.count, 4)
        XCTAssertEqual(BoardingRule.phase(of: atHeld[0], now: held), .boarding, "30 s past its time it still stands there")
        XCTAssertNil(atHeld[1].originFix, "one train at the platform at a time")
        XCTAssertEqual(BoardingRule.phase(of: atHeld[1], now: held), .waiting)

        let moved = leaves.addingTimeInterval(61)
        let (atMoved, _) = try await resolved(.boarding, now: moved)
        XCTAssertEqual(atMoved.count, 4)
        XCTAssertEqual(atMoved[0].originFix, OriginFix(metres: MockLiveFeed.movedMetres, reportedAt: moved))
        XCTAssertGreaterThan(MockLiveFeed.movedMetres, BoardingRule.radius)
        XCTAssertEqual(BoardingRule.phase(of: atMoved[0], now: moved), .departed(.moved), "61 s past its time it has moved off")
        XCTAssertEqual(BoardingRule.phase(of: atMoved[1], now: moved), .boarding, "the following train boards")
    }

    /// Board: a train that moved off is placed away from the station for 10 min; one that left before that gets no
    /// position, so it follows the clock, and the trains after the next one wait with none.
    func testBoardPlacesTheTrainsThatLeftForTenMinutes() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // Minutes from now: two trains that left, the next one, one after it.
        let minutesFromNow: [Int] = [-20, -5, 5, 15]
        let day = ServiceDay(year: 2026, month: 11, day: 5)
        let trips: [Trip] = minutesFromNow.indices.map { (index: Int) -> Trip in
            let leaves: Date = now.addingTimeInterval(TimeInterval(minutesFromNow[index]) * 60)
            return Trip(
                key: TripKey(serviceDay: day, tripId: "T\(index)"),
                scheduledDeparture: leaves,
                scheduledArrival: leaves.addingTimeInterval(1800),
                platform: .pending, tags: []
            )
        }
        let live = MockLiveFeed.snapshot(.boarding, trips: trips, now: now)
        XCTAssertEqual(live.updatedAt, now)
        XCTAssertTrue(trips.allSatisfy { live.updates[$0.key.tripId]?.expectedDeparture == $0.scheduledDeparture }, "all on time")
        XCTAssertEqual(live.originFixes, [
            "T1": OriginFix(metres: MockLiveFeed.movedMetres, reportedAt: now),
            "T2": OriginFix(metres: MockLiveFeed.boardingMetres, reportedAt: now),
        ])
        XCTAssertTrue(live.leftOrigin.isEmpty)

        let departures = Departure.resolve(
            MockLiveFeed.withPlatforms(trips), live: live, freshness: Freshness(live, now: now), isToday: true
        )
        let phases: [BoardingRule.Phase] = departures.map { BoardingRule.phase(of: $0, now: now) }
        XCTAssertEqual(phases, [.departed(.clock), .departed(.moved), .boarding, .waiting])

        // The other feeds place no train, so they follow the clock as before.
        for mode in [MockLive.onTime, .mixed, .changing, .stale] {
            XCTAssertTrue(MockLiveFeed.snapshot(mode, trips: trips, now: now).originFixes.isEmpty, "\(mode)")
        }
    }

    /// Demo trains Platform makes its own live status and wins over Board: no platform posted, no train placed. Ride and
    /// Departure leave live status alone, so Board plays under them.
    func testDemoTrainsThatMakeLiveStatusWinOverBoard() async throws {
        let (repository, base, _) = try make(.boarding, demo: .awaitingPlatform)
        let trips = try await repository.trips(for: base.route, on: base.serviceDay)
        let live = try await repository.liveStatus(for: base.route, on: base.serviceDay)
        XCTAssertTrue(trips.allSatisfy { $0.platform == .pending })
        XCTAssertTrue(live.originFixes.isEmpty)

        let (riding, _, _) = try make(.boarding, demo: .ride)
        let ridingTrips = try await riding.trips(for: base.route, on: base.serviceDay)
        let ridingLive = try await riding.liveStatus(for: base.route, on: base.serviceDay)
        XCTAssertTrue(ridingTrips.allSatisfy { $0.platform != .pending })
        XCTAssertEqual(ridingLive.originFixes.count, 1)
    }
}
