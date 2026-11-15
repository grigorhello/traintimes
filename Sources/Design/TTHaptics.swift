import CoreHaptics
import SwiftUI
import UIKit

/// The app's feels (TT-214, D95; the canvas "Train Times · Motion and haptics", spec-v2). A haptic answers the rider's
/// finger, or a train the rider watches; never navigation, scrolling or ambient updates. One per gesture, timed from the tap
/// by a timer, never from an animation's completion. Only with the app open.
enum HapticFeel: String, CaseIterable, Sendable {
    /// `.selection`: a value in a set changed.
    case tick
    /// A soft tap at 0.6: a small thing took effect (a bell turned off).
    case tap
    /// The soft tap at 0.3 when a bell's save has not come back 150 ms after the tap; Rail joint follows when it lands.
    case wait
    /// A rigid tap at 0.45 as a switch's thumb arrives, the same on and off.
    case click
    /// A medium tap at 0.5: something was removed.
    case drop
    /// The signature, two beats, light then heavy: you're set (an alert is on, I'm on board, your first trains, boarding
    /// now for a train you watch). Nothing else plays it.
    case railJoint
    /// `.success`: what you sent arrived.
    case done
    /// `.warning`: blocked, or bad news about a watched train.
    case warning
    /// `.error`: it broke after you asked.
    case fail
    /// The arriving nudge (TT-173, D66), about a minute before your stop.
    case arriving

    /// The nine feels of the Haptics page, in the canvas's order (the wait tap is felt in its slow bell).
    static let listed: [HapticFeel] = [.tick, .tap, .click, .drop, .railJoint, .done, .warning, .fail, .arriving]

    /// The Haptics page's row title.
    var titleKey: String { "haptics.feel.\(rawValue)" }
    /// The Haptics page's line under the title.
    var detailKey: String { "haptics.feel.\(rawValue).detail" }

    /// Rail joint: a transient at 0.55 intensity and 0.30 sharpness, a transient at 1.0 and 0.20 100 ms later, and under it a
    /// 60 ms ring at 0.25 and 0.10 fading to nothing. Heavy and dull on purpose, so it is never taken for the iOS success.
    static let railJointPattern = ArrivingHaptics.Pattern(
        events: [
            .init(kind: .transient, time: 0, intensity: 0.55, sharpness: 0.30),
            .init(kind: .transient, time: 0.1, intensity: 1, sharpness: 0.20),
            .init(kind: .continuous, time: 0.1, duration: 0.06, intensity: 0.25, sharpness: 0.10),
        ],
        fade: .init(time: 0.1, points: [.init(time: 0, value: 1), .init(time: 0.06, value: 0)])
    )
}

/// Plays the feels: `TTHaptics.shared` in the app, a fake in tests.
@MainActor
protocol HapticPlaying: AnyObject, Sendable {
    func play(_ feel: HapticFeel)
    /// Starts the engine ahead of a Rail joint, on the touch-down of a bell, so its first beat is not late.
    func warm()
}

extension HapticPlaying {
    /// Plays `feel` after `delay`, timed from now, unless the task is cancelled first.
    @discardableResult
    func play(_ feel: HapticFeel, after delay: Duration) -> Task<Void, Never> {
        Task { @MainActor [self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            play(feel)
        }
    }
}

/// The feels on the phone. The system ones through UIKit's generators; Rail joint and Arriving on one shared
/// `CHHapticEngine` (haptics only, auto shutdown, started again before each pattern and after a reset). Plays nothing with
/// the app away, or on a device without haptics.
@MainActor
final class TTHaptics: HapticPlaying {
    static let shared = TTHaptics()

    /// Settings › Testing › Haptics' Cold start: the engine is thrown away before each pattern, to feel the worst case.
    var coldStart = false

    private var engine: CHHapticEngine?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    func play(_ feel: HapticFeel) {
        guard UIApplication.shared.applicationState == .active else { return }
        switch feel {
        case .tick: UISelectionFeedbackGenerator().selectionChanged()
        case .tap: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
        case .wait: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.3)
        case .click: UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.45)
        case .drop: UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.5)
        case .done: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .fail: UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .railJoint: play(HapticFeel.railJointPattern)
        case .arriving: play(ArrivingHaptics.arriving)
        }
    }

    /// A Core Haptics pattern on the shared engine (also the arriving nudge's, `SystemArrivalFeedback`).
    func play(_ pattern: ArrivingHaptics.Pattern) {
        guard supportsHaptics else { return }
        if coldStart {
            engine?.stop(completionHandler: nil)
            engine = nil
        }
        do {
            let engine = try self.engine ?? makeEngine()
            self.engine = engine
            // Starting a running engine is harmless, and brings back one that shut itself down or that iOS stopped.
            try engine.start()
            try engine.makePlayer(with: ArrivingHaptics.pattern(pattern)).start(atTime: CHHapticTimeImmediate)
        } catch {
            engine = nil
        }
    }

    func warm() {
        guard supportsHaptics, !coldStart, UIApplication.shared.applicationState == .active else { return }
        if engine == nil { engine = try? makeEngine() }
        engine?.start(completionHandler: nil)
    }

    private func makeEngine() throws -> CHHapticEngine {
        let engine = try CHHapticEngine()
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        // Called on a queue of the engine's: @Sendable, so it never assumes the main actor, and hops to it. A stopped
        // engine needs nothing here: the next pattern starts it again.
        engine.stoppedHandler = { @Sendable _ in }
        engine.resetHandler = { @Sendable [weak self] in
            Task { @MainActor in self?.restart() }
        }
        return engine
    }

    /// After a reset (the haptic server restarted) the engine must be started again before it plays.
    private func restart() {
        do {
            try engine?.start()
        } catch {
            engine = nil
        }
    }
}

/// A button style that sinks the label like `PressScaleStyle` and warms the haptic engine on touch-down: the bell, whose tap
/// may play Rail joint.
struct WarmsHapticsPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pressScale(configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { TTHaptics.shared.warm() }
            }
    }
}
