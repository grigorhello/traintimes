import AVFoundation
import CoreHaptics
import UIKit

/// The arriving nudge's haptics (TT-173, D66, Live-Spec motion table): plain values, so a test reads the pattern, and
/// `pattern(_:)` makes the Core Haptics pattern the phone plays.
enum ArrivingHaptics {
    struct Event: Equatable, Sendable {
        enum Kind: Sendable { case transient, continuous }
        let kind: Kind
        /// Seconds from the start of the pattern.
        let time: TimeInterval
        /// Seconds; 0 for a transient.
        var duration: TimeInterval = 0
        let intensity: Float
        let sharpness: Float
    }

    /// The intensity control of the rumble from `time` on: each point multiplies the events' intensity.
    struct Fade: Equatable, Sendable {
        struct Point: Equatable, Sendable {
            /// Seconds after the fade's `time`.
            let time: TimeInterval
            let value: Float
        }

        let time: TimeInterval
        let points: [Point]
    }

    struct Pattern: Equatable, Sendable {
        let events: [Event]
        var fade: Fade?
    }

    /// About a minute before your stop: three strong taps 150 ms apart, then on the same beat a 600 ms rumble whose
    /// intensity fades from 0.8 to 0.3.
    static let arriving = Pattern(
        events: [
            Event(kind: .transient, time: 0, intensity: 1, sharpness: 0.6),
            Event(kind: .transient, time: 0.15, intensity: 1, sharpness: 0.6),
            Event(kind: .transient, time: 0.3, intensity: 1, sharpness: 0.6),
            Event(kind: .continuous, time: 0.45, duration: 0.6, intensity: 1, sharpness: 0.3),
        ],
        fade: Fade(time: 0.45, points: [Fade.Point(time: 0, value: 0.8), Fade.Point(time: 0.6, value: 0.3)])
    )

    /// At your stop: one medium tap, as `UIImpactFeedbackGenerator(style: .medium)` gives.
    static let atYourStop = Pattern(events: [Event(kind: .transient, time: 0, intensity: 0.75, sharpness: 0.5)])

    static func pattern(_ pattern: Pattern) throws -> CHHapticPattern {
        let events = pattern.events.map { event in
            let parameters = [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: event.intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: event.sharpness),
            ]
            return switch event.kind {
            case .transient:
                CHHapticEvent(eventType: .hapticTransient, parameters: parameters, relativeTime: event.time)
            case .continuous:
                CHHapticEvent(eventType: .hapticContinuous, parameters: parameters, relativeTime: event.time, duration: event.duration)
            }
        }
        let curves = pattern.fade.map { fade in
            [CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: fade.points.map { CHHapticParameterCurve.ControlPoint(relativeTime: $0.time, value: $0.value) },
                relativeTime: fade.time
            )]
        } ?? []
        return try CHHapticPattern(events: events, parameterCurves: curves)
    }
}

/// What the rider feels and hears while the app is open (TT-173): `SystemArrivalFeedback` in the app, a fake in tests.
@MainActor
protocol ArrivalFeedback: AnyObject {
    /// About a minute before your stop: the taps, the rumble and `arrive.caf`.
    func arriving()
    /// At your stop: one tap.
    func atYourStop()
}

/// The nudge on the phone, only while the app is in front: Core Haptics plays only then, and with the app away the Time
/// Sensitive notification brings its own sound, so the chime never comes twice.
@MainActor
final class SystemArrivalFeedback: ArrivalFeedback {
    /// Outputs only the rider hears, where the chime plays over their music; elsewhere it keeps to the ring/silent switch.
    private static let privateOutputs: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP]

    private var haptics: CHHapticEngine?
    private var player: AVAudioPlayer?

    func arriving() {
        guard UIApplication.shared.applicationState == .active else { return }
        play(ArrivingHaptics.arriving)
        playChime()
    }

    func atYourStop() {
        guard UIApplication.shared.applicationState == .active else { return }
        play(ArrivingHaptics.atYourStop)
    }

    private func play(_ pattern: ArrivingHaptics.Pattern) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try haptics ?? CHHapticEngine()
            haptics = engine
            // Starting again is harmless, and brings the engine back after iOS stopped it while the app was away.
            try engine.start()
            try engine.makePlayer(with: ArrivingHaptics.pattern(pattern)).start(atTime: CHHapticTimeImmediate)
        } catch {
            haptics = nil
        }
    }

    /// `arrive.caf`, the notification's sound: in AirPods or other headphones over the rider's music, which ducks for it;
    /// on the speaker as an ambient sound, silent with the switch on.
    private func playChime() {
        guard let url = Bundle.main.url(forResource: "arrive", withExtension: "caf"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        let session = AVAudioSession.sharedInstance()
        let isPrivate = session.currentRoute.outputs.contains { Self.privateOutputs.contains($0.portType) }
        try? session.setCategory(isPrivate ? .playback : .ambient, options: isPrivate ? [.duckOthers] : [])
        try? session.setActive(true)
        self.player = player
        player.play()
        let duration = player.duration
        let id = ObjectIdentifier(player)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration + 0.2))
            guard let self, let current = self.player, ObjectIdentifier(current) == id else { return }
            self.player = nil
            // The rider's music comes back up.
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
