import XCTest
@testable import TrainTimes

/// TT-242 (D120): the automatic ride's watch on the On board tests' train (`WatchRig`): when it arms, the hold's reports
/// and their retries, the start through the app's engine, the outcomes and their reports, a relaunch, and the gate that
/// keeps real trains off in this part.
@MainActor
final class AutoRideWatchTests: XCTestCase {
    override func tearDown() async throws {
        Analytics.tracker = nil
        try await super.tearDown()
    }

    private func checks(_ recorder: RecordingAnalytics) -> [AnalyticsEvent] {
        recorder.events.filter { $0.name == "auto_ride_checked" }
    }

    // MARK: Arming

    /// The gate: real trains stay off until TT-243.
    func testRealTrainsStayOffBehindTheGate() async throws {
        XCTAssertFalse(AutoRideWatch.isLive)
        let rig = try WatchRig(live: AutoRideWatch.isLive)
        await rig.arm()
        XCTAssertNil(rig.watch.watched)
        XCTAssertFalse(rig.watch.mayArm)
        XCTAssertFalse(rig.location.isUpdating)
        XCTAssertNil(rig.holder.heldRide)
        XCTAssertTrue(rig.holder.reports.isEmpty)
    }

    /// It arms for an alerted train from L − 30 min to L + 2 min, reads location and holds the train.
    func testItArmsForTheAlertedTrainInItsWindow() async throws {
        let rig = try WatchRig(at: -600)
        await rig.arm()
        XCTAssertEqual(rig.watch.watched?.ride, rig.ride)
        XCTAssertEqual(rig.watch.watched?.armedLate, false)
        XCTAssertTrue(rig.location.isUpdating)
        XCTAssertEqual(rig.location.requests, 0, "The watch never asks")
        XCTAssertEqual(rig.holder.heldRide, rig.ride, "No silent asked goes for the held train")
        XCTAssertEqual(rig.store.saved?.ride, rig.ride, "Its train is kept for a relaunch")
    }

    func testItDoesNotArmOutsideItsWindow() async throws {
        let recorder = RecordingAnalytics.install()
        let early = try WatchRig(at: -31 * 60)
        await early.arm()
        XCTAssertNil(early.watch.watched)
        let late = try WatchRig(at: 3 * 60)
        await late.arm()
        XCTAssertNil(late.watch.watched)
        XCTAssertTrue(checks(recorder).isEmpty, "Outside its window a train is not counted")
    }

    /// Armed at or after L, the covered form counts at any station.
    func testAWatchArmedAfterTheTrainsTimeIsArmedLate() async throws {
        let rig = try WatchRig(at: 60)
        await rig.arm()
        XCTAssertEqual(rig.watch.watched?.armedLate, true)
    }

    /// A gate that keeps an alerted train from arming counts once as `not_armed`.
    func testAGateCountsOnceAsNotArmed() async throws {
        let recorder = RecordingAnalytics.install()
        let rig = try WatchRig(at: -600)
        rig.location.isPrecise = false
        await rig.arm()
        await rig.arm()
        XCTAssertNil(rig.watch.watched)
        XCTAssertEqual(rig.watch.lastCheck?.outcome, .notArmed)
        XCTAssertEqual(checks(recorder).count, 1)
        XCTAssertEqual(checks(recorder).first?.properties["outcome"], .string("not_armed"))

        // Precise Location back: it arms, and the train is not counted a second time when the watch ends.
        rig.location.isPrecise = true
        await rig.arm()
        XCTAssertNotNil(rig.watch.watched)
        rig.watch.stop()
        XCTAssertEqual(checks(recorder).count, 1)
    }

    func testMockTimeOrADemoKeepsItFromArming() async throws {
        let rig = try WatchRig(at: -600)
        rig.testing = true
        await rig.arm()
        XCTAssertNil(rig.watch.watched)
        XCTAssertEqual(rig.watch.lastCheck?.outcome, .notArmed)
    }

    func testARideShorterThanEightMinutesNeverArms() async throws {
        let rig = try WatchRig(at: -600)
        let short = AutoRideWatch.Candidate(
            route: rig.route, trip: rig.trip, departure: rig.departure, arrival: rig.departure.addingTimeInterval(7 * 60)
        )
        await rig.watch.consider([short])
        XCTAssertNil(rig.watch.watched)
        XCTAssertEqual(rig.watch.lastCheck?.outcome, .notArmed)
    }

    func testADeclinedTrainOrARunningRideNeverArms() async throws {
        let declined = try WatchRig(at: -600)
        declined.declined = [declined.ride.tripKey]
        await declined.arm()
        XCTAssertNil(declined.watch.watched)

        let riding = try WatchRig(at: -600)
        await riding.engine.start(riding.ride, source: .onBoard)
        await riding.arm()
        XCTAssertNil(riding.watch.watched)
    }

    /// One train at a time, and a train whose watch finished today is not watched again.
    func testOneTrainAtATimeAndOncePerDay() async throws {
        let rig = try WatchRig(at: -600)
        await rig.arm()
        let first = rig.watch.watched?.armedAt
        rig.at(-590)
        await rig.arm()
        XCTAssertEqual(rig.watch.watched?.armedAt, first, "Already watching: the second offer changes nothing")
        rig.watch.stop()
        await rig.arm()
        XCTAssertNil(rig.watch.watched, "Finished today")
    }

    // MARK: The hold

    /// With the train's card on the phone, `holds: true` goes at once; the server has it, so it is not sent again.
    func testTheHoldGoesAtOnceWithTheCardOnThePhone() async throws {
        let rig = try WatchRig(at: -600)
        rig.holder.departureRide = rig.ride
        await rig.arm()
        await rig.eventually { rig.holder.reports.count == 1 }
        XCTAssertEqual(rig.holder.holds, [true])
        XCTAssertEqual(rig.watch.watched?.holdReachedAt, rig.time(-600))
        rig.at(-585)
        await rig.watch.look()
        XCTAssertEqual(rig.holder.reports.count, 1)
    }

    /// With no card, `holds: true` goes from L − 2 min by the clock.
    func testWithNoCardTheHoldGoesFromTwoMinutesBefore() async throws {
        let rig = try WatchRig(at: -600)
        await rig.arm()
        rig.at(-135)
        await rig.watch.look()
        XCTAssertTrue(rig.holder.reports.isEmpty)
        rig.at(-120)
        await rig.watch.look()
        XCTAssertEqual(rig.holder.holds, [true])
    }

    /// A report the server did not get goes again on the next look, until it has it.
    func testTheHoldIsSentAgainUntilTheServerHasIt() async throws {
        let rig = try WatchRig(at: -600)
        rig.holder.answers = [false, false]
        await rig.arm()
        for second in [-120.0, -105, -90, -75] {
            rig.at(second)
            await rig.watch.look()
        }
        XCTAssertEqual(rig.holder.holds, [true, true, true])
        XCTAssertEqual(rig.watch.watched?.holdReachedAt, rig.time(-90))
    }

    // MARK: Outcomes

    /// Acceptance: the phone leaves Union with the train and GO agrees: the ride starts by itself on the app's engine,
    /// asking for nothing and keeping the one location session, and the card hands itself off.
    func testTheRideStartsByItselfWhenThePhoneLeavesWithTheTrain() async throws {
        let recorder = RecordingAnalytics.install()
        let rig = try WatchRig(at: -300)
        rig.holder.departureRide = rig.ride
        await rig.arm()
        await rig.play(from: -299, to: 240)
        await rig.eventually { rig.watch.started != nil }

        XCTAssertEqual(rig.watch.started?.ride, rig.ride)
        XCTAssertEqual(rig.engine.ride, rig.ride)
        XCTAssertEqual(rig.engine.startSource, .auto)
        XCTAssertEqual(rig.location.requests, 0, "An automatic start asks for nothing")
        XCTAssertEqual(rig.location.sessionsStarted, 1, "The ride keeps the watch's session")
        XCTAssertTrue(rig.location.isUpdating)
        XCTAssertNil(rig.watch.watched)
        XCTAssertNil(rig.holder.heldRide)
        XCTAssertNil(rig.store.saved)
        XCTAssertEqual(rig.replans, 1, "The arriving nudge plans for the new ride")
        XCTAssertFalse(rig.holder.reports.contains { $0.handedOff }, "The card on the phone hands itself off")

        let check = try XCTUnwrap(rig.watch.lastCheck)
        XCTAssertEqual(check.outcome, .started)
        let seconds = try XCTUnwrap(check.secondsAfter)
        XCTAssertTrue((90...200).contains(seconds), "\(seconds) s")
        let started = try XCTUnwrap(recorder.events.first { $0.name == "ride_started" })
        XCTAssertEqual(started.properties["source"], .string("auto"))
        XCTAssertEqual(started.properties["demo"], .bool(false))
        XCTAssertEqual(started.properties["seconds_after"], .int(seconds))
        XCTAssertEqual(checks(recorder).map { $0.properties["outcome"] }, [.string("started")])
    }

    /// With no card on the phone, nothing hands the ride off: the watch reports it.
    func testWithNoCardTheWatchReportsTheHandOff() async throws {
        let rig = try WatchRig(at: -300)
        await rig.arm()
        await rig.play(from: -299, to: 240)
        await rig.eventually { rig.holder.reports.contains { $0.handedOff } }
        XCTAssertEqual(rig.holder.reports.first?.holds, true)
        XCTAssertTrue(rig.holder.reports.last?.handedOff == true)
    }

    /// The phone stays at the platform while GO places the train 800 m out: not on board, and the card asks silently.
    func testThePhoneStayingIsNotOnBoard() async throws {
        let recorder = RecordingAnalytics.install()
        let rig = try WatchRig(at: -300)
        rig.holder.departureRide = rig.ride
        await rig.arm()
        await rig.play(from: -60, to: 240, phone: { _ in (0, true) })
        await rig.eventually { rig.holder.reports.contains { $0.asked } }

        XCTAssertNil(rig.watch.watched)
        XCTAssertNil(rig.engine.ride)
        XCTAssertEqual(rig.watch.lastCheck?.outcome, .notOnBoard)
        XCTAssertEqual(rig.holder.reports.last?.asked, true)
        XCTAssertFalse(rig.location.isUpdating, "No ride: the updates stop")
        XCTAssertNil(rig.holder.heldRide)
        XCTAssertEqual(checks(recorder).map { $0.properties["outcome"] }, [.string("not_on_board")])
    }

    /// No train positions: at the deadline it cannot tell. In the background the hold goes, so the server buzzes; it
    /// keeps watching for a later start until the question ends, and counts the train once with the first reason.
    func testNoFeedInTheBackgroundLetsTheHoldGo() async throws {
        let recorder = RecordingAnalytics.install()
        let rig = try WatchRig(at: -300)
        rig.holder.departureRide = rig.ride
        rig.active = false
        await rig.arm()
        await rig.play(from: -299, to: 200, train: nil)
        await rig.eventually { rig.holder.holds.contains(false) }

        XCTAssertEqual(rig.holder.holds, [true, false])
        XCTAssertNotNil(rig.watch.watched, "It keeps watching until the question ends")
        XCTAssertEqual(rig.watch.lastCheck?.outcome, .unsure)
        XCTAssertEqual(rig.watch.lastCheck?.reason, .noFeed)
        XCTAssertTrue(checks(recorder).isEmpty)

        await rig.play(from: 201, to: 615, train: nil)
        XCTAssertNil(rig.watch.watched)
        XCTAssertNil(rig.engine.ride)
        XCTAssertEqual(rig.holder.holds, [true, false], "The release is not sent twice")
        let check = try XCTUnwrap(rig.watch.lastCheck)
        XCTAssertEqual(check.reason, .noFeed)
        XCTAssertTrue((180...200).contains(check.secondsAfter ?? 0), "Counted from when it could not tell")
        let event = try XCTUnwrap(checks(recorder).first)
        XCTAssertEqual(checks(recorder).count, 1)
        XCTAssertEqual(event.properties["outcome"], .string("unsure"))
        XCTAssertEqual(event.properties["reason"], .string("no_feed"))
    }

    /// With the app in front, Schedule asks: the card asks silently instead of the hold being let go.
    func testUnsureInFrontAsksSilently() async throws {
        let rig = try WatchRig(at: -300)
        rig.holder.departureRide = rig.ride
        await rig.arm()
        await rig.play(from: -299, to: 200, train: nil)
        await rig.eventually { rig.holder.reports.contains { $0.asked } }
        XCTAssertEqual(rig.holder.holds, [true, nil])
        XCTAssertEqual(rig.holder.reports.last?.asked, true)
    }

    /// A train standing past its time (D114): at L + 6 min the hold goes with no verdict and the watch keeps watching;
    /// when it moves off at L + 8 min, that is when it left.
    func testATrainStandingPastItsTimeLetsTheHoldGoAndIsStillWatched() async throws {
        let rig = try WatchRig(at: -300)
        rig.holder.departureRide = rig.ride
        await rig.departures.set(originMetres: 100)
        await rig.arm()
        await rig.play(from: -299, to: 359, phone: { _ in nil }, train: nil)
        XCTAssertEqual(rig.holder.holds, [true])
        XCTAssertNil(rig.watch.watched?.leftAt)
        await rig.play(from: 360, to: 465, phone: { _ in nil }, train: nil)
        XCTAssertEqual(rig.holder.holds, [true, false], "Released at L + 6 min")
        XCTAssertNotNil(rig.watch.watched)
        await rig.departures.set(originMetres: 1000)
        await rig.play(from: 466, to: 480, phone: { _ in nil }, train: nil)
        XCTAssertEqual(rig.watch.watched?.leftAt, rig.time(480))
    }

    /// A delay moves L: the train leaves, and the deadline counts, from its expected departure.
    func testADelayMovesTheTrainsTime() async throws {
        let rig = try WatchRig(at: -300)
        await rig.departures.set(delay: 180)
        await rig.arm()
        await rig.play(from: -299, to: 165, phone: { _ in nil }, train: nil)
        XCTAssertEqual(rig.watch.watched?.departure, rig.time(180))
        XCTAssertNil(rig.watch.watched?.leftAt)
        await rig.play(from: 166, to: 180, phone: { _ in nil }, train: nil)
        XCTAssertEqual(rig.watch.watched?.leftAt, rig.time(180))
        XCTAssertEqual(rig.watch.watched?.deadline, rig.time(360))
    }

    /// An offline or stale read keeps the late train's L (`ScheduleDepartureReading` gives nil for it): the deadline is not
    /// moved to the timetable and leftAt is not stamped before the train moves.
    func testAReadWithNoFreshLiveStatusKeepsTheLateTrainsTime() async throws {
        let rig = try WatchRig(at: -300)
        await rig.departures.set(delay: 240)
        await rig.arm()
        await rig.play(from: -299, to: 30, phone: { _ in nil }, train: nil)
        XCTAssertEqual(rig.watch.watched?.departure, rig.time(240))
        await rig.departures.set(unreadable: true)
        await rig.play(from: 31, to: 120, phone: { _ in nil }, train: nil)
        XCTAssertEqual(rig.watch.watched?.departure, rig.time(240), "L as last read")
        XCTAssertNil(rig.watch.watched?.leftAt, "Not left by the timetable")
        await rig.departures.set(unreadable: false)
        await rig.play(from: 121, to: 240, phone: { _ in nil }, train: nil)
        XCTAssertEqual(rig.watch.watched?.leftAt, rig.time(240))
        XCTAssertEqual(rig.watch.watched?.deadline, rig.time(420))
    }

    /// The app's reading: only fresh live status resolves the train; offline or stale gives nil, so the watch keeps L.
    func testTheAppsReadingUsesFreshLiveStatusOnly() async throws {
        let rig = try WatchRig(at: 60)
        let now = rig.clock.now
        let update = LiveTripUpdate(
            expectedDeparture: rig.time(240), expectedArrival: rig.trip.scheduledArrival.addingTimeInterval(240),
            delayMinutes: 4, reportedAt: now
        )
        let fresh = LiveSnapshot(updatedAt: now, updates: [rig.ride.tripId: update])
        var offline = fresh
        offline.isOffline = true
        let stale = LiveSnapshot(updatedAt: now.addingTimeInterval(-300), updates: [rig.ride.tripId: update])
        func read(_ live: LiveSnapshot) async -> Departure? {
            await ScheduleDepartureReading(repository: LiveStub(live: live)).departure(of: rig.trip, ride: rig.ride, at: now)
        }
        let departure = await read(fresh)
        XCTAssertEqual(departure?.departureTime, rig.time(240))
        let none = await read(offline)
        XCTAssertNil(none, "Offline would read the timetable's time")
        let old = await read(stale)
        XCTAssertNil(old, "Stale too")
    }

    // MARK: Reports as a watch ends

    /// Not on board's `asked` that the server did not take is sent again until it does, and the location keeps going
    /// meanwhile so the app is not suspended before it goes.
    func testAnEndingReportTheServerDidNotTakeIsSentAgain() async throws {
        let rig = try WatchRig(at: -300)
        rig.holder.departureRide = rig.ride
        rig.holder.answers = [true, false]
        await rig.arm()
        await rig.play(from: -60, to: 240, phone: { _ in (0, true) })
        await rig.eventually { rig.holder.reports.contains { $0.asked } }
        XCTAssertNil(rig.watch.watched)
        XCTAssertEqual(rig.holder.reports.filter(\.asked).count, 1)
        XCTAssertEqual(rig.store.pending.map(\.report.asked), [true], "Kept on device")
        XCTAssertTrue(rig.location.isUpdating, "Still owed to the server")

        await rig.watch.retryPending()
        XCTAssertEqual(rig.holder.reports.filter(\.asked).count, 2)
        XCTAssertTrue(rig.store.pending.isEmpty)
        XCTAssertFalse(rig.location.isUpdating, "Told: the updates stop")
    }

    /// With no card the start's hand-off is the watch's to send: one the server missed goes again.
    func testAHandOffTheServerMissedIsSentAgain() async throws {
        let rig = try WatchRig(at: -300)
        rig.holder.answers = [true, false]
        await rig.arm()
        await rig.play(from: -299, to: 240)
        await rig.eventually { rig.holder.reports.contains { $0.handedOff } }
        XCTAssertNotNil(rig.engine.ride)
        XCTAssertEqual(rig.store.pending.map(\.report.handedOff), [true])
        await rig.watch.retryPending()
        XCTAssertEqual(rig.holder.reports.filter(\.handedOff).count, 2)
        XCTAssertTrue(rig.store.pending.isEmpty)
        XCTAssertTrue(rig.location.isUpdating, "The ride has the updates")
    }

    /// A report still owed when the app stopped goes at the next launch; one whose question has ended is dropped unsent.
    func testAnOwedReportGoesAfterARelaunchUntilTheQuestionEnds() async throws {
        let defaults = UserDefaults.ephemeral()
        let first = try WatchRig(at: -300, defaults: defaults)
        first.holder.departureRide = first.ride
        first.holder.answers = [true, false]
        await first.arm()
        await first.play(from: -60, to: 240, phone: { _ in (0, true) })
        await first.eventually { first.holder.reports.contains { $0.asked } }
        XCTAssertEqual(first.store.pending.count, 1)

        let relaunched = try WatchRig(at: 300, defaults: defaults)
        await relaunched.watch.restore()
        await relaunched.eventually { relaunched.holder.reports.contains { $0.asked } }
        XCTAssertEqual(relaunched.holder.reports.map(\.asked), [true])
        XCTAssertTrue(relaunched.store.pending.isEmpty)

        let late = try WatchRig(at: -300)
        late.holder.departureRide = late.ride
        late.holder.answers = [true, false]
        await late.arm()
        await late.play(from: -60, to: 240, phone: { _ in (0, true) })
        await late.eventually { late.holder.reports.contains { $0.asked } }
        let owed = try XCTUnwrap(late.store.pending.first)
        late.clock.set(owed.until)
        await late.watch.retryPending()
        XCTAssertEqual(late.holder.reports.filter(\.asked).count, 1, "Past the question's end: not sent")
        XCTAssertTrue(late.store.pending.isEmpty)
    }

    // MARK: Stopping and answering

    /// The alert switched off or removed stops the watch; the rule's own DELETE or pause lets the server's hold go.
    func testTheAlertGoingStopsTheWatch() async throws {
        let rig = try WatchRig(at: -600)
        rig.holder.departureRide = rig.ride
        await rig.arm()
        await rig.eventually { rig.holder.reports.count == 1 }
        rig.watch.alertsChanged(FakeWatchedTrips([rig.ride.tripKey]))
        XCTAssertNotNil(rig.watch.watched, "Still alerted")
        rig.watch.alertsChanged(FakeWatchedTrips())
        await rig.settle()
        XCTAssertNil(rig.watch.watched)
        XCTAssertEqual(rig.watch.lastCheck?.outcome, .stopped)
        XCTAssertEqual(rig.holder.holds, [true], "No release of its own")
        XCTAssertNil(rig.holder.heldRide)
        XCTAssertFalse(rig.location.isUpdating)
    }

    /// Precise Location turned off while it watches: stopped, and the hold is let go.
    func testPreciseLocationGoingStopsTheWatchAndLetsTheHoldGo() async throws {
        let rig = try WatchRig(at: -600)
        rig.holder.departureRide = rig.ride
        await rig.arm()
        await rig.eventually { rig.holder.reports.count == 1 }
        rig.location.isPrecise = false
        rig.at(-585)
        await rig.watch.look()
        await rig.eventually { rig.holder.reports.count == 2 }
        XCTAssertEqual(rig.watch.lastCheck?.outcome, .stopped)
        XCTAssertEqual(rig.holder.holds, [true, false])
    }

    /// The rider's Yes or "I’m on board" first: answered, and the ride is theirs.
    func testTheRidersOwnStartEndsTheWatchAsAnswered() async throws {
        let rig = try WatchRig(at: -600)
        rig.watch.follow(rig.engine)
        await rig.arm()
        rig.at(30)
        await rig.engine.start(rig.ride, source: .departure)
        await rig.eventually { rig.watch.watched == nil }
        XCTAssertEqual(rig.watch.lastCheck?.outcome, .answered)
        XCTAssertEqual(rig.engine.startSource, .departure)
        XCTAssertTrue(rig.location.isUpdating, "The ride keeps the updates")
    }

    func testNoOnTheQuestionEndsTheWatchAsAnswered() async throws {
        let rig = try WatchRig(at: -600)
        await rig.arm()
        rig.declined = [rig.ride.tripKey]
        rig.at(30)
        await rig.watch.look()
        XCTAssertNil(rig.watch.watched)
        XCTAssertEqual(rig.watch.lastCheck?.outcome, .answered)
    }

    // MARK: Relaunch

    /// The app stopped while it watched: at launch the watch picks up its train with what it kept.
    func testARelaunchPicksUpTheTrain() async throws {
        let defaults = UserDefaults.ephemeral()
        let first = try WatchRig(at: -300, defaults: defaults)
        first.holder.departureRide = first.ride
        await first.arm()
        await first.eventually { first.holder.reports.count == 1 }
        let kept = try XCTUnwrap(first.store.saved)
        XCTAssertNotNil(kept.holdReachedAt)

        let relaunched = try WatchRig(at: -200, defaults: defaults)
        await relaunched.watch.restore()
        XCTAssertEqual(relaunched.watch.watched?.armedAt, kept.armedAt)
        XCTAssertEqual(relaunched.watch.watched?.holdReachedAt, kept.holdReachedAt, "The hold is not sent again")
        XCTAssertTrue(relaunched.location.isUpdating)
        XCTAssertEqual(relaunched.holder.heldRide, relaunched.ride)
    }

    /// A ride saved meanwhile (it started, or the rider started one): answered.
    func testARelaunchWithARideSavedEndsAsAnswered() async throws {
        let defaults = UserDefaults.ephemeral()
        let first = try WatchRig(at: -300, defaults: defaults)
        await first.arm()

        let rideDefaults = UserDefaults.ephemeral()
        SavedRide(ride: first.ride, startedAt: first.time(100), startSource: .auto)
            .write(to: rideDefaults, key: RideEngine.storageKey)
        let relaunched = try WatchRig(at: 200, defaults: defaults, rideDefaults: rideDefaults)
        await relaunched.watch.restore()
        XCTAssertNil(relaunched.watch.watched)
        XCTAssertEqual(relaunched.watch.lastCheck?.outcome, .answered)
        XCTAssertNil(relaunched.store.saved)
    }

    /// Past its deadline: the hold goes and it ends as unsure.
    func testARelaunchPastTheDeadlineLetsTheHoldGo() async throws {
        let defaults = UserDefaults.ephemeral()
        let first = try WatchRig(at: -300, defaults: defaults)
        await first.arm()

        let relaunched = try WatchRig(at: 7 * 60, defaults: defaults)
        await relaunched.watch.restore()
        await relaunched.eventually { !relaunched.holder.reports.isEmpty }
        XCTAssertNil(relaunched.watch.watched)
        XCTAssertEqual(relaunched.watch.lastCheck?.outcome, .unsure)
        XCTAssertNil(relaunched.watch.lastCheck?.reason, "No verdict was made, so no reason is made up")
        XCTAssertEqual(relaunched.holder.holds, [false])
        XCTAssertFalse(relaunched.location.isUpdating)
    }
}

/// Live status only, for `ScheduleDepartureReading`.
private struct LiveStub: ScheduleRepository {
    let live: LiveSnapshot

    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] { [] }
    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot { live }
    func lineNotices(for line: Line) async throws -> [LineNotice] { [] }
}

/// TT-242 (D120): the ride engine's side of the automatic start.
@MainActor
final class RideEngineAutoStartTests: XCTestCase {
    override func tearDown() async throws {
        Analytics.tracker = nil
        try await super.tearDown()
    }

    private func engine(location: FakeLocation, defaults: UserDefaults? = .ephemeral()) throws -> RideEngine {
        RideEngine(
            data: FakeRideData(plan: try OnBoardFixtures.plan()), location: location,
            clock: TestClock(now: OnBoardFixtures.time(11, 20)), defaults: defaults, tickInterval: nil
        )
    }

    /// An automatic start never shows a prompt: it goes by what is allowed.
    func testAnAutomaticStartAsksForNothing() async throws {
        let location = FakeLocation(authorized: false)
        let engine = try engine(location: location)
        let started = await engine.start(OnBoardFixtures.ride, source: .auto, asks: false)
        XCTAssertTrue(started)
        XCTAssertEqual(location.requests, 0)
        XCTAssertFalse(location.isUpdating, "Without location the ride runs on the timetable")
        XCTAssertEqual(engine.startSource, .auto)
    }

    /// How the ride started is kept with it, and comes back with a relaunch; a ride saved before that comes back too.
    func testTheStartSourceIsKeptAcrossARelaunch() async throws {
        let defaults = UserDefaults.ephemeral()
        let first = try engine(location: FakeLocation(authorized: true), defaults: defaults)
        await first.start(OnBoardFixtures.ride, source: .auto, asks: false)
        XCTAssertEqual(SavedRide.read(from: defaults, key: RideEngine.storageKey)?.startSource, .auto)
        let relaunched = try engine(location: FakeLocation(authorized: true), defaults: defaults)
        await relaunched.restore()
        XCTAssertEqual(relaunched.startSource, .auto)

        let old = UserDefaults.ephemeral()
        let json = #"{"ride":{"tripId":"20261127-LW-1015","serviceDate":20261127,"originId":"UN","destinationId":"CL"},"startedAt":0}"#
        old.set(Data(json.utf8), forKey: RideEngine.storageKey)
        let saved = try XCTUnwrap(SavedRide.read(from: old, key: RideEngine.storageKey))
        XCTAssertNil(saved.startSource)
    }

    /// The watch and the rider's Yes never make two rides: a start while another awaits its plan returns false.
    func testASecondStartWhileTheFirstIsUnderWayReturnsFalse() async throws {
        let engine = try engine(location: FakeLocation(authorized: true))
        async let first = engine.start(OnBoardFixtures.ride, source: .auto, asks: false)
        async let second = engine.start(OnBoardFixtures.ride, source: .departure)
        let results = await [first, second]
        XCTAssertEqual(results.filter { $0 }.count, 1)
    }

    /// `ride_ended` says how the ride started.
    func testRideEndedCarriesTheStartSource() async throws {
        let recorder = RecordingAnalytics.install()
        let engine = try engine(location: FakeLocation(authorized: true))
        await engine.start(OnBoardFixtures.ride, source: .auto, asks: false)
        engine.end(.byRider)
        let ended = try XCTUnwrap(recorder.events.first { $0.name == "ride_ended" })
        XCTAssertEqual(ended.properties["source"], .string("auto"))
    }
}

/// TT-242 (D120): the hold in the report, and the alert rules sending it with no alert left.
final class AutoRideHoldReportTests: XCTestCase {
    private let report = LiveActivityReport(tripId: "LW-1713", serviceDate: "20261127", originId: "UN", destinationId: "CL")

    func testHoldsIsLeftOutOfTheJSONUnlessSet() throws {
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any]
        XCTAssertNil(plain?["holds"])
        var held = report
        held.holds = true
        let holding = try JSONSerialization.jsonObject(with: JSONEncoder().encode(held)) as? [String: Any]
        XCTAssertEqual(holding?["holds"] as? Bool, true)
        held.holds = false
        let released = try JSONSerialization.jsonObject(with: JSONEncoder().encode(held)) as? [String: Any]
        XCTAssertEqual(released?["holds"] as? Bool, false)
    }

    @MainActor
    func testTheHoldIsReportedWithNoAlertLeft() async {
        let server = FakeAlertServer()
        let rules = AlertFixtures.rules(server)
        var release = report
        release.holds = false
        let sent = await rules.report(release)
        XCTAssertTrue(sent)
        let reports = await server.activityReports
        XCTAssertEqual(reports, [release])
        let plain = await rules.report(report)
        XCTAssertTrue(plain)
        let still = await server.activityReports
        XCTAssertEqual(still, [release], "A plain report with no alert left needs nothing")
    }
}
