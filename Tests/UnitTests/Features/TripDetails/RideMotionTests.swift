import XCTest
@testable import TrainTimes

/// TT-224, D106: the ride screen moving. Where the train is drawn, the Tick and the Tap, and `ride_ended`'s watch time.
@MainActor
final class RideMotionTests: XCTestCase {
    private let formatter = TimeFormatter(format: .twelveHour)

    override func tearDown() {
        Analytics.tracker = nil
        super.tearDown()
    }

    private func details(_ rig: DemoRideRig) throws -> RideDetails {
        try XCTUnwrap(rig.onBoard.details(for: rig.key, formatter: formatter))
    }

    // MARK: The train's place

    func testTheTrainCreepsForwardByTheClock() async throws {
        let rig = await DemoRideRig.started()
        let first = try XCTUnwrap(try details(rig).trainPosition)
        rig.drive(to: DemoRideRig.time(17, 32, 30))
        let later = try XCTUnwrap(try details(rig).trainPosition)
        XCTAssertGreaterThan(later, first, "Not parked half way: it moves on with the clock")
        XCTAssertLessThan(later, 4, "Still on the same stretch")
    }

    func testOnAStretchTheRailPlacesTheTrainBetweenTheTwoDots() async throws {
        let rig = await DemoRideRig.started()
        let ride = try details(rig)
        let rail = RideRail(rows: ride.rows, stopCount: ride.stops.count)
        // Rows: Union, fold, Long Branch, Port Credit, Clarkson.
        XCTAssertEqual(rail.tops, [0, 50, 76, 126, 176])
        XCTAssertEqual(rail.centre(ofStop: 3), 101)
        XCTAssertEqual(rail.centre(ofStop: 4), 151)
        XCTAssertNil(rail.centre(ofStop: 1), "Folded away")
        XCTAssertEqual(rail.trainY(3), 101, "On Long Branch's dot")
        XCTAssertEqual(rail.trainY(3.25), 113.5)
        XCTAssertEqual(rail.trainY(nil), 201, "At your stop: on the pin")
        XCTAssertEqual(rail.nextY(3.25), 151, "The glint runs to Port Credit")
    }

    func testOnTheLastStretchTheTrainStays24PointsShortOfYourPin() async throws {
        let rig = await DemoRideRig.started()
        let ride = try details(rig)
        let rail = RideRail(rows: ride.rows, stopCount: ride.stops.count)
        let pin = try XCTUnwrap(rail.centre(ofStop: 5))
        XCTAssertEqual(rail.trainY(4.2), 151 + 50 * 0.2, accuracy: 0.001, "Short of the cap: by the clock")
        XCTAssertEqual(rail.trainY(4.92), pin - 24, "Held 24 pt short of the pin's centre")
        XCTAssertEqual(rail.trainY(4), 151, "At Port Credit: on its dot")
    }

    func testAFoldedStretchIsCrossedAsOne() {
        let stops = (0..<6).map { index in
            RideDetails.Stop(
                id: "S\(index)", index: index, name: "S\(index)", time: nil, isFirst: index == 0, isYours: index == 5,
                isDone: false, isNext: index == 1, isLate: false
            )
        }
        // Drawn: S0, S1, fold (S2, S3), S4, S5. Between S1 and S4 nothing else is drawn.
        let rows: [RideDetails.Row] = [.stop(stops[0]), .stop(stops[1]), .fold(after: "S1"), .stop(stops[4]), .stop(stops[5])]
        let rail = RideRail(rows: rows, stopCount: 6)
        XCTAssertEqual(rail.trainY(1), 75)
        XCTAssertEqual(rail.trainY(1.5), 75 + (151 - 75) / 2, "Half way to the next drawn stop, over the fold")
        XCTAssertEqual(rail.nextY(1.5), 151)
    }

    func testTheTrainNeverGoesBackOnTheSameStretch() {
        XCTAssertEqual(RideDetails.forward(3.4, from: 3.5), 3.5, "A later delay holds it where it was")
        XCTAssertEqual(RideDetails.forward(3.6, from: 3.5), 3.6)
        XCTAssertEqual(RideDetails.forward(4, from: 3.9), 4, "A stop shows as it is")
        XCTAssertEqual(RideDetails.forward(4.1, from: 3.9), 4.1, "A new stretch shows as it is")
        XCTAssertNil(RideDetails.forward(nil, from: 4.8), "At your stop")
        XCTAssertEqual(RideDetails.forward(3.2, from: nil), 3.2)
    }

    // MARK: Feels

    private func screen() -> (RideScreen, FakeHaptics) {
        let haptics = FakeHaptics()
        return (RideScreen(haptics: haptics, passDelay: .zero), haptics)
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(50))
    }

    func testAPassingStopTicksAndNothingOnFirstSight() async throws {
        let rig = await DemoRideRig.started()
        let (screen, haptics) = screen()
        screen.opened(rig.engine)
        screen.show(passed: 3, yoursIsNext: false, isComplete: false)
        try await settle()
        XCTAssertEqual(haptics.played, [], "Nothing when the screen opens")
        screen.show(passed: 3, yoursIsNext: false, isComplete: false)
        try await settle()
        XCTAssertEqual(haptics.played, [], "Nothing when nothing passed")
        screen.show(passed: 4, yoursIsNext: false, isComplete: false)
        try await settle()
        XCTAssertEqual(haptics.played, [.tick])
    }

    func testYourStopBecomingNextTapsInsteadOfTicking() async throws {
        let rig = await DemoRideRig.started()
        let (screen, haptics) = screen()
        screen.opened(rig.engine)
        screen.show(passed: 3, yoursIsNext: false, isComplete: false)
        screen.show(passed: 4, yoursIsNext: true, isComplete: false)
        try await settle()
        XCTAssertEqual(haptics.played, [.tap], "One feel per event: the Tap, not both")
        // Leaving the stop before yours: still next, nothing more.
        screen.show(passed: 4, yoursIsNext: true, isComplete: false)
        try await settle()
        XCTAssertEqual(haptics.played, [.tap])
    }

    func testAtYourStopTheScreenPlaysNothing() async throws {
        let rig = await DemoRideRig.started()
        let (screen, haptics) = screen()
        screen.opened(rig.engine)
        screen.show(passed: 4, yoursIsNext: true, isComplete: false)
        screen.show(passed: 5, yoursIsNext: false, isComplete: true)
        try await settle()
        XCTAssertEqual(haptics.played, [], "The arriving nudge's Done plays at your stop")
    }

    func testNothingPlaysWithTheScreenAwayOrTheAppInTheBackground() async throws {
        let rig = await DemoRideRig.started()
        let (screen, haptics) = screen()
        screen.show(passed: 3, yoursIsNext: false, isComplete: false)
        screen.show(passed: 4, yoursIsNext: false, isComplete: false)
        try await settle()
        XCTAssertEqual(haptics.played, [], "Never opened")

        screen.opened(rig.engine)
        screen.show(passed: 3, yoursIsNext: false, isComplete: false)
        screen.scene(isActive: false)
        screen.show(passed: 4, yoursIsNext: true, isComplete: false)
        try await settle()
        XCTAssertEqual(haptics.played, [], "App in the background")

        screen.closed()
        screen.show(passed: 4, yoursIsNext: true, isComplete: false)
        try await settle()
        XCTAssertEqual(haptics.played, [], "Screen closed")
    }

    // MARK: Watch time

    func testWatchCountsOnScreenSecondsWithTheAppActive() {
        var watch = RideWatch()
        let start = Date(timeIntervalSince1970: 1_000)
        watch.opened()
        watch.watching(true, at: start)
        watch.watching(false, at: start.addingTimeInterval(20))
        watch.watching(false, at: start.addingTimeInterval(40))
        watch.opened()
        watch.watching(true, at: start.addingTimeInterval(60))
        XCTAssertEqual(watch.seconds(at: start.addingTimeInterval(72.9)), 32)
        XCTAssertEqual(watch.opens, 2)
    }

    func testRideEndedCarriesWatchedSecondsAndOpens() async throws {
        let recorder = RecordingAnalytics.install()
        let rig = await DemoRideRig.started()
        let (screen, _) = screen()
        let start = Date(timeIntervalSinceNow: -100)
        screen.opened(rig.engine, now: start)
        screen.scene(isActive: false, now: start.addingTimeInterval(30))
        screen.scene(isActive: true, now: start.addingTimeInterval(50))
        screen.closed(now: start.addingTimeInterval(62.5))
        screen.opened(rig.engine, now: start.addingTimeInterval(70))
        screen.closed(now: start.addingTimeInterval(80))
        rig.onBoard.end()
        let ended = try XCTUnwrap(recorder.events.last { $0.name == "ride_ended" })
        XCTAssertEqual(ended.properties["watched_seconds"], .int(52))
        XCTAssertEqual(ended.properties["opens"], .int(2))
    }
}
