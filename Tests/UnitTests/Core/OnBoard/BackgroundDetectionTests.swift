import XCTest
@testable import TrainTimes

/// "Detect my train" (TT-176): off by default and offered once; the switch both ways; the wake-up decisions (near a line,
/// moving, the hours); GPS only during a check of up to 12 minutes; a riding track leads to one notification; Not me
/// silences the train for the day, and three in a week turn the switch off.
@MainActor
final class BackgroundDetectionTests: XCTestCase {
    private let day = BackgroundRig.day

    // MARK: The switch and the offer

    func testOffByDefaultAndNothingWakes() async throws {
        let rig = BackgroundRig()

        rig.detection.resume()
        let wake = await rig.detection.wake(try rig.wakeFix())

        XCTAssertFalse(rig.detection.isOn)
        XCTAssertEqual(wake, .off)
        XCTAssertFalse(rig.wakes.isWaking)
        XCTAssertEqual(rig.wakes.requests, 0)
        XCTAssertFalse(rig.gps.isUpdating)
    }

    func testOfferedOnceAfterTheFirstCompletedRide() {
        let defaults = UserDefaults.ephemeral()
        let rig = BackgroundRig(defaults: defaults)
        XCTAssertFalse(rig.detection.offerDue)

        rig.detection.rideReachedYourStop()
        XCTAssertTrue(rig.detection.offerDue)
        // Still due after a relaunch, until it shows.
        XCTAssertTrue(BackgroundRig(defaults: defaults).detection.offerDue)

        rig.detection.offerShown()
        rig.detection.rideReachedYourStop()

        XCTAssertFalse(rig.detection.offerDue)
        XCTAssertFalse(BackgroundRig(defaults: defaults).detection.offerDue)
        XCTAssertFalse(rig.detection.isOn, "Shown is not turned on")
    }

    func testNoOfferWhenTheSwitchIsAlreadyOn() {
        let rig = BackgroundRig.on()

        rig.detection.rideReachedYourStop()

        XCTAssertFalse(rig.detection.offerDue)
    }

    func testTheSwitchWorksBothWays() async {
        let rig = BackgroundRig(allowsAlways: false)

        let on = await rig.detection.turnOn()

        XCTAssertTrue(on)
        XCTAssertTrue(rig.detection.isOn)
        XCTAssertEqual(rig.wakes.requests, 1)
        XCTAssertTrue(rig.wakes.isWaking)
        XCTAssertTrue(BackgroundRig(defaults: rig.defaults).detection.isOn)

        rig.detection.turnOff()

        XCTAssertFalse(rig.detection.isOn)
        XCTAssertFalse(rig.wakes.isWaking)
        XCTAssertFalse(BackgroundRig(defaults: rig.defaults).detection.isOn)
    }

    func testStaysOffWithoutAlways() async {
        let rig = BackgroundRig(allowsAlways: false)
        rig.wakes.answer = false

        let on = await rig.detection.turnOn()

        XCTAssertFalse(on)
        XCTAssertFalse(rig.detection.isOn)
        XCTAssertFalse(rig.wakes.isWaking)
    }

    func testWakeUpsStartAgainAtLaunch() {
        let rig = BackgroundRig.on()
        rig.detection.resume()
        XCTAssertTrue(rig.wakes.isWaking)

        // Always taken back in iOS Settings: the switch goes off.
        let revoked = BackgroundRig.on()
        revoked.wakes.allowsAlways = false
        revoked.detection.resume()
        XCTAssertFalse(revoked.detection.isOn)
        XCTAssertFalse(revoked.wakes.isWaking)
    }

    // MARK: Wake-ups

    func testAWakeUpNearTheLineWhileMovingStartsACheck() async throws {
        let rig = BackgroundRig.on()

        let wake = await rig.detection.wake(try rig.wakeFix(north: 250, accuracy: 10, speed: 20))

        XCTAssertEqual(wake, .check)
        XCTAssertTrue(rig.detection.isChecking)
        XCTAssertTrue(rig.gps.isUpdating)
    }

    func testACoarseFixCountsItsAccuracy() async throws {
        let rig = BackgroundRig.on()

        let wake = await rig.detection.wake(try rig.wakeFix(north: 800, accuracy: 700))

        XCTAssertEqual(wake, .check)
    }

    func testAWakeUpAwayFromTheLineSleeps() async throws {
        let rig = BackgroundRig.on()

        let wake = await rig.detection.wake(try rig.wakeFix(north: 2000, accuracy: 50))

        XCTAssertEqual(wake, .awayFromLine)
        XCTAssertFalse(rig.gps.isUpdating)
    }

    func testAWakeUpStandingStillSleeps() async throws {
        let rig = BackgroundRig.on()

        let wake = await rig.detection.wake(try rig.wakeFix(speed: 0.5))

        XCTAssertEqual(wake, .standing)
        XCTAssertFalse(rig.gps.isUpdating)
    }

    func testNoCheckWithoutARouteDuringARideOrWhileChecking() async throws {
        let noRoute = BackgroundRig.on()
        noRoute.route = nil
        let noRouteWake = await noRoute.detection.wake(try noRoute.wakeFix())
        XCTAssertEqual(noRouteWake, .noRoute)

        let riding = BackgroundRig.on()
        riding.isRiding = true
        let ridingWake = await riding.detection.wake(try riding.wakeFix())
        XCTAssertEqual(ridingWake, .busy)

        let checking = BackgroundRig.on()
        let first = await checking.detection.wake(try checking.wakeFix())
        let second = await checking.detection.wake(try checking.wakeFix())
        XCTAssertEqual(first, .check)
        XCTAssertEqual(second, .busy)
    }

    func testNothingBetween1And5AM() async throws {
        let cases: [(seconds: Int, expected: BackgroundDetection.Wake)] = [
            (24 * 3600 + 59 * 60, .check), // 12:59 AM
            (25 * 3600, .quietHours), // 1:00 AM
            (28 * 3600 + 59 * 60, .quietHours), // 4:59 AM
            (29 * 3600, .check), // 5:00 AM
        ]
        for (seconds, expected) in cases {
            let rig = BackgroundRig.on(at: day.gtfsTime(seconds))
            let wake = await rig.detection.wake(try rig.wakeFix())
            XCTAssertEqual(wake, expected, "at \(seconds / 3600 % 24):\(seconds / 60 % 60)")
            XCTAssertEqual(rig.gps.isUpdating, expected == .check)
        }
    }

    func testGPSStopsAfter12Minutes() async throws {
        let rig = BackgroundRig.on()
        _ = await rig.detection.wake(try rig.wakeFix())

        rig.clock.advance(seconds: 12 * 60 - 1)
        await rig.detection.tick()
        XCTAssertTrue(rig.gps.isUpdating)

        rig.clock.advance(seconds: 1)
        await rig.detection.tick()
        XCTAssertFalse(rig.gps.isUpdating)
        XCTAssertFalse(rig.detection.isChecking)
        XCTAssertTrue(rig.notifier.posted.isEmpty)
    }

    func testACheckStopsAt1AM() async throws {
        let rig = BackgroundRig.on(at: day.gtfsTime(24 * 3600 + 55 * 60))
        let wake = await rig.detection.wake(try rig.wakeFix())
        XCTAssertEqual(wake, .check)

        rig.clock.advance(seconds: 5 * 60)
        await rig.detection.tick()

        XCTAssertFalse(rig.gps.isUpdating)
    }

    func testOpeningTheAppEndsACheck() async throws {
        let rig = BackgroundRig.on()
        _ = await rig.detection.wake(try rig.wakeFix())

        rig.detection.appDidBecomeActive()

        XCTAssertFalse(rig.gps.isUpdating)
        XCTAssertFalse(rig.detection.isChecking)
    }

    // MARK: The question

    func testARidingTrackLeadsToTheNotification() async throws {
        let rig = BackgroundRig.on()
        let wake = await rig.detection.wake(try rig.wakeFix())
        XCTAssertEqual(wake, .check)

        try await rig.ride(until: day.gtfsTime(17 * 3600 + 40 * 60))

        let question = try XCTUnwrap(rig.notifier.posted.first)
        XCTAssertEqual(rig.notifier.posted.count, 1)
        XCTAssertEqual(question.trains.map(\.trip), [DemoRide.ride(on: day).tripKey])
        XCTAssertLessThan(rig.clock.now, day.gtfsTime(17 * 3600 + 30 * 60))
        // GPS goes off with the question, and the train is not asked about again today, here or on Schedule.
        XCTAssertFalse(rig.gps.isUpdating)
        XCTAssertFalse(rig.detection.isChecking)
        XCTAssertEqual(schedulesDetector(rig).silenced, [DemoRide.ride(on: day).tripKey])
        // The notification carries the train Start On board rides.
        let train = try XCTUnwrap(DetectedTrain(question))
        XCTAssertEqual(train.ride, Ride(trip: DemoRide.ride(on: day).tripKey, from: "UN", to: "CL"))
        XCTAssertEqual(DetectedTrain(userInfo: train.userInfo), train)
    }

    func testTheNotificationsWords() async throws {
        let rig = BackgroundRig.on()
        _ = await rig.detection.wake(try rig.wakeFix())
        try await rig.ride(until: day.gtfsTime(17 * 3600 + 40 * 60))
        let question = try XCTUnwrap(rig.notifier.posted.first)

        let notice = try XCTUnwrap(DetectionNotice(question, formatter: TimeFormatter(format: .twelveHour)))

        XCTAssertEqual(notice.title, "On the 5:13 PM train?")
        XCTAssertEqual(notice.body, "Lakeshore West, moving with it since Union. Start On board for a tap before Clarkson.")
    }

    // MARK: Not me

    func testNotMeSilencesTheTrainForTheDay() async {
        let rig = BackgroundRig.on()
        // Schedule's detector, made before the Not me, hears it when it starts again.
        let schedule = schedulesDetector(rig)
        let key = DemoRide.ride(on: day).tripKey

        rig.detection.notMe(DetectedTrain(trip: key, originId: "UN", destinationId: "CL"))

        _ = await schedule.start(on: DemoRide.route)
        XCTAssertEqual(schedule.silenced, [key])
        XCTAssertEqual(schedulesDetector(rig).silenced, [key])
        rig.clock.advance(seconds: 24 * 3600)
        XCTAssertEqual(schedulesDetector(rig).silenced, [])
    }

    func testThreeNotMeInAWeekTurnItOff() async {
        let rig = BackgroundRig.on()
        rig.detection.resume()
        let train = DetectedTrain(trip: DemoRide.ride(on: day).tripKey, originId: "UN", destinationId: "CL")

        rig.detection.notMe(train)
        rig.clock.advance(seconds: 2 * 24 * 3600)
        rig.detection.notMe(train)
        XCTAssertTrue(rig.detection.isOn)
        rig.clock.advance(seconds: 2 * 24 * 3600)
        rig.detection.notMe(train)

        XCTAssertFalse(rig.detection.isOn)
        XCTAssertTrue(rig.detection.wasTurnedOff)
        XCTAssertFalse(rig.wakes.isWaking)
        // Turning it on again clears the line.
        await rig.detection.turnOn()
        XCTAssertFalse(rig.detection.wasTurnedOff)
    }

    func testNotMeOlderThanAWeekDoesNotCount() {
        let rig = BackgroundRig.on()
        let train = DetectedTrain(trip: DemoRide.ride(on: day).tripKey, originId: "UN", destinationId: "CL")

        rig.detection.notMe(train)
        rig.clock.advance(seconds: 4 * 24 * 3600)
        rig.detection.notMe(train)
        rig.clock.advance(seconds: 4 * 24 * 3600)
        rig.detection.notMe(train)

        XCTAssertTrue(rig.detection.isOn)
    }

    /// The notification's handler writes the Not me in the background; the third turns the switch off at the next refresh
    /// (the app in front, or the next wake-up).
    func testNotMeFromTheHandlerCountsAtTheNextRefresh() async throws {
        let rig = BackgroundRig.on()
        let train = DetectedTrain(trip: DemoRide.ride(on: day).tripKey, originId: "UN", destinationId: "CL")
        for _ in 0..<3 { DetectionStore.recordNotMe(train, in: rig.defaults, at: rig.clock.now) }

        let wake = await rig.detection.wake(try rig.wakeFix())

        XCTAssertEqual(wake, .off)
        XCTAssertFalse(rig.detection.isOn)
        XCTAssertTrue(rig.detection.wasTurnedOff)
    }

    // MARK: Helpers

    /// A detector as Schedule makes one, on the same device storage.
    private func schedulesDetector(_ rig: BackgroundRig) -> TrainDetector {
        TrainDetector(
            candidates: DemoCandidates(train: DemoRide.candidate(on: day)),
            location: FakeLocation(authorized: true),
            clock: rig.clock,
            defaults: rig.defaults,
            tickInterval: nil
        )
    }
}
