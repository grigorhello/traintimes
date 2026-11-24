import Foundation
@testable import TrainTimes

/// Wake-ups and the location permissions in tests, for When the app is closed (TT-243, D120; Detect my train's before it).
/// It keeps the iOS prompts in the order the model asked for them (TT-234), and adds no order of its own.
@MainActor
final class FakeWakeLocation: WakeLocationProviding {
    /// One iOS prompt.
    enum Ask: Equatable {
        case whenInUse
        case always
    }

    var allowsAlways: Bool
    /// What the rider answers to the Always dialog.
    var answer = true
    /// Location was never asked, so the When In Use prompt can show; false as for a rider who answered it before.
    var canAskWhenInUse = false
    /// iOS can still show its Always dialog; it shows it once, so asking turns this off.
    var canAskAlways = true
    /// What the rider answers to the When In Use prompt, or answered before.
    var whenInUseAnswer = true
    /// How many times Always was asked for.
    private(set) var requests = 0
    /// Every prompt shown, in order.
    private(set) var asks: [Ask] = []
    private(set) var isWaking = false
    private var onWake: (@MainActor (WakeFix) async -> Void)?

    init(allowsAlways: Bool) {
        self.allowsAlways = allowsAlways
    }

    func requestWhenInUse() async -> Bool {
        if canAskWhenInUse {
            asks.append(.whenInUse)
            canAskWhenInUse = false
        }
        return whenInUseAnswer
    }

    func requestAlways() async -> Bool {
        requests += 1
        if canAskAlways {
            asks.append(.always)
            canAskAlways = false
            if !allowsAlways { allowsAlways = answer }
        }
        return allowsAlways
    }

    func startWakes(_ onWake: @escaping @MainActor (WakeFix) async -> Void) {
        isWaking = true
        self.onWake = onWake
    }

    func stopWakes() {
        isWaking = false
        onWake = nil
    }

    /// A significant-change wake-up, as iOS would send it while the wake-ups run.
    func wake(_ fix: WakeFix) async {
        await onWake?(fix)
    }
}

extension AutoRideWake {
    /// When the app is closed over a watch that never arms, for tests of the switch alone: `trains` gives no train.
    static func switchOnly(location: FakeWakeLocation, store: AutoRideStore) -> AutoRideWake {
        let watch = AutoRideWatch(
            ride: nil, location: FakeLocation(authorized: true), departures: FakeDepartures(), positions: FakeTripPositions(),
            clock: TestClock(now: Date(timeIntervalSince1970: 1_795_000_000)), store: store, lookInterval: nil
        )
        return AutoRideWake(
            location: location, watch: watch, store: store, clock: TestClock(now: Date(timeIntervalSince1970: 1_795_000_000)),
            trains: { _ in [] }
        )
    }
}
