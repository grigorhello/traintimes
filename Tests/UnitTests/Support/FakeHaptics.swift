import Foundation
@testable import TrainTimes

/// Records each feel played and when, instead of playing it (TT-214).
@MainActor
final class FakeHaptics: HapticPlaying {
    private(set) var played: [HapticFeel] = []
    private(set) var times: [ContinuousClock.Instant] = []
    private(set) var warms = 0

    func play(_ feel: HapticFeel) {
        played.append(feel)
        times.append(.now)
    }

    func warm() { warms += 1 }
}
