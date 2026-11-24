import XCTest
@testable import TrainTimes

/// When the app is closed (TT-243, D120): `AutoRideWake` over the automatic ride's watch on the On board tests' train
/// (Union to Clarkson at 11:17 AM). A significant-change wake near the train in its window arms the watch with `wake`, the
/// card arriving arms it with `card`, a wake after the window counts `not_armed`, and nothing arms while the switch, Always
/// or Automatic ride is off, or the app is in front. A watch armed that way reads `BackgroundFixes`.
@MainActor
final class AutoRideWakeTests: XCTestCase {
    private final class App {
        var inFront = false
    }

    private struct Rig {
        let watch: WatchRig
        let location: FakeWakeLocation
        let wake: AutoRideWake
        let app: App
    }

    override func tearDown() async throws {
        Analytics.tracker = nil
        try await super.tearDown()
    }

    /// The switch on with Always allowed, at `seconds` after L, and the watch's train as today's one alerted train.
    private func rig(at seconds: Double = -300, allowsAlways: Bool = true) throws -> Rig {
        let watch = try WatchRig(at: seconds)
        watch.store.closed = true
        let location = FakeWakeLocation(allowsAlways: allowsAlways)
        let app = App()
        let train = AutoRideTrain(candidate: watch.candidate, plan: watch.plan)
        let wake = AutoRideWake(
            location: location, watch: watch.watch, store: watch.store, clock: watch.clock, trains: { _ in [train] },
            isInForeground: { app.inFront }
        )
        return Rig(watch: watch, location: location, wake: wake, app: app)
    }

    /// A coarse fix `north` metres north of Union's platform.
    private func fix(_ rig: Rig, north: Double = 0, accuracy: Double = 500) -> WakeFix {
        WakeFix(coordinate: AutoRideFixtures.point(rig.watch.plan, along: 0, north: north), horizontalAccuracy: accuracy)
    }

    // MARK: Arming

    func testAWakeNearTheStationInTheWindowArmsTheWatch() async throws {
        let rig = try rig()
        rig.wake.resume()
        XCTAssertTrue(rig.location.isWaking)

        let outcome = await rig.wake.wake(fix(rig))

        XCTAssertEqual(outcome, .armed)
        XCTAssertEqual(rig.watch.watch.watched?.ride, rig.watch.ride)
        XCTAssertEqual(rig.watch.watch.watched?.armed, .wake)
        XCTAssertEqual(rig.watch.watch.watched?.armedLate, true, "Y1's covered form counts at any station")
        XCTAssertTrue(rig.watch.closedLocation.isUpdating, "BackgroundFixes, which already run in the background")
        XCTAssertFalse(rig.watch.location.isUpdating)
    }

    func testAWakeFromIOSReachesTheWatch() async throws {
        let rig = try rig()
        rig.wake.resume()
        await rig.location.wake(fix(rig))
        XCTAssertEqual(rig.watch.watch.watched?.armed, .wake)
    }

    func testTheCardArrivingArmsTheWatch() async throws {
        let rig = try rig(at: -29 * 60)

        let outcome = await rig.wake.cardArrived(rig.watch.ride)

        XCTAssertEqual(outcome, .armed)
        XCTAssertEqual(rig.watch.watch.watched?.armed, .card)
    }

    func testAWakeFarFromTheLineArmsNothing() async throws {
        let rig = try rig()
        let outcome = await rig.wake.wake(fix(rig, north: 5000, accuracy: 100))
        XCTAssertEqual(outcome, .nothing)
        XCTAssertNil(rig.watch.watch.watched)
    }

    func testAWakeBeforeTheWindowArmsNothing() async throws {
        let rig = try rig(at: -40 * 60)
        let outcome = await rig.wake.wake(fix(rig))
        XCTAssertEqual(outcome, .nothing)
        XCTAssertNil(rig.watch.watch.watched)
    }

    func testAWakeAfterTheWindowCountsNotArmed() async throws {
        let recorder = RecordingAnalytics.install()
        let rig = try rig(at: 5 * 60)

        let outcome = await rig.wake.wake(fix(rig))

        XCTAssertEqual(outcome, .late)
        XCTAssertNil(rig.watch.watch.watched)
        XCTAssertEqual(recorder.events, [.autoRideChecked(AutoRideCheck(outcome: .notArmed, armed: .wake), demo: false)])

        _ = await rig.wake.wake(fix(rig))
        XCTAssertEqual(recorder.events.count, 1, "Once per train and day")
    }

    func testPreciseLocationOffKeepsItFromArming() async throws {
        let recorder = RecordingAnalytics.install()
        let rig = try rig()
        rig.watch.closedLocation.isPrecise = false

        let outcome = await rig.wake.wake(fix(rig))

        XCTAssertEqual(outcome, .nothing)
        XCTAssertNil(rig.watch.watch.watched)
        XCTAssertEqual(recorder.events.first?.properties["outcome"], .string("not_armed"))
        XCTAssertEqual(recorder.events.first?.properties["armed"], .string("wake"))
    }

    // MARK: Off and busy

    func testNothingArmsWhileTheAppIsInFront() async throws {
        let rig = try rig()
        rig.app.inFront = true
        let outcome = await rig.wake.wake(fix(rig))
        XCTAssertEqual(outcome, .busy, "The app's own arming runs there")
        XCTAssertNil(rig.watch.watch.watched)
    }

    func testTheSwitchOffArmsNothingAndStopsTheWakes() async throws {
        let rig = try rig()
        rig.wake.resume()
        rig.watch.store.closed = false

        let outcome = await rig.wake.wake(fix(rig))

        XCTAssertEqual(outcome, .off)
        XCTAssertFalse(rig.location.isWaking)
        XCTAssertNil(rig.watch.watch.watched)
    }

    func testAlwaysNotAllowedArmsNothing() async throws {
        let rig = try rig(allowsAlways: false)
        XCTAssertFalse(rig.wake.isOn)
        rig.wake.resume()
        XCTAssertFalse(rig.location.isWaking)
        let outcome = await rig.wake.cardArrived(rig.watch.ride)
        XCTAssertEqual(outcome, .off)
    }

    func testAutomaticRideOffArmsNothing() async throws {
        let rig = try rig()
        rig.watch.store.isOff = true
        XCTAssertFalse(rig.wake.isOn)
        let outcome = await rig.wake.wake(fix(rig))
        XCTAssertEqual(outcome, .off)
    }

    // MARK: The rule

    func testACoarseFixCountsItsAccuracyUpToOneKilometre() throws {
        let plan = try OnBoardFixtures.plan()
        func near(north: Double, accuracy: Double) -> Bool {
            AutoRideWake.isNear(
                WakeFix(coordinate: AutoRideFixtures.point(plan, along: 0, north: north), horizontalAccuracy: accuracy), plan
            )
        }
        XCTAssertTrue(near(north: 900, accuracy: 10), "Within 1 km of the station")
        XCTAssertFalse(near(north: 1800, accuracy: 200))
        XCTAssertTrue(near(north: 1800, accuracy: 1000))
        XCTAssertFalse(near(north: 2500, accuracy: 3000), "Counted up to 1 km only")
        XCTAssertFalse(near(north: 0, accuracy: -1), "Not a valid fix")
        XCTAssertTrue(
            AutoRideWake.isNear(WakeFix(coordinate: AutoRideFixtures.point(plan, along: 12_000, north: 200), horizontalAccuracy: 50), plan),
            "Within 300 m of the track"
        )
    }
}
