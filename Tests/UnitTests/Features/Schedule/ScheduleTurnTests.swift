import XCTest
@testable import TrainTimes

/// The turn nobody tapped, on Schedule's model (TT-235, D116): the token the route card plays its calm swap from, the
/// trains' path (the other direction's trains are read while the old ones show, then the route and the trains change in
/// one step, straight from the timetable) and the life of the arrow on From. The route is the fixture's, Oakville to
/// Union on Thu Nov 5 at 7:21 AM, with three trains the other way.
@MainActor
final class ScheduleTurnTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)

    override func tearDown() async throws {
        Analytics.tracker = nil
        try await super.tearDown()
    }

    /// Schedule on the fixture route with its trains loaded, over a timetable that runs both ways.
    private struct Rig {
        let timetable: TurnFixtures.Timetable
        let repository: TurnScheduleRepository
        let model: ScheduleViewModel
        let haptics: FakeHaptics
        let watched: FakeWatchedTrips
    }

    private func rig(loads: Bool = true) async throws -> Rig {
        let timetable = try await TurnFixtures.timetable()
        let repository = timetable.repository()
        let haptics = FakeHaptics()
        let watched = FakeWatchedTrips()
        let model = ScheduleViewModel(
            route: timetable.route, repository: repository, clock: FixedClock(now: timetable.now), watchedTrips: watched,
            haptics: haptics
        )
        if loads { await model.loadIfNeeded() }
        return Rig(timetable: timetable, repository: repository, model: model, haptics: haptics, watched: watched)
    }

    private func eventually(
        _ condition: () async -> Bool, file: StaticString = #filePath, line: UInt = #line
    ) async {
        for _ in 0..<500 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out", file: file, line: line)
    }

    // MARK: The token

    /// Each turn publishes a token for the route card: the names as they stood, starting now.
    func testATurnPublishesItsTokenWithTheOldNames() async throws {
        let rig = try await rig()
        XCTAssertNil(rig.model.turnToken)

        let before = Date()
        let made = await rig.model.turn()
        XCTAssertTrue(made)
        let token = try XCTUnwrap(rig.model.turnToken)
        XCTAssertEqual(token.id, rig.model.turns)
        XCTAssertEqual(token.from, rig.timetable.route.from.name)
        XCTAssertEqual(token.to, rig.timetable.route.to.name)
        let start = try XCTUnwrap(token.start, "Coming back, the names trade the moment the route turns")
        XCTAssertGreaterThanOrEqual(start, before)
        XCTAssertLessThanOrEqual(start, Date())

        // Undo is a turn too: the names go back the same calm way, under a new token.
        await rig.model.turn(.undone)
        let undo = try XCTUnwrap(rig.model.turnToken)
        XCTAssertEqual(undo.id, token.id + 1)
        XCTAssertEqual(undo.from, rig.timetable.route.to.name)
        XCTAssertEqual(undo.to, rig.timetable.route.from.name)
        XCTAssertNotNil(undo.start)
    }

    /// A cold start: the route turns under the splash and the token is held, so the card keeps the old order at rest.
    /// The names trade once the splash has gone: the lift plus its fade.
    func testATurnUnderTheSplashIsHeldUntilTheSplashHasGone() async throws {
        let rig = try await rig()
        rig.model.setSplashCovers(true)

        await rig.model.turn()
        XCTAssertEqual(rig.model.route, rig.timetable.reversed, "The route turns under the splash")
        XCTAssertEqual(rig.model.departures.map(\.id), rig.timetable.reverseTrips.map(\.id), "with its trains")
        let held = try XCTUnwrap(rig.model.turnToken)
        XCTAssertNil(held.start, "Held: the old order at rest")
        XCTAssertNil(rig.model.outgoing, "Nothing showed, so nothing fades")

        let lifted = Date()
        rig.model.setSplashCovers(false, fade: 0.24)
        let token = try XCTUnwrap(rig.model.turnToken)
        XCTAssertEqual(token.id, held.id)
        let start = try XCTUnwrap(token.start)
        XCTAssertGreaterThanOrEqual(start, lifted.addingTimeInterval(0.24))
        XCTAssertLessThanOrEqual(start, Date().addingTimeInterval(0.24))

        // Told again, the start stays.
        rig.model.setSplashCovers(false, fade: 0.24)
        XCTAssertEqual(rig.model.turnToken, token)
    }

    /// The fade is the launch's own: 200 ms, 240 ms on the first 8 launches.
    func testTheHeldStartWaitsForTheSplashsFade() {
        XCTAssertEqual(LaunchMotion.Timing.quick.markFadeDuration, 0.2)
        XCTAssertEqual(LaunchMotion.Timing.full.markFadeDuration, 0.24)
    }

    /// Before the first load the route alone changes, and the token is published all the same.
    func testATurnBeforeTheFirstLoadStillPublishesItsToken() async throws {
        let rig = try await rig(loads: false)
        rig.model.setSplashCovers(true)

        let made = await rig.model.turn()
        XCTAssertTrue(made)
        XCTAssertEqual(rig.model.route, rig.timetable.reversed)
        XCTAssertNotNil(rig.model.turnToken)
        XCTAssertNil(rig.model.turnToken?.start)
        XCTAssertTrue(rig.model.marksFrom)

        await rig.model.loadIfNeeded()
        XCTAssertEqual(rig.model.departures.map(\.id), rig.timetable.reverseTrips.map(\.id))
        XCTAssertEqual(rig.model.scrollRequest, 1, "The launch's own scroll")
    }

    /// A turn made while the launch's load still runs brings its own trains, its jump to Now and the one Now play: the
    /// launch's scroll and pulse do not come after it.
    func testATurnDuringTheFirstLoadIsTheOneArrival() async throws {
        let rig = try await rig(loads: false)
        rig.model.setSplashCovers(true)
        await rig.repository.holdTrips(from: rig.timetable.route.from.id)
        let launch = Task { await rig.model.loadIfNeeded() }
        await eventually { await rig.repository.tripsWaiting == 1 }

        let made = await rig.model.turn()
        XCTAssertTrue(made)
        XCTAssertEqual(rig.model.departures.map(\.id), rig.timetable.reverseTrips.map(\.id))
        XCTAssertFalse(rig.model.awaitsNewTrains)
        XCTAssertEqual(rig.model.scrollRequest, 1)
        XCTAssertEqual(rig.model.nowPulse, 1)

        await rig.repository.releaseTrips()
        await launch.value
        XCTAssertEqual(rig.model.route, rig.timetable.reversed)
        XCTAssertEqual(rig.model.departures.map(\.id), rig.timetable.reverseTrips.map(\.id), "The old route's load is dropped")
        XCTAssertEqual(rig.model.scrollRequest, 1, "One jump to Now")
        XCTAssertEqual(rig.model.entranceRequest, 1, "One cascade")
        // The launch's scroll would pulse Now once it settles: it must not.
        for departure in rig.model.departures {
            rig.model.setCardSize(TimelineCardSize(height: 118, anchor: 33), for: departure.id)
        }
        XCTAssertEqual(rig.model.nowPulse, 1, "One Now play")
    }

    // MARK: The trains

    /// The old cards stay until the new ones are in: while the other direction's trains are read nothing changes, and
    /// the route, its trains and the cascade then come in one step, with the old cards kept for their fade.
    func testTheOldCardsStayUntilTheNewOnesAreIn() async throws {
        let rig = try await rig()
        let model = rig.model
        let old = model.departures
        let entrances = model.entranceRequest
        let scrolls = model.scrollRequest
        let pulses = model.nowPulse
        XCTAssertEqual(old.count, 4)
        await rig.repository.holdTrips(from: rig.timetable.reversed.from.id)

        let turn = Task { await model.turn() }
        await eventually { await rig.repository.tripsWaiting == 1 }
        XCTAssertEqual(model.route, rig.timetable.route, "The old route still shows")
        XCTAssertEqual(model.departures, old)
        XCTAssertFalse(model.awaitsNewTrains, "The old cards are not hidden")
        XCTAssertEqual(model.content, .timeline)
        XCTAssertEqual(model.entranceRequest, entrances)
        XCTAssertNil(model.turnToken)
        XCTAssertNil(model.outgoing)

        await rig.repository.releaseTrips()
        let made = await turn.value
        XCTAssertTrue(made)
        XCTAssertEqual(model.route, rig.timetable.reversed)
        XCTAssertEqual(model.departures.map(\.id), rig.timetable.reverseTrips.map(\.id))
        XCTAssertEqual(model.content, .timeline, "Never empty")
        XCTAssertFalse(model.awaitsNewTrains)
        XCTAssertEqual(model.entranceRequest, entrances + 1, "The new trains cascade in")
        XCTAssertEqual(model.scrollRequest, scrolls + 1)
        XCTAssertTrue(model.scrollJumps, "At Now after it, as after a swap")
        XCTAssertEqual(model.nowPulse, pulses + 1, "One Now play")

        let outgoing = try XCTUnwrap(model.outgoing, "The old cards are kept for their fade")
        XCTAssertEqual(outgoing.request, model.entranceRequest)
        XCTAssertEqual(outgoing.route, rig.timetable.route)
        XCTAssertEqual(outgoing.departures, old)
        let cards = model.cards(of: outgoing, formatter)
        XCTAssertFalse(cards.isEmpty)
        XCTAssertTrue(Set(cards.map(\.id)).isSubset(of: Set(old.map(\.id))))
        XCTAssertEqual(cards.filter(\.isNext).map(\.id), [old[0].id], "As they stood: the 7:32 was the next train")
    }

    /// The turned trains are published from the timetable without waiting for live status: status fills in after, as a
    /// poll's does, with no second cascade. A watched train that is late already is not felt as turning late.
    func testTheTurnedTrainsShowBeforeTheirLiveStatus() async throws {
        let rig = try await rig()
        let model = rig.model
        let entrances = model.entranceRequest
        let first = try XCTUnwrap(rig.timetable.reverseTrips.first)
        rig.watched.trips = [first.key]
        await rig.repository.holdLive()

        let turn = Task { await model.turn() }
        await eventually { await rig.repository.liveWaiting == 1 }
        XCTAssertEqual(model.route, rig.timetable.reversed)
        XCTAssertEqual(model.departures.map(\.id), rig.timetable.reverseTrips.map(\.id), "The timetable's trains show")
        XCTAssertEqual(model.departures.map(\.status), [.scheduled, .scheduled, .scheduled])
        XCTAssertEqual(model.content, .timeline)
        XCTAssertFalse(model.awaitsNewTrains)
        XCTAssertEqual(model.entranceRequest, entrances + 1)

        let late = LiveTripUpdate(
            expectedDeparture: first.scheduledDeparture.addingTimeInterval(9 * 60), delayMinutes: 9, reportedAt: rig.timetable.now
        )
        await rig.repository.releaseLive(LiveSnapshot(updatedAt: rig.timetable.now, updates: [first.key.tripId: late]))
        _ = await turn.value
        XCTAssertEqual(model.departures.first?.status, .delayed(minutes: 9, reportedAt: rig.timetable.now), "Status fills in")
        XCTAssertEqual(model.entranceRequest, entrances + 1, "No second cascade")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(rig.haptics.played, [], "Already late when first seen: no Warning")
    }

    /// The look says no once the trains are in (they came too late, or the rider touched Schedule): nothing moves.
    func testANoOnceTheTrainsAreInLeavesEverythingAsItIs() async throws {
        let rig = try await rig()
        let model = rig.model
        let old = model.departures
        let entrances = model.entranceRequest
        let scrolls = model.scrollRequest

        let made = await model.turn(.byItself) { false }
        XCTAssertFalse(made)
        XCTAssertEqual(model.route, rig.timetable.route)
        XCTAssertEqual(model.departures, old)
        XCTAssertEqual(model.turns, 0)
        XCTAssertNil(model.turnToken)
        XCTAssertFalse(model.marksFrom)
        XCTAssertEqual(model.entranceRequest, entrances)
        XCTAssertEqual(model.scrollRequest, scrolls)
    }

    /// The look is asked only once the trains are in, and the route turns in that same step.
    func testTheLookIsAskedOnceTheTrainsAreIn() async throws {
        let rig = try await rig()
        let model = rig.model
        await rig.repository.holdTrips(from: rig.timetable.reversed.from.id)
        let asked = Counter()

        let turn = Task {
            await model.turn(.byItself) {
                asked.count += 1
                return true
            }
        }
        await eventually { await rig.repository.tripsWaiting == 1 }
        XCTAssertEqual(asked.count, 0, "Not before the trains are read")

        await rig.repository.releaseTrips()
        _ = await turn.value
        XCTAssertEqual(asked.count, 1)
        XCTAssertEqual(model.route, rig.timetable.reversed)
    }

    /// With no timetable to read a turn by itself is not made (the look asks). Undo and Switch are the rider's taps and
    /// turn the route anyway, as any new route does.
    func testNoTimetableStopsATurnByItselfOnly() async throws {
        let rig = try await rig()
        let model = rig.model
        await rig.repository.removeTimetable()

        let made = await model.turn()
        XCTAssertFalse(made)
        XCTAssertEqual(model.route, rig.timetable.route)
        XCTAssertEqual(model.departures.count, 4, "The old trains stay")
        XCTAssertNil(model.turnToken)

        let switched = await model.turn(.switched)
        XCTAssertTrue(switched)
        XCTAssertEqual(model.route, rig.timetable.reversed)
        XCTAssertNotNil(model.turnToken)
        XCTAssertTrue(model.marksFrom)
    }

    /// A route chosen while the other direction's trains are read stands: the turn is dropped.
    func testARouteChosenWhileTheTrainsAreReadStands() async throws {
        let rig = try await rig()
        let model = rig.model
        let picked = Route(from: Station(id: "CL", name: "Clarkson"), to: rig.timetable.route.to, line: rig.timetable.route.line)
        await rig.repository.holdTrips(from: rig.timetable.reversed.from.id)

        let turn = Task { await model.turn() }
        await eventually { await rig.repository.tripsWaiting == 1 }
        await model.show(picked)
        await rig.repository.releaseTrips()

        let made = await turn.value
        XCTAssertFalse(made)
        XCTAssertEqual(model.route, picked)
        XCTAssertEqual(model.turns, 0)
        XCTAssertNil(model.turnToken)
        XCTAssertFalse(model.marksFrom)
    }

    // MARK: The arrow on From

    /// The arrow shows after a turn the app made from the rider's place and after Switch, and stays for the visit: it
    /// goes when the app goes to the background, on Undo, and when the route changes by hand or by a link.
    func testTheArrowOnFromLivesForTheVisit() async throws {
        let rig = try await rig()
        let model = rig.model
        XCTAssertFalse(model.marksFrom)

        await model.turn()
        XCTAssertTrue(model.marksFrom, "A turn by itself")
        model.timelineAppeared()
        await model.refresh()
        await model.select(model.days[1])
        await model.backToNow()
        XCTAssertTrue(model.marksFrom, "It stays across the visit")

        model.wentToBackground()
        XCTAssertFalse(model.marksFrom, "The visit is over")

        await model.turn(.switched)
        XCTAssertTrue(model.marksFrom, "Switch")
        await model.turn(.undone)
        XCTAssertFalse(model.marksFrom, "Undo")

        await model.turn()
        await model.swap()
        XCTAssertFalse(model.marksFrom, "The swap button")

        await model.turn()
        let shown = try XCTUnwrap(model.route)
        await model.show(shown, chosen: .widgetRoute)
        XCTAssertTrue(model.marksFrom, "A link to the route that shows changes nothing")
        await model.show(Route(from: shown.to, to: shown.from, line: shown.line), chosen: .trainLink)
        XCTAssertFalse(model.marksFrom, "A link that changes the route")

        await model.turn()
        let picked = Route(from: Station(id: "CL", name: "Clarkson"), to: rig.timetable.route.to, line: rig.timetable.route.line)
        await model.show(picked)
        XCTAssertFalse(model.marksFrom, "A route picked by hand")
    }
}

@MainActor
private final class Counter {
    var count = 0
}
