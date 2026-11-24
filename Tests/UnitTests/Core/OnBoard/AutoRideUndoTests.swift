import CoreLocation
import XCTest
@testable import TrainTimes

/// The undo by itself and Not on it's ending (TT-243, D120): `AutoRideRule.undoVerdict(at:)` on the On board tests' train
/// (Union to Clarkson at 11:17 AM), the ride engine ending a ride that started by itself in its first 10 min, Not on it before
/// a launch's restore, the window across a relaunch, the ride that started with the app closed, the declined-today store and
/// a wake fix's age.
@MainActor
final class AutoRideUndoTests: XCTestCase {
    override func tearDown() async throws {
        Analytics.tracker = nil
        try await super.tearDown()
    }

    // MARK: The rule

    func testAPhoneThatStayedAsTheTrainWentOnIsUndone() throws {
        var rig = try RuleRig()
        _ = rig.run(from: 0, to: 200, phone: { _ in (0, 0, false) }, stopAt: { _ in false })
        XCTAssertEqual(rig.rule.undoVerdict(at: rig.time(200)), .stayed)
    }

    func testAPhoneOnTheTrainKeepsTheRide() throws {
        var rig = try RuleRig()
        _ = rig.run(from: 0, to: 400, stopAt: { _ in false })
        XCTAssertEqual(rig.rule.undoVerdict(at: rig.time(400)), .keeps)
    }

    func testAPhoneOffTheLineFor60SecondsIsUndone() throws {
        var rig = try RuleRig()
        _ = rig.run(from: 0, to: 40, phone: { _ in (0, 500, false) }, stopAt: { _ in false })
        XCTAssertEqual(rig.rule.undoVerdict(at: rig.time(40)), .keeps, "Not 60 s yet")
        _ = rig.run(from: 41, to: 70, phone: { _ in (0, 500, false) }, stopAt: { _ in false })
        XCTAssertEqual(rig.rule.undoVerdict(at: rig.time(70)), .offTheLine)
    }

    func testStationaryFixesOffTheLineNeverUndo() throws {
        var rig = try RuleRig()
        _ = rig.run(from: 0, to: 300, phone: { _ in (0, 500, true) }, stopAt: { _ in false })
        XCTAssertEqual(rig.rule.undoVerdict(at: rig.time(300)), .keeps, "iOS can take a smooth train for a phone at rest")
    }

    func testAPauseNeverUndoes() throws {
        var rig = try RuleRig()
        _ = rig.run(
            from: 0, to: 70, phone: { s in (40...55).contains(s) ? nil : (0, 500, false) }, stopAt: { _ in false }
        )
        XCTAssertEqual(rig.rule.undoVerdict(at: rig.time(70)), .keeps, "A 17 s gap breaks the 60 s")
    }

    func testMissingFixesNeverUndo() throws {
        var rig = try RuleRig()
        _ = rig.run(
            from: 0, to: 300, phone: { s in s < 30 ? (AutoRideFixtures.boarding(s), 0, false) : nil }, stopAt: { _ in false }
        )
        XCTAssertEqual(rig.rule.undoVerdict(at: rig.time(300)), .keeps, "The feed moved on while the phone sent nothing")
    }

    func testAPhoneFallingBehindTheTrainIsUndone() throws {
        var rig = try RuleRig()
        _ = rig.run(
            from: 0, to: 200, phone: { s in (AutoRideFixtures.boarding(s) / 2, 0, false) }, stopAt: { _ in false }
        )
        XCTAssertEqual(rig.rule.undoVerdict(at: rig.time(200)), .fallingBehind)
    }

    /// The train at 90 km/h, its positions read 45 s after GO reported them: the phone's place now is never set against
    /// them, so a phone on the train is not behind.
    func testAFastTrainsOldPositionsAreNotFallingBehind() throws {
        var rig = try RuleRig()
        for second in 0...400 {
            let s = Double(second)
            rig.phone(s, along: AutoRideFixtures.boarding(s))
            let reported = s - 45
            if reported >= 0, Int(reported) % 30 == 0 { rig.train(reported, along: AutoRideFixtures.boarding(reported), lag: 45) }
        }
        XCTAssertEqual(rig.rule.undoVerdict(at: rig.time(400)), .keeps)
    }

    // MARK: The engine

    private struct EngineRig {
        let engine: RideEngine
        let clock: TestClock
        let location: FakeLocation
        let trains: FakeTrainPositions
        let defaults: UserDefaults
        let plan: RidePlan
        let departure: Date

        func time(_ seconds: Double) -> Date { departure.addingTimeInterval(seconds) }
    }

    /// An engine on the On board tests' train with location allowed, at `seconds` after L.
    private func engineRig(at seconds: Double = 60, defaults: UserDefaults = .ephemeral()) throws -> EngineRig {
        let plan = try OnBoardFixtures.plan()
        let departure = AutoRideFixtures.departure(plan)
        let clock = TestClock(now: departure.addingTimeInterval(seconds))
        let location = FakeLocation(authorized: true)
        let trains = FakeTrainPositions()
        let engine = RideEngine(
            data: FakeRideData(plan: plan), location: location, trains: trains, clock: clock, defaults: defaults, tickInterval: nil
        )
        return EngineRig(
            engine: engine, clock: clock, location: location, trains: trains, defaults: defaults, plan: plan, departure: departure
        )
    }

    /// The phone at Union each second from `from` to `to` after L while GO's train leaves (reported 20 s before each half
    /// minute's read), until the ride ends.
    private func stayAtUnion(_ rig: EngineRig, from: Int, to: Int) async {
        for second in from...to {
            let s = Double(second)
            rig.clock.set(rig.time(s))
            rig.location.send(LocationFix(coordinate: AutoRideFixtures.point(rig.plan, along: 0), horizontalAccuracy: 8))
            if second % 30 == 0 {
                await rig.trains.set(TrainPosition(
                    coordinate: AutoRideFixtures.point(rig.plan, along: AutoRideFixtures.boarding(s - 20)), reportedAt: rig.time(s - 20)
                ))
                await rig.engine.refresh()
            }
            if rig.engine.state?.phase == .ended { return }
        }
    }

    func testTheEngineEndsARideThatStartedByItselfWhenThePhoneStayed() async throws {
        let recorder = RecordingAnalytics.install()
        let rig = try engineRig()
        let started = await rig.engine.start(OnBoardFixtures.ride, source: .auto, asks: false)
        XCTAssertTrue(started)
        XCTAssertEqual(rig.engine.autoUndoUntil, rig.time(60 + 600))

        await stayAtUnion(rig, from: 60, to: 300)

        XCTAssertEqual(rig.engine.state?.endReason, .autoUndone)
        XCTAssertNil(rig.engine.autoUndoUntil)
        XCTAssertFalse(rig.location.isUpdating)
        XCTAssertNil(rig.defaults.data(forKey: RideEngine.storageKey))
        let ended = try XCTUnwrap(recorder.events.last)
        XCTAssertEqual(ended.name, "ride_ended")
        XCTAssertEqual(ended.properties["reason"], .string("auto_undone"))
        XCTAssertEqual(ended.properties["source"], .string("auto"))
        XCTAssertNil(ended.properties["surface"])
        XCTAssertTrue(DepartureQuestion.isDeclined(OnBoardFixtures.ride.tripKey, in: rig.defaults), "Nothing asks again today")
    }

    func testARideStartedByTheRiderIsNeverUndone() async throws {
        let rig = try engineRig()
        let started = await rig.engine.start(OnBoardFixtures.ride, source: .onBoard)
        XCTAssertTrue(started)
        XCTAssertNil(rig.engine.autoUndoUntil)

        await stayAtUnion(rig, from: 60, to: 300)

        XCTAssertNotEqual(rig.engine.state?.phase, .ended)
    }

    func testTheUndoIsLetGoAfterTenMinutes() async throws {
        let rig = try engineRig()
        let started = await rig.engine.start(OnBoardFixtures.ride, source: .auto, asks: false)
        XCTAssertTrue(started)

        // The phone reaches the station only from 10 min after the start: the rule has been let go.
        await stayAtUnion(rig, from: 60 + 600, to: 60 + 840)

        XCTAssertNotEqual(rig.engine.state?.endReason, .autoUndone)
    }

    // MARK: Not on it and the relaunch

    func testNotOnItBeforeTheRestoreEndsTheSavedRide() async throws {
        let recorder = RecordingAnalytics.install()
        let defaults = UserDefaults.ephemeral()
        let first = try engineRig(defaults: defaults)
        let started = await first.engine.start(OnBoardFixtures.ride, source: .auto, asks: false)
        XCTAssertTrue(started)

        // The card's Not on it opens a stopped app: a new engine on the same defaults, before its restore.
        let relaunched = try engineRig(at: 120, defaults: defaults)
        let ended = relaunched.engine.end(.notOnIt, surface: .card)

        XCTAssertEqual(ended, OnBoardFixtures.ride)
        XCTAssertNil(defaults.data(forKey: RideEngine.storageKey))
        XCTAssertTrue(DepartureQuestion.isDeclined(OnBoardFixtures.ride.tripKey, in: defaults))
        let event = try XCTUnwrap(recorder.events.last)
        XCTAssertEqual(event.name, "ride_ended")
        XCTAssertEqual(event.properties["reason"], .string("not_on_it"))
        XCTAssertEqual(event.properties["source"], .string("auto"))
        XCTAssertEqual(event.properties["surface"], .string("card"))

        await relaunched.engine.restore()
        XCTAssertNil(relaunched.engine.ride, "The restore does not bring it back")
    }

    func testNotOnItOnTheRideScreenEndsTheRunningRide() async throws {
        let recorder = RecordingAnalytics.install()
        let rig = try engineRig()
        let started = await rig.engine.start(OnBoardFixtures.ride, source: .auto, asks: false)
        XCTAssertTrue(started)

        XCTAssertEqual(rig.engine.end(.notOnIt, surface: .ride), OnBoardFixtures.ride)

        XCTAssertEqual(rig.engine.state?.endReason, .notOnIt)
        XCTAssertNil(rig.engine.end(.notOnIt, surface: .ride), "Once")
        XCTAssertEqual(recorder.events.last?.properties["surface"], .string("ride"))
        XCTAssertTrue(DepartureQuestion.isDeclined(OnBoardFixtures.ride.tripKey, in: rig.defaults))
    }

    func testTheWindowHoldsAcrossARelaunch() async throws {
        let defaults = UserDefaults.ephemeral()
        let first = try engineRig(defaults: defaults)
        let started = await first.engine.start(OnBoardFixtures.ride, source: .auto, asks: false)
        XCTAssertTrue(started)

        let relaunched = try engineRig(at: 360, defaults: defaults)
        await relaunched.engine.restore()

        XCTAssertEqual(relaunched.engine.autoUndoUntil, relaunched.time(60 + 600), "Counted from the start, not the relaunch")
    }

    func testARideThatStartedWithTheAppClosedRidesOnItsLocationUntilTheRestore() async throws {
        let defaults = UserDefaults.ephemeral()
        let rig = try engineRig(defaults: defaults)
        let closed = FakeLocation(authorized: true)
        let started = await rig.engine.start(OnBoardFixtures.ride, source: .auto, asks: false, location: closed)
        XCTAssertTrue(started)
        XCTAssertTrue(closed.isUpdating)
        XCTAssertFalse(rig.location.isUpdating, "The app's own location is not started from the background")

        let relaunched = try engineRig(at: 120, defaults: defaults)
        await relaunched.engine.restore()
        XCTAssertTrue(relaunched.location.isUpdating, "The next restore goes back to the app's location")
    }

    // MARK: The store and the saved ride

    func testDecliningKeepsOnlyTheDays() {
        let defaults = UserDefaults.ephemeral()
        let thursday = ServiceDay(year: 2026, month: 11, day: 26)
        DetectionStore.silence([TripKey(serviceDay: thursday, tripId: "OLD")], in: defaults)
        DetectionStore.silence([OnBoardFixtures.ride.tripKey], in: defaults)

        XCTAssertEqual(
            defaults.stringArray(forKey: DetectionStore.silencedKey),
            ["\(OnBoardFixtures.friday.dateKey)/\(OnBoardFixtures.ride.tripId)"]
        )
    }

    func testARideSavedWithTheRetiredDetectionSourceStillDecodes() throws {
        let defaults = UserDefaults.ephemeral()
        let saved = SavedRide(ride: OnBoardFixtures.ride, startedAt: Date(timeIntervalSince1970: 1_795_000_000), startSource: .onBoard)
        let json = try XCTUnwrap(String(data: try JSONEncoder().encode(saved), encoding: .utf8))
        XCTAssertTrue(json.contains("\"on_board\""))
        defaults.set(Data(json.replacingOccurrences(of: "\"on_board\"", with: "\"detection\"").utf8), forKey: RideEngine.storageKey)

        XCTAssertEqual(SavedRide.read(from: defaults, key: RideEngine.storageKey)?.startSource, .detection)
    }

    // MARK: Wake fixes

    func testAWakeFixGetsItsAgeFromItsTimestamp() {
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        let old = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.645, longitude: -79.38), altitude: 0, horizontalAccuracy: 65,
            verticalAccuracy: -1, timestamp: now.addingTimeInterval(-30)
        )
        let fix = SystemWakeLocation.fix(from: old, now: now)
        XCTAssertEqual(fix.age, 30, accuracy: 0.001)
        XCTAssertEqual(fix.horizontalAccuracy, 65)

        let ahead = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.645, longitude: -79.38), altitude: 0, horizontalAccuracy: 65,
            verticalAccuracy: -1, timestamp: now.addingTimeInterval(5)
        )
        XCTAssertEqual(SystemWakeLocation.fix(from: ahead, now: now).age, 0, "A clock a little ahead is no age")
    }
}
