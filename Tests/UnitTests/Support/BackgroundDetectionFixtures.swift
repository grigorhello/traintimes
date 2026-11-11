import Foundation
import XCTest
@testable import TrainTimes

/// "Detect my train" in tests (TT-176): the demo's 5:13 PM Lakeshore West train on Fri Nov 27 as the one train on the route,
/// placed by its train feed, wake-ups and GPS the test sends, and the question kept instead of posted.
@MainActor
final class BackgroundRig {
    static let day = OnBoardFixtures.friday

    let defaults: UserDefaults
    let clock: TestClock
    let wakes: FakeWakeLocation
    /// The check's GPS.
    let gps = FakeLocation(authorized: true)
    let notifier = FakeDetectionNotifier()
    var route: Route? = DemoRide.route
    var isRiding = false
    private(set) var detection: BackgroundDetection!

    /// At `time` (5:18:20 PM, 40 s before Exhibition, by default).
    init(at time: Date? = nil, allowsAlways: Bool = true, defaults: UserDefaults = .ephemeral()) {
        self.defaults = defaults
        clock = TestClock(now: time ?? Self.day.gtfsTime(DemoRide.detectStartSeconds))
        wakes = FakeWakeLocation(allowsAlways: allowsAlways)
        detection = BackgroundDetection(
            location: wakes,
            candidates: DemoCandidates(train: DemoRide.candidate(on: Self.day)),
            notifier: notifier,
            clock: clock,
            defaults: defaults,
            route: { [weak self] in self?.route },
            isRiding: { [weak self] in self?.isRiding ?? false },
            makeDetector: { [unowned self] in
                TrainDetector(
                    candidates: DemoCandidates(train: DemoRide.candidate(on: Self.day)),
                    location: self.gps,
                    trains: DemoTrainPositions(plan: DemoRide.plan(on: Self.day), clock: self.clock),
                    clock: self.clock,
                    defaults: self.defaults,
                    tickInterval: nil,
                    feedInterval: 0
                )
            },
            tickInterval: nil
        )
    }

    /// The switch on, as a rider who turned it on earlier.
    static func on(at time: Date? = nil) -> BackgroundRig {
        let defaults = UserDefaults.ephemeral()
        defaults.set(true, forKey: DetectionStore.enabledKey)
        return BackgroundRig(at: time, defaults: defaults)
    }

    var plan: RidePlan { DemoRide.plan(on: Self.day) }

    /// A wake-up where the demo train is now, `north` metres off its track.
    func wakeFix(north: Double = 0, accuracy: Double = 500, speed: Double = -1) throws -> WakeFix {
        var point = try XCTUnwrap(plan.track).shape.point(at: plan.scheduledAlong(at: clock.now))
        point.latitude += north / 111_195.08
        return WakeFix(coordinate: point, horizontalAccuracy: accuracy, speed: speed)
    }

    /// The phone on the demo train, a fix each 5 s, until the question goes out or `end`.
    func ride(until end: Date) async throws {
        let shape = try XCTUnwrap(plan.track).shape
        while clock.now < end, notifier.posted.isEmpty {
            clock.advance(seconds: 5)
            await detection.tick()
            gps.send(LocationFix(coordinate: shape.point(at: plan.scheduledAlong(at: clock.now)), horizontalAccuracy: 5))
        }
    }
}

/// Wake-ups and the Always permission in tests.
@MainActor
final class FakeWakeLocation: WakeLocationProviding {
    var allowsAlways: Bool
    /// What the rider answers to the Always dialog.
    var answer = true
    private(set) var requests = 0
    private(set) var isWaking = false

    init(allowsAlways: Bool) {
        self.allowsAlways = allowsAlways
    }

    func requestAlways() async -> Bool {
        requests += 1
        if !allowsAlways { allowsAlways = answer }
        return allowsAlways
    }

    func startWakes(_ onWake: @escaping @MainActor (WakeFix) async -> Void) {
        isWaking = true
    }

    func stopWakes() {
        isWaking = false
    }
}

/// Keeps the questions instead of posting them.
@MainActor
final class FakeDetectionNotifier: DetectionNotifying {
    private(set) var posted: [TrainMatcher.Question] = []

    func post(_ question: TrainMatcher.Question) {
        posted.append(question)
    }
}
