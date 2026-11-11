import XCTest
@testable import TrainTimes

/// TT-171: the ride engine on the 11:17 AM Lakeshore West train from Union to Clarkson (`OnBoardFixtures`), driven by a
/// synthetic location track and a hand-moved clock.
@MainActor
final class RideEngineTests: XCTestCase {
    private let ride = OnBoardFixtures.ride

    private struct Rig {
        let engine: RideEngine
        let clock: TestClock
        let location: FakeLocation
        let data: FakeRideData
        let defaults: UserDefaults
        let plan: RidePlan
    }

    private func rig(
        at time: Date, authorized: Bool = false, answer: Bool = true, trains: FakeTrainPositions? = nil,
        defaults: UserDefaults = .ephemeral()
    ) throws -> Rig {
        let plan = try OnBoardFixtures.plan()
        let clock = TestClock(now: time)
        let location = FakeLocation(authorized: authorized)
        location.answer = answer
        let data = FakeRideData(plan: plan)
        let engine = RideEngine(data: data, location: location, trains: trains, clock: clock, defaults: defaults, tickInterval: nil)
        return Rig(engine: engine, clock: clock, location: location, data: data, defaults: defaults, plan: plan)
    }

    private func t(_ hours: Int, _ minutes: Int, _ seconds: Int = 0) -> Date {
        OnBoardFixtures.time(hours, minutes, seconds)
    }

    /// Sets the clock and sends the fix of a train on time at that moment.
    private func drive(_ rig: Rig, to time: Date) throws {
        rig.clock.set(time)
        let fix = try OnBoardFixtures.fix(along: OnBoardFixtures.along(at: time, plan: rig.plan), plan: rig.plan)
        rig.location.send(fix)
    }

    func testThePlanPlacesEachStopAlongTheTrack() throws {
        let plan = try OnBoardFixtures.plan()
        XCTAssertEqual(plan.stops.map(\.station.id), ["UN", "EX", "MI", "LO", "PO", "CL"])
        XCTAssertEqual(plan.stops.first?.departure, t(11, 17))
        XCTAssertEqual(plan.stops.last?.arrival, t(11, 52))
        let distances = try XCTUnwrap(plan.track).stopDistances
        XCTAssertEqual(distances.first ?? -1, 0, accuracy: 1)
        XCTAssertEqual(distances, distances.sorted())
        XCTAssertEqual(distances.last ?? 0, 25_943, accuracy: 50, "Union to Clarkson is about 26 km of track")
    }

    /// Acceptance: a location track from Union to Clarkson drives the engine through every phase in order, with the right
    /// next stop and stops left at each point; the ride ends by itself 10 min after your stop.
    func testUnionToClarksonGoesThroughEveryPhaseInOrder() async throws {
        let rig = try rig(at: t(11, 10))
        let events = rig.engine.events()
        let started = await rig.engine.start(ride)
        XCTAssertTrue(started)
        XCTAssertTrue(rig.location.isUpdating)
        XCTAssertEqual(rig.engine.state?.minutesToYourStop, 42)

        typealias Check = (phase: RidePhase, at: String?, next: String?, left: Int)
        let checks: [Date: Check] = [
            t(11, 10): (.atStation, "UN", "EX", 5),
            t(11, 20): (.riding, nil, "EX", 5),
            t(11, 24): (.atStation, "EX", "MI", 4),
            t(11, 35): (.riding, nil, "LO", 3),
            t(11, 38): (.atStation, "LO", "PO", 2),
            t(11, 45): (.atStation, "PO", "CL", 1),
            t(11, 48): (.yourStopNext, nil, "CL", 1),
            t(11, 51, 10): (.arriving, nil, "CL", 1),
            t(11, 52): (.atYourStop, "CL", nil, 0),
            t(12, 1): (.atYourStop, "CL", nil, 0),
            t(12, 3): (.ended, "CL", nil, 0),
        ]
        var phases: [RidePhase] = []
        var time = t(11, 10)
        while time <= t(12, 5) {
            try drive(rig, to: time)
            rig.engine.update()
            let state = try XCTUnwrap(rig.engine.state)
            if state.phase != phases.last { phases.append(state.phase) }
            if let check = checks[time] {
                XCTAssertEqual(state.phase, check.phase, "\(time)")
                XCTAssertEqual(state.currentStop?.id, check.at, "\(time)")
                XCTAssertEqual(state.nextStop?.id, check.next, "\(time)")
                XCTAssertEqual(state.stopsLeft, check.left, "\(time)")
            }
            if time == t(11, 45) { XCTAssertEqual(state.minutesToYourStop, 7, "On time at Port Credit") }
            if state.phase != .ended { XCTAssertEqual(state.source, .phone, "\(time)") }
            time = time.addingTimeInterval(5)
        }

        let expected: [RidePhase] = [
            .atStation, .riding, .atStation, .riding, .atStation, .riding, .atStation, .riding, .atStation,
            .yourStopNext, .arriving, .atYourStop, .ended,
        ]
        XCTAssertEqual(phases, expected)
        XCTAssertEqual(rig.engine.state?.endReason, .arrived)
        XCTAssertFalse(rig.location.isUpdating, "Location stops with the ride")
        XCTAssertNil(rig.defaults.data(forKey: RideEngine.storageKey), "An ended ride is not kept")

        // The same phases reach the nudge and the Live Activity as events, the arriving one once.
        guard rig.engine.state?.phase == .ended else { return XCTFail("The ride did not end") }
        var emitted: [RidePhase] = []
        for await event in events {
            guard case let .phase(phase) = event else { continue }
            emitted.append(phase)
            if phase == .ended { break }
        }
        XCTAssertEqual(emitted, expected)
    }

    /// Acceptance: 60 s without a fix switches the source to the timetable, and back when the fix returns.
    func testSixtySecondsWithoutAFixFallBackToTheTimetableAndBack() async throws {
        let rig = try rig(at: t(11, 20))
        await rig.engine.start(ride)
        XCTAssertEqual(rig.engine.state?.source, .phone, "The first 60 s wait for the first fix")
        try drive(rig, to: t(11, 20))
        XCTAssertEqual(rig.engine.state?.source, .phone)
        XCTAssertEqual(rig.engine.state?.lastUpdate, t(11, 20))

        rig.clock.set(t(11, 20, 59))
        rig.engine.update()
        XCTAssertEqual(rig.engine.state?.source, .phone)
        rig.clock.set(t(11, 21, 1))
        rig.engine.update()
        XCTAssertEqual(rig.engine.state?.source, .timetable)
        XCTAssertEqual(rig.engine.state?.lastUpdate, t(11, 20), "The status shows when the phone last placed the train")
        XCTAssertEqual(rig.engine.state?.nextStop?.id, "EX")

        try drive(rig, to: t(11, 21, 30))
        XCTAssertEqual(rig.engine.state?.source, .phone)
        XCTAssertEqual(rig.engine.state?.lastUpdate, t(11, 21, 30))
    }

    /// After the phone, the train feed places the train while its position is fresh; then the timetable.
    func testTheTrainFeedComesBeforeTheTimetable() async throws {
        let trains = FakeTrainPositions()
        let rig = try rig(at: t(11, 20), trains: trains)
        await rig.engine.start(ride)
        try drive(rig, to: t(11, 20))
        rig.clock.set(t(11, 21, 1))
        let along = try OnBoardFixtures.along(at: rig.clock.now, plan: rig.plan)
        let place = try OnBoardFixtures.fix(along: along, plan: rig.plan).coordinate
        await trains.set(TrainPosition(coordinate: place, reportedAt: rig.clock.now))
        await rig.engine.refresh()
        XCTAssertEqual(rig.engine.state?.source, .trainFeed)
        XCTAssertEqual(rig.engine.state?.lastUpdate, t(11, 21, 1))

        rig.clock.advance(seconds: 91)
        rig.engine.update()
        XCTAssertEqual(rig.engine.state?.source, .timetable)
    }

    /// iOS sends nothing while the phone does not move, so a stationary fix holds; a train still at a station after its
    /// departure time is late by that much.
    func testAStationaryFixHoldsAtAStation() async throws {
        let rig = try rig(at: t(11, 24))
        await rig.engine.start(ride)
        let exhibition = try XCTUnwrap(rig.plan.track).stopDistances[1]
        let fix = try OnBoardFixtures.fix(along: exhibition, plan: rig.plan, stationary: true)
        rig.location.send(fix)
        rig.clock.set(t(11, 29))
        rig.engine.update()
        XCTAssertEqual(rig.engine.state?.source, .phone)
        XCTAssertEqual(rig.engine.state?.phase, .atStation)
        XCTAssertEqual(rig.engine.state?.currentStop?.id, "EX")
        XCTAssertEqual(rig.engine.state?.expectedArrival, t(11, 57), "5 min late leaving Exhibition")
    }

    /// A train held between stations: iOS sends one stationary fix and then nothing, and the delay keeps growing, so the
    /// arriving tap waits for the train to move.
    func testAStationaryFixBetweenStationsKeepsTheDelayGrowing() async throws {
        let rig = try rig(at: t(11, 50, 20))
        await rig.engine.start(ride)
        let distances = try XCTUnwrap(rig.plan.track).stopDistances
        let held = try OnBoardFixtures.fix(along: distances[5] - 1_400, plan: rig.plan, stationary: true)
        rig.location.send(held)
        rig.clock.set(t(11, 53))
        rig.engine.update()
        let state = try XCTUnwrap(rig.engine.state)
        XCTAssertEqual(state.source, .phone)
        XCTAssertEqual(state.phase, .yourStopNext, "Still held 1.4 km before Clarkson: no arriving tap yet")
        XCTAssertEqual(state.minutesToYourStop, 2)
    }

    /// The live status is read before the first update, so a ride starts with the feed's delay.
    func testARideStartsWithTheFeedsDelay() async throws {
        let rig = try rig(at: t(11, 10), answer: false)
        await rig.data.setStatus(RideStatus(delay: 300))
        await rig.engine.start(ride)
        XCTAssertEqual(rig.engine.state?.expectedArrival, t(11, 57))
    }

    /// A late train with no delay in the feed: until the first fix the timetable only fills in, so a ride started after
    /// the timetable's arrival at your stop neither arrives nor ends, and the phone places the train.
    func testALateTrainIsPlacedByThePhoneNotTheTimetable() async throws {
        let rig = try rig(at: t(11, 55))
        let events = rig.engine.events()
        await rig.engine.start(ride)
        XCTAssertNotEqual(rig.engine.state?.phase, .ended)
        let atUnion = try OnBoardFixtures.fix(along: 0, plan: rig.plan)
        for second in stride(from: 0, through: 15 * 60, by: 10) {
            rig.clock.set(t(11, 55).addingTimeInterval(TimeInterval(second)))
            rig.location.send(atUnion)
        }
        let state = try XCTUnwrap(rig.engine.state)
        XCTAssertEqual(state.phase, .atStation, "Still at Union at 12:10, after the timetable's 11:52 at Clarkson")
        XCTAssertEqual(state.currentStop?.id, "UN")
        XCTAssertEqual(state.stopsLeft, 5)
        XCTAssertEqual(state.expectedArrival, t(12, 45), "53 min late leaving Union")

        rig.engine.end()
        var emitted: [RidePhase] = []
        for await event in events {
            guard case let .phase(phase) = event else { continue }
            emitted.append(phase)
            if phase == .ended { break }
        }
        XCTAssertEqual(emitted, [.atStation, .ended], "No phase is sent before the first fix")
    }

    /// After a minute without a fix the timetable can place the arrival; the phone's next fix short of your stop takes it
    /// back, and the ride ends 10 min after the measured arrival.
    func testAFixTakesBackTheTimetablesArrival() async throws {
        let rig = try rig(at: t(11, 45))
        await rig.engine.start(ride)
        let distances = try XCTUnwrap(rig.plan.track).stopDistances
        let atPortCredit = try OnBoardFixtures.fix(along: distances[4], plan: rig.plan)
        rig.location.send(atPortCredit)
        rig.clock.set(t(11, 53))
        rig.engine.update()
        XCTAssertEqual(rig.engine.state?.source, .timetable)
        XCTAssertEqual(rig.engine.state?.phase, .atYourStop)

        let short = try OnBoardFixtures.fix(along: distances[5] - 2_000, plan: rig.plan)
        rig.location.send(short)
        XCTAssertEqual(rig.engine.state?.phase, .yourStopNext)
        XCTAssertEqual(rig.engine.state?.nextStop?.id, "CL")

        let atClarkson = try OnBoardFixtures.fix(along: distances[5], plan: rig.plan)
        rig.clock.set(t(11, 55))
        rig.location.send(atClarkson)
        XCTAssertEqual(rig.engine.state?.phase, .atYourStop)
        rig.clock.set(t(12, 4))
        rig.location.send(atClarkson)
        XCTAssertEqual(rig.engine.state?.phase, .atYourStop, "The timetable's 11:52 would have ended it at 12:02")
        rig.clock.set(t(12, 5))
        rig.engine.update()
        XCTAssertEqual(rig.engine.state?.phase, .ended)
        XCTAssertEqual(rig.engine.state?.endReason, .arrived)
    }

    /// A fix at your stop after the timetable placed the arrival keeps that arrival, and the offset the first fix there
    /// made: standing at Clarkson does not read as running later and later.
    func testAFixAtYourStopKeepsTheTimetablesArrival() async throws {
        let rig = try rig(at: t(11, 45))
        await rig.engine.start(ride)
        let distances = try XCTUnwrap(rig.plan.track).stopDistances
        rig.location.send(try OnBoardFixtures.fix(along: distances[4], plan: rig.plan))
        rig.clock.set(t(11, 53))
        rig.engine.update()
        XCTAssertEqual(rig.engine.state?.source, .timetable)
        XCTAssertEqual(rig.engine.state?.phase, .atYourStop)

        let atClarkson = try OnBoardFixtures.fix(along: distances[5], plan: rig.plan)
        rig.clock.set(t(11, 54))
        rig.location.send(atClarkson)
        let arrival = try XCTUnwrap(rig.engine.state?.expectedArrival)
        rig.clock.set(t(12, 0))
        rig.location.send(atClarkson)
        XCTAssertEqual(rig.engine.state?.phase, .atYourStop)
        XCTAssertEqual(rig.engine.state?.expectedArrival, arrival, "Standing at Clarkson is not running later")
    }

    /// The arriving tap comes once a ride: the timetable's while the phone was silent counts, and a fix that brings the
    /// train back to Port Credit, 6 min late, does not make a second one.
    func testTheArrivingTapComesOnce() async throws {
        let rig = try rig(at: t(11, 45))
        let events = rig.engine.events()
        await rig.engine.start(ride)
        try drive(rig, to: t(11, 45))
        rig.clock.set(t(11, 51, 10))
        rig.engine.update()
        XCTAssertEqual(rig.engine.state?.source, .timetable)
        XCTAssertEqual(rig.engine.state?.phase, .arriving)

        var phases: [RidePhase] = []
        var time = t(11, 51, 15)
        while time <= t(11, 58, 30) {
            rig.clock.set(time)
            let along = try OnBoardFixtures.along(at: time.addingTimeInterval(-6 * 60), plan: rig.plan)
            let fix = try OnBoardFixtures.fix(along: along, plan: rig.plan)
            rig.location.send(fix)
            let phase = try XCTUnwrap(rig.engine.state).phase
            if phase != phases.last { phases.append(phase) }
            time = time.addingTimeInterval(5)
        }
        XCTAssertEqual(phases, [.atStation, .yourStopNext, .arriving, .atYourStop], "The card still shows arriving")

        rig.engine.end()
        var emitted: [RidePhase] = []
        for await event in events {
            guard case let .phase(phase) = event else { continue }
            emitted.append(phase)
            if phase == .ended { break }
        }
        XCTAssertEqual(emitted, [.atStation, .arriving, .atStation, .yourStopNext, .atYourStop, .ended])
    }

    /// Acceptance: a ride survives a relaunch: it is restored from disk, and the background updates start again without
    /// asking.
    func testARideSurvivesARelaunch() async throws {
        let defaults = UserDefaults.ephemeral()
        let first = try rig(at: t(11, 30), defaults: defaults)
        await first.engine.start(ride)
        try drive(first, to: t(11, 30))
        XCTAssertNotNil(defaults.data(forKey: RideEngine.storageKey))

        // iOS stopped the app and relaunches it.
        let relaunched = try rig(at: t(11, 31), authorized: true, defaults: defaults)
        await relaunched.engine.restore()
        XCTAssertEqual(relaunched.engine.ride, ride)
        XCTAssertEqual(relaunched.location.requests, 0, "A restore never asks for location")
        XCTAssertTrue(relaunched.location.isUpdating, "The background session is created again")
        XCTAssertEqual(relaunched.engine.state?.phase, .riding)
        XCTAssertEqual(relaunched.engine.state?.nextStop?.id, "MI")
        XCTAssertEqual(relaunched.engine.state?.stopsLeft, 4)
        XCTAssertEqual(relaunched.engine.state?.lastUpdate, t(11, 30))
        try drive(relaunched, to: t(11, 33))
        XCTAssertEqual(relaunched.engine.state?.source, .phone)
        XCTAssertEqual(relaunched.engine.state?.nextStop?.id, "LO")
    }

    /// TT-174: the Live Activity's End ride can open a stopped app before its restore has finished: the ride stays ended.
    func testEndRideBeforeTheRestoreFinishedKeepsTheRideEnded() async throws {
        let defaults = UserDefaults.ephemeral()
        let first = try rig(at: t(11, 30), defaults: defaults)
        await first.engine.start(ride)
        let relaunched = try rig(at: t(11, 31), authorized: true, defaults: defaults)
        relaunched.engine.end()
        await relaunched.engine.restore()
        XCTAssertNil(relaunched.engine.ride)
        XCTAssertNil(relaunched.engine.state)
        XCTAssertFalse(relaunched.location.isUpdating)
        XCTAssertNil(defaults.data(forKey: RideEngine.storageKey))
    }

    /// A ride restored long after your stop ends at once.
    func testARideRestoredLongAfterYourStopEnds() async throws {
        let defaults = UserDefaults.ephemeral()
        let first = try rig(at: t(11, 30), defaults: defaults)
        await first.engine.start(ride)
        let later = try rig(at: t(13, 0), authorized: true, defaults: defaults)
        await later.engine.restore()
        XCTAssertEqual(later.engine.state?.phase, .ended)
        XCTAssertEqual(later.engine.state?.endReason, .arrived)
        XCTAssertFalse(later.location.isUpdating)
        XCTAssertNil(defaults.data(forKey: RideEngine.storageKey))
    }

    /// Acceptance: 1 km off the line for 3 min ends the ride; before the train leaves it does not count.
    func testTheRideEndsOffTheLine() async throws {
        let rig = try rig(at: t(11, 12))
        await rig.engine.start(ride)
        for second in stride(from: 0, through: 270, by: 10) {
            rig.clock.set(t(11, 12).addingTimeInterval(TimeInterval(second)))
            let fix = try OnBoardFixtures.fix(along: 0, plan: rig.plan, north: 2_000)
            rig.location.send(fix)
        }
        XCTAssertNotEqual(rig.engine.state?.phase, .ended, "Walking to the station before departure")

        for second in stride(from: 0, through: 170, by: 10) {
            rig.clock.set(t(11, 20).addingTimeInterval(TimeInterval(second)))
            let along = try OnBoardFixtures.along(at: rig.clock.now, plan: rig.plan)
            let fix = try OnBoardFixtures.fix(along: along, plan: rig.plan, north: 2_000)
            rig.location.send(fix)
        }
        XCTAssertNotEqual(rig.engine.state?.phase, .ended)
        rig.clock.set(t(11, 23))
        let offLine = try OnBoardFixtures.fix(along: OnBoardFixtures.along(at: t(11, 23), plan: rig.plan), plan: rig.plan, north: 2_000)
        rig.location.send(offLine)
        XCTAssertEqual(rig.engine.state?.phase, .ended)
        XCTAssertEqual(rig.engine.state?.endReason, .leftTheLine)
        XCTAssertFalse(rig.location.isUpdating)
    }

    /// Acceptance: a cancelled trip ends the ride.
    func testACancelledTripEndsTheRide() async throws {
        let rig = try rig(at: t(11, 20))
        await rig.engine.start(ride)
        await rig.data.setStatus(RideStatus(isCancelled: true))
        await rig.engine.refresh()
        XCTAssertEqual(rig.engine.state?.phase, .ended)
        XCTAssertEqual(rig.engine.state?.endReason, .cancelled)
        XCTAssertNil(rig.defaults.data(forKey: RideEngine.storageKey))
    }

    func testEndRide() async throws {
        let rig = try rig(at: t(11, 20))
        await rig.engine.start(ride)
        rig.engine.end()
        XCTAssertEqual(rig.engine.state?.phase, .ended)
        XCTAssertEqual(rig.engine.state?.endReason, .byRider)
        XCTAssertFalse(rig.location.isUpdating)
        XCTAssertNil(rig.defaults.data(forKey: RideEngine.storageKey))
    }

    /// Acceptance: no location request at launch, or anywhere but a ride start.
    func testLocationIsAskedOnlyWhenARideStarts() async throws {
        let rig = try rig(at: t(11, 10))
        await rig.engine.restore()
        XCTAssertNil(rig.engine.ride)
        XCTAssertEqual(rig.location.requests, 0, "Launch asks nothing")
        XCTAssertFalse(rig.location.isUpdating)
        await rig.engine.start(ride)
        XCTAssertEqual(rig.location.requests, 1)
    }

    /// Location denied: the ride runs on the timetable, corrected by the feed's delay (D36).
    func testWithoutLocationTheRideRunsOnTheTimetable() async throws {
        let rig = try rig(at: t(11, 23, 45), answer: false)
        await rig.engine.start(ride)
        XCTAssertFalse(rig.location.isUpdating)
        XCTAssertEqual(rig.engine.state?.source, .timetable)
        XCTAssertNil(rig.engine.state?.lastUpdate)
        XCTAssertEqual(rig.engine.state?.phase, .atStation)
        XCTAssertEqual(rig.engine.state?.currentStop?.id, "EX")

        rig.clock.set(t(11, 28))
        await rig.data.setStatus(RideStatus(delay: 120))
        await rig.engine.refresh()
        XCTAssertEqual(rig.engine.state?.phase, .riding)
        XCTAssertEqual(rig.engine.state?.nextStop?.id, "MI")
        XCTAssertEqual(rig.engine.state?.expectedArrival, t(11, 54))
        XCTAssertEqual(rig.engine.state?.minutesToYourStop, 26)
    }
}
