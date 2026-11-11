import XCTest
@testable import TrainTimes

/// TT-173: the arriving nudge. Notifications scheduled from the timetable and moved with the estimate under the same
/// identifiers, the taps on the engine's phases, and the haptic pattern.
@MainActor
final class ArrivalNudgeTests: XCTestCase {
    private let ride = OnBoardFixtures.ride
    private let clarkson = Station(id: "CL", name: "Clarkson GO")

    private func t(_ hours: Int, _ minutes: Int, _ seconds: Int = 0) -> Date {
        OnBoardFixtures.time(hours, minutes, seconds)
    }

    private struct Rig {
        let nudge: ArrivalNudge
        let notifications: FakeRideNotifications
        let feedback: FakeArrivalFeedback
    }

    private func rig(rate: Double = 1) -> Rig {
        let notifications = FakeRideNotifications()
        let feedback = FakeArrivalFeedback()
        return Rig(nudge: ArrivalNudge(notifications: notifications, feedback: feedback, rate: rate), notifications: notifications, feedback: feedback)
    }

    private func state(_ phase: RidePhase, arrival: Date) -> RideState {
        RideState(
            phase: phase, currentStop: nil, nextStop: clarkson, stopsLeft: 1, minutesToYourStop: 1, expectedArrival: arrival,
            source: .phone, lastUpdate: nil
        )
    }

    private func send(_ event: RideEvent, to rig: Rig, at now: Date) {
        rig.nudge.handle(event, ride: ride, destination: clarkson, now: now)
    }

    /// Lets the nudge's task take the engine's events.
    private func until(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    // MARK: Notifications

    func testARideSchedulesBothNotificationsFromTheTimetable() {
        let rig = rig()
        send(.update(state(.atStation, arrival: t(11, 52))), to: rig, at: t(11, 17))

        XCTAssertEqual(rig.notifications.pending.count, 2)
        let arriving = rig.notifications.pending[rig.nudge.id(.arriving)]
        XCTAssertEqual(arriving?.title, "Arriving at Clarkson in 1 min")
        XCTAssertEqual(arriving?.body, "Your stop is next. Get ready to step off.")
        XCTAssertEqual(arriving?.delay ?? 0, 34 * 60, accuracy: 0.5)
        let here = rig.notifications.pending[rig.nudge.id(.here)]
        XCTAssertEqual(here?.title, "This is Clarkson")
        XCTAssertEqual(here?.body, "Your stop. Doors are open.")
        XCTAssertEqual(here?.delay ?? 0, 35 * 60, accuracy: 0.5)
    }

    /// Acceptance: a changed estimate replaces the pending notification instead of adding a second.
    func testAMovedEstimateReplacesThePendingNotifications() {
        let rig = rig()
        send(.update(state(.riding, arrival: t(11, 52))), to: rig, at: t(11, 17))
        send(.update(state(.riding, arrival: t(11, 55))), to: rig, at: t(11, 30))

        XCTAssertEqual(rig.notifications.added.count, 4)
        XCTAssertEqual(Set(rig.notifications.added.map(\.id)).count, 2, "the same two identifiers")
        XCTAssertEqual(rig.notifications.pending.count, 2)
        XCTAssertEqual(rig.notifications.pending[rig.nudge.id(.arriving)]?.delay ?? 0, 24 * 60, accuracy: 0.5)
        XCTAssertEqual(rig.notifications.pending[rig.nudge.id(.here)]?.delay ?? 0, 25 * 60, accuracy: 0.5)
    }

    /// A fix every second moves the estimate a little each time; the notifications move only for 15 s or more.
    func testASmallMoveLeavesThePendingNotifications() {
        let rig = rig()
        send(.update(state(.riding, arrival: t(11, 52))), to: rig, at: t(11, 17))
        send(.update(state(.riding, arrival: t(11, 52, 10))), to: rig, at: t(11, 18))
        XCTAssertEqual(rig.notifications.added.count, 2)
    }

    func testANotificationThatWentOffIsNotScheduledAgain() {
        let rig = rig()
        send(.update(state(.yourStopNext, arrival: t(11, 52))), to: rig, at: t(11, 40))
        // Past 11:51, "Arriving" has gone off; the train then runs two minutes late.
        send(.update(state(.arriving, arrival: t(11, 54))), to: rig, at: t(11, 51, 30))

        XCTAssertEqual(rig.notifications.added.map(\.id), [rig.nudge.id(.arriving), rig.nudge.id(.here), rig.nudge.id(.here)])
        XCTAssertEqual(rig.notifications.added.last?.delay ?? 0, 150, accuracy: 0.5)
    }

    func testATrainAheadOfItsEstimateSendsArrivingAtOnce() {
        let rig = rig()
        send(.update(state(.yourStopNext, arrival: t(11, 52))), to: rig, at: t(11, 40))
        send(.update(state(.yourStopNext, arrival: t(11, 51, 20))), to: rig, at: t(11, 50, 30))

        XCTAssertEqual(rig.notifications.pending[rig.nudge.id(.arriving)]?.delay, 1)
    }

    /// Acceptance: with location lost the engine falls back to the timetable with the last measured offset, and the
    /// notifications stay where they are, so they still go off on the timetable.
    func testWithLocationLostTheTimetableNotificationsStay() async throws {
        let plan = try OnBoardFixtures.plan()
        let clock = TestClock(now: t(11, 15))
        let location = FakeLocation(authorized: true)
        let engine = RideEngine(data: FakeRideData(plan: plan), location: location, clock: clock, defaults: nil, tickInterval: nil)
        let rig = rig()
        rig.nudge.follow(engine)
        let started = await engine.start(ride)
        XCTAssertTrue(started)
        for minute in stride(from: 16, through: 30, by: 2) {
            clock.set(t(11, minute))
            location.send(try OnBoardFixtures.fix(along: OnBoardFixtures.along(at: t(11, minute), plan: plan), plan: plan))
        }
        await until { rig.notifications.added.count >= 2 }
        XCTAssertEqual(rig.notifications.pending.count, 2)
        let scheduled = rig.notifications.added.count

        // No fix for three minutes: the timetable places the train.
        clock.set(t(11, 33))
        engine.update()
        await until { engine.state?.source == .timetable }
        await until { false }
        XCTAssertEqual(engine.state?.source, .timetable)
        XCTAssertEqual(rig.notifications.added.count, scheduled, "nothing moved, nothing was removed")
        XCTAssertTrue(rig.notifications.removed.isEmpty)
        XCTAssertEqual(rig.notifications.pending.count, 2)
    }

    func testEndingTheRideRemovesItsPendingNotifications() {
        let rig = rig()
        send(.update(state(.riding, arrival: t(11, 52))), to: rig, at: t(11, 17))
        let ids = [rig.nudge.id(.arriving), rig.nudge.id(.here)]
        send(.phase(.ended), to: rig, at: t(11, 20))

        XCTAssertEqual(Set(rig.notifications.removed), Set(ids))
        XCTAssertTrue(rig.notifications.pending.isEmpty)
    }

    func testTheDemoRideSchedulesInRealSeconds() {
        let rig = rig(rate: DemoRide.speed)
        send(.update(state(.riding, arrival: t(17, 43))), to: rig, at: t(17, 32))

        XCTAssertEqual(rig.notifications.pending[rig.nudge.id(.arriving)]?.delay ?? 0, 100, accuracy: 0.5)
        XCTAssertEqual(rig.notifications.pending[rig.nudge.id(.here)]?.delay ?? 0, 110, accuracy: 0.5)
    }

    // MARK: Your stop

    func testReachingYourStopEarlySaysThisIsAtOnce() {
        let rig = rig()
        send(.update(state(.yourStopNext, arrival: t(11, 52))), to: rig, at: t(11, 40))
        let arriving = rig.nudge.id(.arriving), here = rig.nudge.id(.here)
        send(.phase(.atYourStop), to: rig, at: t(11, 50))

        XCTAssertEqual(rig.notifications.removed, [arriving], "\"Arriving\" would come after the train got there")
        XCTAssertEqual(rig.notifications.pending.keys.sorted(), [here])
        XCTAssertEqual(rig.notifications.pending[here]?.delay, 1)
        XCTAssertEqual(rig.feedback.stops, 1)
    }

    func testARideRestoredAtYourStopNeitherTapsNorNotifies() {
        let rig = rig()
        send(.phase(.atYourStop), to: rig, at: t(11, 55))
        send(.update(state(.atYourStop, arrival: t(11, 52))), to: rig, at: t(11, 55))

        XCTAssertTrue(rig.notifications.added.isEmpty)
        XCTAssertEqual(rig.feedback.stops, 0)
    }

    // MARK: Taps

    func testArrivingTapsOnceAndYourStopOnce() {
        let rig = rig()
        send(.update(state(.yourStopNext, arrival: t(11, 52))), to: rig, at: t(11, 48))
        send(.phase(.arriving), to: rig, at: t(11, 51))
        XCTAssertEqual(rig.feedback.arrivals, 1)
        XCTAssertEqual(rig.feedback.stops, 0)
        send(.phase(.atYourStop), to: rig, at: t(11, 52))
        XCTAssertEqual(rig.feedback.arrivals, 1)
        XCTAssertEqual(rig.feedback.stops, 1)
    }

    /// Acceptance: the demo ride with the app open taps about a minute before Clarkson, as the card turns green, and
    /// once at Clarkson; its notifications run on the demo's 6x clock.
    func testTheDemoRideTapsAMinuteBeforeClarksonAndAtIt() async {
        let notifications = FakeRideNotifications()
        let feedback = FakeArrivalFeedback()
        let rig = await DemoRideRig.started {
            ArrivalNudge(notifications: notifications, feedback: feedback, rate: DemoRide.speed)
        }
        await until { notifications.pending.count == 2 }
        XCTAssertEqual(notifications.added.first?.delay ?? 0, 100, accuracy: 3, "5:42 PM on the demo clock")

        rig.drive(to: DemoRideRig.time(17, 41, 50))
        await until { false }
        XCTAssertEqual(feedback.arrivals, 0)

        rig.drive(to: DemoRideRig.time(17, 42, 10))
        await until { feedback.arrivals == 1 }
        XCTAssertEqual(rig.engine?.state?.phase, .arriving)
        XCTAssertEqual(feedback.arrivals, 1)

        rig.drive(to: DemoRideRig.time(17, 43))
        await until { feedback.stops == 1 }
        XCTAssertEqual(rig.engine?.state?.phase, .atYourStop)
        XCTAssertEqual(feedback.stops, 1)
        XCTAssertEqual(feedback.arrivals, 1)
    }

    func testTurningTheDemoOffRemovesItsPendingNotifications() async {
        let notifications = FakeRideNotifications()
        let rig = await DemoRideRig.started {
            ArrivalNudge(notifications: notifications, feedback: FakeArrivalFeedback(), rate: DemoRide.speed)
        }
        await until { notifications.pending.count == 2 }
        XCTAssertEqual(notifications.pending.count, 2)

        await rig.onBoard.setDemo(false)
        XCTAssertEqual(notifications.removed.count, 2)
        XCTAssertTrue(notifications.pending.isEmpty)
    }

    // MARK: Haptics

    func testTheArrivingPatternIsThreeStrongTapsThenAFadingRumble() throws {
        let pattern = ArrivingHaptics.arriving
        let taps = pattern.events.filter { $0.kind == .transient }
        XCTAssertEqual(taps.map(\.time), [0, 0.15, 0.3])
        XCTAssertTrue(taps.allSatisfy { $0.intensity == 1 })
        let rumble = try XCTUnwrap(pattern.events.first { $0.kind == .continuous })
        XCTAssertEqual(pattern.events.count, 4)
        XCTAssertGreaterThan(rumble.time, 0.3, "after the third tap")
        XCTAssertEqual(rumble.duration, 0.6)
        let fade = try XCTUnwrap(pattern.fade)
        XCTAssertEqual(fade.time, rumble.time)
        XCTAssertEqual(fade.points.map(\.value), [0.8, 0.3])
        XCTAssertEqual(fade.points.map(\.time), [0, 0.6])
        XCTAssertNoThrow(try ArrivingHaptics.pattern(pattern))
    }

    func testYourStopIsOneMediumTap() {
        XCTAssertEqual(ArrivingHaptics.atYourStop.events.count, 1)
        XCTAssertEqual(ArrivingHaptics.atYourStop.events.first?.kind, .transient)
        XCTAssertNil(ArrivingHaptics.atYourStop.fade)
        XCTAssertNoThrow(try ArrivingHaptics.pattern(ArrivingHaptics.atYourStop))
    }
}
