import XCTest
@testable import TrainTimes

/// TT-251 (D127): the wrong train check on `WrongWorld`, with fakes for the timetable, the live stops and the position
/// history, the shared fake location, a recording presenter and a clock in seconds after L. No timer: tests call `look()`.
@MainActor
final class WrongTrainCheckTests: XCTestCase {
    private typealias World = WrongWorld

    override func tearDown() async throws {
        Analytics.tracker = nil
        try await super.tearDown()
    }

    /// T comes 6 km late from the west, at 25 m/s.
    private func lateT(_ rig: CheckRig) -> (Double) -> GeoPoint? {
        { [unowned rig] in rig.point("T", -6_000 - 25 * max(0, -$0)) }
    }

    /// The phone leaves O with the westbound 5 min before L, while T is still on its way.
    private func wrongWay(_ rig: CheckRig) async {
        await rig.stops("WEST", ["W1", "W2"])
        let phone = rig.leaving("WEST", at: -300)
        await rig.play(from: -600, to: 120, phone: phone, trains: ["WEST": phone, "T": lateT(rig)], until: {
            rig.presenter.warning != nil
        })
    }

    // MARK: Opening

    func testTheWatchArmingOpensItAndTheWrongWayRaisesTheWarning() async throws {
        let rig = CheckRig(candidates: [World.westbound(after: -300), World.express(after: 900)])
        await rig.armWatch()
        XCTAssertEqual(rig.check.checked, rig.ride)
        XCTAssertEqual(rig.check.source, .alert)
        XCTAssertTrue(rig.check.keepsLocation)
        await wrongWay(rig)

        let warning = try XCTUnwrap(rig.presenter.warning)
        XCTAssertEqual(rig.presenter.raised.count, 1)
        XCTAssertEqual(warning.ride, rig.ride)
        XCTAssertEqual(warning.reason, .wrongWay)
        XCTAssertEqual(warning.evidence, .feed)
        XCTAssertEqual(warning.source, .alert)
        XCTAssertEqual(warning.stopName, "D")
        XCTAssertEqual(warning.nextStopId, "W1")
        XCTAssertEqual(warning.nextStopName, "W1")
        XCTAssertEqual(warning.nextStopTime, rig.time(300))
        XCTAssertEqual(warning.expires, rig.time(420), "2 min after its next stop")
        XCTAssertFalse(warning.isDemo)
        XCTAssertGreaterThan(warning.secondsAfter, 60)
        XCTAssertTrue(rig.check.hasWarned(rig.ride), "The watch finishes wrong_train")
        XCTAssertTrue(rig.check.holdsLeftTheLine(of: rig.ride), "A ride would not end as left the line meanwhile")
        XCTAssertEqual(rig.check.checked, rig.ride, "It keeps looking while the warning shows")
    }

    func testEachGateKeepsItClosed() async {
        let gates: [(String, (CheckRig) -> Void)] = [
            ("location off", { $0.location.isAuthorized = false }),
            ("Precise Location off", { $0.location.isPrecise = false }),
            ("Mock time or a demo", { $0.testing = true }),
            ("Automatic ride off, no ride", { $0.autoRideOff = true }),
            ("declined today", { $0.declined.insert($0.ride.tripKey) }),
            ("I’m fine today", { WrongTrainStore(defaults: $0.defaults).storeFine($0.ride) }),
        ]
        for (name, close) in gates {
            let rig = CheckRig(candidates: [World.westbound()])
            close(rig)
            await rig.armWatch()
            XCTAssertNil(rig.check.checked, name)
        }
        let rig = CheckRig(candidates: [World.westbound()])
        let plain = RidePlan(stops: rig.plan.stops, track: nil)
        rig.check.watchArmed(rig.ride, plan: plain, departure: World.departure, reader: rig.location)
        await rig.settle()
        XCTAssertNil(rig.check.checked, "no track")
    }

    func testATappedRideOpensItAndAnAutomaticOneNever() async {
        let rig = CheckRig(candidates: [World.westbound()])
        rig.rideRunning = true
        rig.check.rideUpdated(rig.ride, source: .onBoard, plan: rig.plan, phase: .atStation)
        await rig.settle()
        XCTAssertEqual(rig.check.source, .onBoard)

        let yes = CheckRig(candidates: [World.westbound()])
        yes.rideRunning = true
        yes.check.rideUpdated(yes.ride, source: .departure, plan: yes.plan, phase: .atStation)
        await yes.settle()
        XCTAssertEqual(yes.check.source, .departure)

        let auto = CheckRig(candidates: [World.westbound()])
        auto.rideRunning = true
        auto.check.rideUpdated(auto.ride, source: .auto, plan: auto.plan, phase: .riding)
        await auto.settle()
        XCTAssertNil(auto.check.checked, "its start proved T")
    }

    func testARideTappedOnTheAlertedTrainTiesTheOpenCheckToIt() async {
        let rig = CheckRig(candidates: [World.westbound()])
        await rig.armWatch()
        rig.rideRunning = true
        rig.check.rideUpdated(rig.ride, source: .onBoard, plan: rig.plan, phase: .atStation)
        XCTAssertEqual(rig.check.source, .onBoard)
        rig.check.rideEnded(rig.ride)
        XCTAssertNil(rig.check.checked, "its ride ended")
        XCTAssertEqual(rig.check.lastCheck?.why, .rideEnded)
    }

    func testAnAutomaticStartOnTheAlertedTrainClosesItWithTheTrain() async {
        let rig = CheckRig(candidates: [World.westbound()])
        await rig.armWatch()
        rig.check.watchEnded(rig.ride, outcome: .started)
        XCTAssertNil(rig.check.checked)
        XCTAssertEqual(rig.check.lastCheck?.outcome, .withTrain)
    }

    func testConsiderOpensForAnAlertedTrainAfterItLeftAndRunsTheUpdates() async {
        let rig = CheckRig(at: 300, candidates: [World.westbound()])
        let trip = Trip(
            key: rig.ride.tripKey, scheduledDeparture: World.departure, scheduledArrival: rig.time(480), platform: .pending,
            tags: []
        )
        let route = Route(from: Station(id: "O", name: "O"), to: Station(id: "D", name: "D"), line: nil)
        rig.alerted = [AutoRideTrain(
            candidate: AutoRideWatch.Candidate(route: route, trip: trip, departure: World.departure, arrival: rig.time(480)),
            plan: rig.plan
        )]
        await rig.check.consider()
        await rig.settle()
        XCTAssertEqual(rig.check.checked, rig.ride)
        XCTAssertTrue(rig.location.isUpdating, "No watch and no ride: the check runs the updates")
        XCTAssertEqual(rig.location.sessionsStarted, 1)

        // The phone walks off: the check closes and stops them.
        rig.phone(at: rig.point("T", 0))
        rig.at(310)
        rig.phone(at: rig.point("T", 0, north: 500))
        XCTAssertNil(rig.check.checked)
        XCTAssertEqual(rig.check.lastCheck?.outcome, .stayed)
        XCTAssertEqual(rig.check.lastCheck?.why, .walkedAway)
        XCTAssertFalse(rig.location.isUpdating)

        // Read at most every 30 s, and a train checked today is not opened again.
        let reads = rig.alertedReads
        await rig.check.consider()
        XCTAssertEqual(rig.alertedReads, reads)
        rig.at(400)
        await rig.check.consider()
        await rig.settle()
        XCTAssertNil(rig.check.checked)
    }

    // MARK: The tail

    func testTheWatchFinishingHandsTheLocationOverAndItStaysOpenAtTheStation() async {
        let rig = CheckRig(candidates: [World.westbound(after: 600)])
        rig.location.startUpdates { _ in }
        await rig.armWatch()
        rig.check.watchEnded(rig.ride, outcome: .notOnBoard)
        XCTAssertTrue(rig.location.isUpdating)
        XCTAssertEqual(rig.location.sessionsStarted, 1, "The callback is swapped, the session kept")
        XCTAssertTrue(rig.check.keepsLocation)

        // T leaves at L without the phone, which stays on the platform until L + 30 min.
        await rig.play(from: -600, to: 1_799, phone: { [unowned rig] _ in rig.point("T", 0) }, trains: [
            "T": { [unowned rig] in rig.point("T", World.moving($0, from: 0)) },
        ])
        XCTAssertEqual(rig.check.checked, rig.ride, "Open at the station up to L + 30 min")
        rig.at(1_800)
        await rig.check.look()
        XCTAssertNil(rig.check.checked)
        XCTAssertEqual(rig.check.lastCheck?.outcome, .stayed)
        XCTAssertEqual(rig.check.lastCheck?.why, .limit)
        XCTAssertFalse(rig.location.isUpdating, "Closed with no ride: the updates stop")
    }

    func testTheMissedTrainWarnsWhenThePhoneLeavesLaterTheOtherWay() async throws {
        let rig = CheckRig(candidates: [World.westbound(after: 600)])
        await rig.armWatch()
        rig.check.watchEnded(rig.ride, outcome: .notOnBoard)
        await rig.stops("WEST", ["W1", "W2"])
        let phone = rig.leaving("WEST", at: 600)
        await rig.play(from: -120, to: 900, phone: phone, trains: [
            "WEST": phone, "T": { [unowned rig] in rig.point("T", World.moving($0, from: 0)) },
        ], until: { rig.presenter.warning != nil })
        let warning = try XCTUnwrap(rig.presenter.warning)
        XCTAssertEqual(warning.reason, .wrongWay)
        XCTAssertGreaterThan(rig.clock.now, rig.time(600))
    }

    func testThePhoneNeverNearTheStationOnceTLeftClosesIt() async {
        let rig = CheckRig(candidates: [World.westbound()])
        await rig.armWatch()
        await rig.play(from: -600, to: 300, phone: { [unowned rig] _ in rig.point("T", -3_000, north: 2_000) })
        XCTAssertNil(rig.check.checked)
        XCTAssertEqual(rig.check.lastCheck?.outcome, .stayed)
        XCTAssertGreaterThanOrEqual(rig.clock.now, rig.time(WrongTrainCheck.leftAfter))
    }

    // MARK: Closing

    func testWithTheTrainClosesItAndWithdrawsAWarningThatWasUp() async throws {
        let recorder = RecordingAnalytics.install()
        let rig = CheckRig(at: -300, candidates: [World.westbound(after: -300), World.express(after: 900)])
        await rig.armWatch()
        _ = rig.presenter.raise(DemoRide.wrongTrainWarning(for: rig.ride), now: rig.clock.now, rate: 1)
        let phone: (Double) -> GeoPoint = { [unowned rig] in rig.point("T", World.moving($0, from: 0)) }
        await rig.play(from: -300, to: 300, phone: phone, trains: ["T": phone])
        XCTAssertNil(rig.check.checked)
        XCTAssertEqual(rig.presenter.withdrawals, 1)
        XCTAssertEqual(rig.check.lastCheck?.outcome, .withTrain)
        XCTAssertNotNil(rig.check.lastCheck?.seconds)
        let event = try XCTUnwrap(recorder.events.first { $0.name == "wrong_train_checked" })
        XCTAssertEqual(event.properties["outcome"], .string("with_train"))
        XCTAssertEqual(event.properties["source"], .string("alert"))
        XCTAssertNotNil(event.properties["seconds"])
    }

    func testItClosesWhenTheRideReachesTheStop() async {
        let rig = CheckRig(candidates: [World.westbound()])
        rig.rideRunning = true
        rig.check.rideUpdated(rig.ride, source: .onBoard, plan: rig.plan, phase: .atStation)
        await rig.settle()
        rig.check.rideUpdated(rig.ride, source: .onBoard, plan: rig.plan, phase: .atYourStop)
        XCTAssertNil(rig.check.checked)
        XCTAssertEqual(rig.check.lastCheck?.why, .arrived)
    }

    func testAWarningThatEndsClosesItAsWarned() async {
        let rig = CheckRig(candidates: [World.westbound(after: -300), World.express(after: 900)])
        await rig.armWatch()
        await wrongWay(rig)
        rig.presenter.answer()
        await rig.check.look()
        XCTAssertNil(rig.check.checked)
        XCTAssertEqual(rig.check.lastCheck?.outcome, .warned)
        XCTAssertEqual(rig.check.lastCheck?.reason, .wrongWay)
    }

    func testCheckedOncePerTrainAndDay() async {
        let recorder = RecordingAnalytics.install()
        let rig = CheckRig(candidates: [World.westbound()])
        rig.rideRunning = true
        for _ in 0..<2 {
            rig.check.rideUpdated(rig.ride, source: .onBoard, plan: rig.plan, phase: .atStation)
            await rig.settle()
            rig.check.rideEnded(rig.ride)
        }
        XCTAssertEqual(recorder.events.filter { $0.name == "wrong_train_checked" }.count, 1)
        XCTAssertEqual(rig.check.lastCheck?.source, .onBoard)
    }

    // MARK: Paused fixes and the feed

    func testPausedFixesRestartTheUpdatesOnceTLeftAtMostEvery30Seconds() async {
        let rig = CheckRig(at: -60, candidates: [World.westbound()])
        rig.location.startUpdates { _ in }
        await rig.armWatch()
        rig.phone(at: rig.point("T", 0), stationary: true)
        rig.at(-30)
        await rig.check.look()
        XCTAssertEqual(rig.location.restarts, 0, "Not before T is due to leave")
        rig.at(15)
        await rig.check.look()
        XCTAssertEqual(rig.location.restarts, 1, "No good fix for 30 s once T left")
        rig.at(30)
        await rig.check.look()
        XCTAssertEqual(rig.location.restarts, 1, "At most once per 30 s")
        rig.at(45)
        await rig.check.look()
        XCTAssertEqual(rig.location.restarts, 2)
        XCTAssertEqual(rig.check.checked, rig.ride, "Never read as quiet or as with the train")
    }

    func testTheFastFeedFromTheFirstMovingFixOnly() async {
        let rig = CheckRig(candidates: [World.westbound(after: -300), World.express(after: 900)])
        await rig.armWatch()
        await rig.stops("WEST", ["W1", "W2"])
        let phone = rig.leaving("WEST", at: -300)
        let trains = ["WEST": phone, "T": lateT(rig)]
        await rig.play(from: -600, to: -300, phone: phone, trains: trains)
        let standing = await rig.positions.fastReads
        XCTAssertEqual(standing, 0, "Standing at O: today's pace")
        await rig.play(from: -299, to: 120, phone: phone, trains: trains, until: { rig.presenter.warning != nil })
        let moving = await rig.positions.fastReads
        XCTAssertGreaterThan(moving, 0)
    }

    func testItFollowsTheTrainBeforeTheProofIsComplete() async {
        let rig = CheckRig(candidates: [World.westbound(after: -300), World.express(after: 900)])
        await rig.armWatch()
        await rig.stops("WEST", ["W1", "W2"])
        let phone = rig.leaving("WEST", at: -300)
        var followed: Date?
        await rig.play(from: -600, to: 120, phone: phone, trains: ["WEST": phone, "T": lateT(rig)], until: {
            if followed == nil { followed = rig.check.followingSince(rig.ride) }
            return rig.presenter.warning != nil
        })
        XCTAssertNotNil(followed, "It follows the westbound before the proof is complete")
    }
}
