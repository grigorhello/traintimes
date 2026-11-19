import Foundation
@testable import TrainTimes

private final class BundleToken {}

/// A repository that returns what a test hands it.
struct StubScheduleRepository: ScheduleRepository {
    var tripList: [Trip]
    var live: LiveSnapshot
    var stopList: [TripStop]

    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] { tripList }
    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot { live }
    func lineNotices(for line: Line) async throws -> [LineNotice] { [] }
    func stops(for trip: TripKey, on route: Route) async throws -> [TripStop] { stopList }
}

extension TripDetailsViewModel {
    nonisolated static let fixtureTripId = "LW-0732-20261105"

    /// One fixture trip (the 7:32 AM train by default) on the fixture clock, Thu Nov 5, 7:21 AM, already loaded.
    @MainActor
    static func loadedFixture(
        _ scenario: FixtureScheduleRepository.Scenario = .normal,
        tripId: String = fixtureTripId,
        minutesLater: Int = 0,
        hasAlert: Bool = false
    ) async throws -> TripDetailsViewModel {
        let repository = try FixtureScheduleRepository(scenario: scenario, bundle: Bundle(for: BundleToken.self))
        let model = TripDetailsViewModel(
            route: repository.route,
            key: TripKey(serviceDay: repository.serviceDay, tripId: tripId),
            repository: repository,
            clock: FixedClock(now: repository.now.addingTimeInterval(TimeInterval(minutesLater * 60))),
            hasAlert: hasAlert
        )
        await model.load()
        return model
    }

    /// The 7:32 AM train at 7:50 AM with fresh live data: it left at 7:43 AM, 11 min late, and is expected at Union at
    /// 8:23 AM. `skipping` marks those stops as skipped by the feed.
    @MainActor
    static func departedFixture(skipping skipped: Set<String> = []) async throws -> TripDetailsViewModel {
        let fixture = try FixtureScheduleRepository(bundle: Bundle(for: BundleToken.self))
        let day = fixture.serviceDay
        let key = TripKey(serviceDay: day, tripId: fixtureTripId)
        let delay: TimeInterval = 11 * 60
        let now = day.date(hour: 7, minute: 50)
        let trips = try await fixture.trips(for: fixture.route, on: day)
        let stops = try await fixture.stops(for: key, on: fixture.route).map { stop in
            skipped.contains(stop.id)
                ? TripStop(station: stop.station, scheduled: stop.scheduled, isSkipped: true)
                : TripStop(station: stop.station, scheduled: stop.scheduled, expected: stop.scheduled.addingTimeInterval(delay))
        }
        let update = LiveTripUpdate(
            expectedDeparture: day.date(hour: 7, minute: 43),
            expectedArrival: day.date(hour: 8, minute: 23),
            delayMinutes: 11,
            reportedAt: day.date(hour: 7, minute: 49)
        )
        let repository = StubScheduleRepository(
            tripList: trips,
            live: LiveSnapshot(updatedAt: now, updates: [fixtureTripId: update]),
            stopList: stops
        )
        let model = TripDetailsViewModel(route: fixture.route, key: key, repository: repository, clock: FixedClock(now: now), hasAlert: true)
        await model.load()
        return model
    }

    /// One fixture trip with no live data at all: the timetable only (D14), as the app shows it without the Metrolinx
    /// key. The 7:58 AM express train by default, which has no platform yet.
    @MainActor
    static func timetableOnlyFixture(tripId: String = "LW-0758-20261105", hasAlert: Bool = false) async throws -> TripDetailsViewModel {
        let fixture = try FixtureScheduleRepository(bundle: Bundle(for: BundleToken.self))
        let key = TripKey(serviceDay: fixture.serviceDay, tripId: tripId)
        let repository = StubScheduleRepository(
            tripList: try await fixture.trips(for: fixture.route, on: fixture.serviceDay),
            live: .empty,
            stopList: try await fixture.stops(for: key, on: fixture.route)
        )
        let model = TripDetailsViewModel(
            route: fixture.route, key: key, repository: repository, clock: FixedClock(now: fixture.now), hasAlert: hasAlert
        )
        await model.load()
        return model
    }

    /// The 7:58 AM express train at 7:21 AM, 9 min late with fresh live data (expected 8:07 AM): a later train, which says
    /// "Departs at" in the hero (TT-207, the canvas's Delay-A-Dark).
    @MainActor
    static func laterDelayedFixture() async throws -> TripDetailsViewModel {
        let fixture = try FixtureScheduleRepository(bundle: Bundle(for: BundleToken.self))
        let day = fixture.serviceDay
        let key = TripKey(serviceDay: day, tripId: "LW-0758-20261105")
        let update = LiveTripUpdate(
            expectedDeparture: day.date(hour: 8, minute: 7),
            expectedArrival: day.date(hour: 8, minute: 47),
            delayMinutes: 9,
            reportedAt: fixture.now
        )
        let repository = StubScheduleRepository(
            tripList: try await fixture.trips(for: fixture.route, on: day),
            live: LiveSnapshot(updatedAt: fixture.now, updates: [key.tripId: update]),
            stopList: try await fixture.stops(for: key, on: fixture.route)
        )
        let model = TripDetailsViewModel(route: fixture.route, key: key, repository: repository, clock: FixedClock(now: fixture.now))
        await model.load()
        return model
    }

    /// West Harbour to Union with 12 stops, 6:58 to 8:02 AM, timetable only, at 6:30 AM by default: the list is taller than
    /// the sheet (the canvas's Trip-Details-End frame). From 6:58 AM the train has left and the sheet shows the whole list.
    @MainActor
    static func longTripFixture(hasAlert: Bool = false, hour: Int = 6, minute: Int = 30) async throws -> TripDetailsViewModel {
        let fixture = try FixtureScheduleRepository(bundle: Bundle(for: BundleToken.self))
        let day = fixture.serviceDay
        let departure = day.date(hour: 6, minute: 58)
        let trip = Trip(
            key: TripKey(serviceDay: day, tripId: "LW-0658-20261105"),
            scheduledDeparture: departure,
            scheduledArrival: day.date(hour: 8, minute: 2),
            platform: .pending,
            tags: []
        )
        let stations = [
            ("WH", "West Harbour GO", 0), ("AL", "Aldershot GO", 10), ("BU", "Burlington GO", 14), ("AP", "Appleby GO", 19),
            ("BR", "Bronte GO", 23), ("OA", "Oakville GO", 28), ("CL", "Clarkson GO", 33), ("PO", "Port Credit GO", 38),
            ("LO", "Long Branch GO", 44), ("MO", "Mimico GO", 49), ("EX", "Exhibition GO", 55), ("UN", "Union Station GO", 64),
        ]
        let stops = stations.map { id, name, minutes in
            TripStop(station: Station(id: id, name: name), scheduled: departure.addingTimeInterval(TimeInterval(minutes * 60)))
        }
        let repository = StubScheduleRepository(tripList: [trip], live: .empty, stopList: stops)
        let model = TripDetailsViewModel(
            route: fixture.route, key: trip.key, repository: repository, clock: FixedClock(now: day.date(hour: hour, minute: minute)),
            hasAlert: hasAlert
        )
        await model.load()
        return model
    }
}

extension TripDetailsViewModel {
    /// The 7:32 AM fixture train at 7:21 AM, 11 min before it leaves, with On board (TT-172): an app engine that can start a
    /// ride on the sample Union to Clarkson plan (any trip gets it) and asks for location through `location`.
    @MainActor
    static func onBoardFixture(
        minutesLater: Int = 0, hasAlert: Bool = false, location: FakeLocation? = nil
    ) async throws -> TripDetailsViewModel {
        let repository = try FixtureScheduleRepository(bundle: Bundle(for: BundleToken.self))
        let clock = FixedClock(now: repository.now.addingTimeInterval(TimeInterval(minutesLater * 60)))
        let engine = RideEngine(
            data: FakeRideData(plan: try OnBoardFixtures.plan()), location: location ?? FakeLocation(), clock: clock, defaults: nil,
            tickInterval: nil
        )
        let model = TripDetailsViewModel(
            route: repository.route,
            key: TripKey(serviceDay: repository.serviceDay, tripId: fixtureTripId),
            repository: repository,
            clock: clock,
            hasAlert: hasAlert,
            onBoard: OnBoard(app: engine)
        )
        await model.load()
        return model
    }
}

/// The demo ride (TT-172) on Friday, Nov 27, on a clock the test moves: `drive(to:)` sets the clock and sends the fix of the
/// demo train at that moment, as the demo's own location does each second.
@MainActor
struct DemoRideRig {
    nonisolated static let day = OnBoardFixtures.friday

    let clock: TestClock
    let onBoard: OnBoard
    var plan = DemoRide.plan(on: DemoRideRig.day)

    nonisolated static func time(_ hours: Int, _ minutes: Int, _ seconds: Int = 0) -> Date {
        DemoRideRig.day.gtfsTime(hours * 3600 + minutes * 60 + seconds)
    }

    /// The demo started at 5:32 PM and moved on to `moment`, with the arriving nudge `makeNudge` gives (none by default).
    /// `express` (TT-232): the same train not stopping between Union and Clarkson (5:13 to 5:39 PM), started at `start`.
    static func started(
        at moment: Date = DemoRideRig.time(17, 32), makeNudge: @escaping @MainActor () -> ArrivalNudge? = { nil },
        wishes: ArrivalWishes? = nil, express: Bool = false, from start: Date = DemoRideRig.time(17, 32)
    ) async -> DemoRideRig {
        // The first wish of the pool, so the at-your-stop snapshots stay the same (TT-223).
        let wishes = wishes ?? ArrivalWishes(defaults: nil, haptics: FakeHaptics(), index: { _ in 0 })
        let clock = TestClock(now: start)
        let day = DemoRideRig.day
        // No question first (TT-175): the ride starts as Demo trains › Ride turns on.
        let onBoard = OnBoard(
            app: nil,
            makeDemo: { _ in
                (engine: DemoRide.engine(on: day, clock: clock, tickInterval: nil, express: express), ride: DemoRide.ride(on: day))
            },
            makeDemoDetector: nil,
            makeDemoNudge: makeNudge,
            wishes: wishes
        )
        await onBoard.setDemo(true)
        let rig = DemoRideRig(clock: clock, onBoard: onBoard, plan: DemoRide.plan(on: day, express: express))
        if moment != start { rig.drive(to: moment) }
        return rig
    }

    /// The demo express (TT-232) started at 5:20 PM and moved on to `moment`: Exhibition, Mimico, Long Branch and Port Credit
    /// passed without stopping, about 13 %, 38 %, 57 % and 77 % of the way to Clarkson.
    static func express(at moment: Date) async -> DemoRideRig {
        await started(at: moment, express: true, from: DemoRideRig.time(17, 20))
    }

    var engine: RideEngine? { onBoard.engine }
    var key: TripKey { DemoRide.ride(on: DemoRideRig.day).tripKey }

    func drive(to time: Date) {
        clock.set(time)
        guard let track = plan.track else { return }
        engine?.receive(LocationFix(coordinate: track.shape.point(at: DemoRide.along(at: time, plan: plan)), horizontalAccuracy: 5))
    }

    /// Trip details on the demo ride, as the strip opens it.
    func tripDetails() -> TripDetailsViewModel {
        TripDetailsViewModel(
            route: DemoRide.route,
            key: key,
            repository: StubScheduleRepository(tripList: [], live: .empty, stopList: []),
            clock: clock,
            onBoard: onBoard
        )
    }
}

/// Demo trains › Departure (TT-177) on Friday, Nov 27, on a clock the test moves: the 5:13 PM train counting down from
/// 5:01 PM, Platform 7 posted at 5:03, 3 min late from 5:04, Boarding now from 5:14, Departed at 5:16. "I’m on board" hands
/// over into the demo ride on the same clock, with no timer.
@MainActor
struct DepartureRig {
    nonisolated static let day = OnBoardFixtures.friday

    let clock: TestClock
    let onBoard: OnBoard

    nonisolated static func time(_ hours: Int, _ minutes: Int, _ seconds: Int = 0) -> Date {
        DepartureRig.day.gtfsTime(hours * 3600 + minutes * 60 + seconds)
    }

    /// The demo departure playing, at `moment`.
    static func started(at moment: Date = DepartureRig.time(17, 1)) -> DepartureRig {
        let clock = TestClock(now: moment)
        let day = DepartureRig.day
        let onBoard = OnBoard(
            app: nil,
            makeDeparture: { DemoDeparture.Session(day: day, clock: clock) },
            makeHandOff: { _ in (engine: DemoRide.engine(on: day, clock: clock, tickInterval: nil), ride: DemoRide.ride(on: day)) }
        )
        onBoard.setDemoDeparture(true)
        return DepartureRig(clock: clock, onBoard: onBoard)
    }

    var key: TripKey { TripKey(serviceDay: DepartureRig.day, tripId: DemoRide.tripId) }

    /// Trip details on the demo train, as its strip opens it, loaded.
    /// Directions taps go to `maps`, a fake by default, so no test opens Apple Maps.
    func tripDetails(maps: any MapsOpening = FakeMapsOpener()) async -> TripDetailsViewModel {
        let model = TripDetailsViewModel(
            route: DemoRide.route,
            key: key,
            repository: StubScheduleRepository(tripList: [], live: .empty, stopList: []),
            clock: clock,
            hasAlert: true,
            onBoard: onBoard,
            maps: maps
        )
        await model.load()
        return model
    }

    /// Moves the clock and lets the open sheet follow it, as its tick does each second.
    func move(to time: Date, _ model: TripDetailsViewModel) {
        clock.set(time)
        model.tick()
    }
}

/// A repository whose live feed a test replaces between loads, as a poll does (TT-233).
private actor PolledScheduleRepository: ScheduleRepository {
    private let tripList: [Trip]
    private let stopList: [TripStop]
    private var live: LiveSnapshot

    init(tripList: [Trip], live: LiveSnapshot, stopList: [TripStop]) {
        self.tripList = tripList
        self.live = live
        self.stopList = stopList
    }

    func set(_ live: LiveSnapshot) {
        self.live = live
    }

    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] { tripList }
    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot { live }
    func lineNotices(for line: Line) async throws -> [LineNotice] { [] }
    func stops(for trip: TripKey, on route: Route) async throws -> [TripStop] { stopList }
}

/// Boarding at the platform in Trip details (TT-233, D114): one fixture train's sheet on Thu Nov 5, with no alert and no
/// ride, on a clock and a feed the test moves. Each poll is fresh live data at that moment: the 7:32 AM and 7:58 AM trains
/// on time, Platform 2 and Platform 3 posted, and GO's train feed placing the sheet's train `metres` from Oakville 10 s
/// before (nil: no position, so the train follows the clock).
@MainActor
struct TripBoardingRig {
    /// The 7:32 AM train, the next one until it leaves.
    nonisolated static let nextTrain = "LW-0732-20261105"
    /// The 7:58 AM express train.
    nonisolated static let laterTrain = "LW-0758-20261105"

    let model: TripDetailsViewModel
    private let day: ServiceDay
    private let tripId: String
    private let clock: TestClock
    private let feed: PolledScheduleRepository

    /// The sheet on `tripId` opened at `hour`:`minute`:`second` with its first poll, loaded.
    static func opened(
        _ tripId: String, hour: Int, minute: Int, second: Int = 0, metres: Double?,
        boardingShown: BoardingShown = BoardingShown(defaults: nil)
    ) async throws -> TripBoardingRig {
        let fixture = try FixtureScheduleRepository(bundle: Bundle(for: BundleToken.self))
        let day = fixture.serviceDay
        let key = TripKey(serviceDay: day, tripId: tripId)
        let now = day.date(hour: hour, minute: minute).addingTimeInterval(TimeInterval(second))
        let clock = TestClock(now: now)
        let feed = PolledScheduleRepository(
            tripList: try await fixture.trips(for: fixture.route, on: day),
            live: poll(day: day, tripId: tripId, metres: metres, now: now),
            stopList: try await fixture.stops(for: key, on: fixture.route)
        )
        let model = TripDetailsViewModel(route: fixture.route, key: key, repository: feed, clock: clock, boardingShown: boardingShown)
        await model.load()
        return TripBoardingRig(model: model, day: day, tripId: tripId, clock: clock, feed: feed)
    }

    /// A later poll at `hour`:`minute`:`second`: the clock moves there and the sheet reloads, as its refresh does.
    func sight(metres: Double?, hour: Int, minute: Int, second: Int = 0) async {
        let now = day.date(hour: hour, minute: minute).addingTimeInterval(TimeInterval(second))
        clock.set(now)
        await feed.set(Self.poll(day: day, tripId: tripId, metres: metres, now: now))
        await model.load()
    }

    /// What the feeds say at `now`.
    private nonisolated static func poll(day: ServiceDay, tripId: String, metres: Double?, now: Date) -> LiveSnapshot {
        var updates: [String: LiveTripUpdate] = [:]
        for (id, hour, minute) in [(nextTrain, 7, 32), (laterTrain, 7, 58)] {
            updates[id] = LiveTripUpdate(expectedDeparture: day.date(hour: hour, minute: minute), reportedAt: now)
        }
        var live = LiveSnapshot(
            updatedAt: now, hasPlatformSource: true, updates: updates, platforms: [nextTrain: "2", laterTrain: "3"]
        )
        if let metres {
            live.originFixes[tripId] = OriginFix(metres: metres, reportedAt: now.addingTimeInterval(-10))
        }
        return live
    }
}
