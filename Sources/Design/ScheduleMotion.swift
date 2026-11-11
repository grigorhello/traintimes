import SwiftUI

/// Schedule's motion (TT-164, D60; the Motion-Spec board on the canvas): the cards cascading in when a new set of trains is
/// shown, and the Now dot's pulse on the way back to Now. Both are drawn from the clock, as the swap is (`SwapMotion`), so
/// that a card that has only just been inserted starts from its first pose in its first frame. The day tile's glide and
/// press are SwiftUI springs (`TTMotion.glide`, `TTMotion.press`) in `ScheduleView`.
enum CascadeMotion {
    /// What a card, or one of its rail marks, looks like at a moment of its entrance.
    struct Pose: Equatable {
        var opacity = 1.0
        var offsetY: CGFloat = 0
        var scale: CGFloat = 1
    }

    static let rest = Pose()
    /// A card starts 20 pt up, at 0.96 of its size.
    static let rise: CGFloat = -20
    static let startScale: CGFloat = 0.96
    /// A card fades in over 0.12 s, ease-out; under Reduce Motion over `TTMotion.fade`'s 0.18 s, without moving.
    static let fadeDuration = 0.12
    static let reducedFadeDuration = 0.18
    /// The last card's delay and its spring's settling: past this every card is at rest.
    static let duration = TTMotion.cascadeDelay(5) + 0.9

    /// The pose `elapsed` seconds after the cascade started of the card `order` places after the first in view. Rail marks
    /// and the empty-state cards only fade (`moves` false), and Reduce Motion fades everything.
    static func pose(at elapsed: Double, order: Int, moves: Bool = true, reduceMotion: Bool = false) -> Pose {
        guard elapsed < duration else { return rest }
        let time = elapsed - TTMotion.cascadeDelay(order)
        let fade = reduceMotion ? reducedFadeDuration : fadeDuration
        let opacity = time <= 0 ? 0 : time >= fade ? 1 : UnitCurve.easeOut.value(at: time / fade)
        guard moves, !reduceMotion else { return Pose(opacity: opacity) }
        let progress = time > 0 ? TTMotion.cascadeCurve.progress(at: time) : 0
        return Pose(opacity: opacity, offsetY: rise * (1 - progress), scale: startScale + (1 - startScale) * progress)
    }
}

/// The Now dot pulsing once when the Schedule tab is tapped again, and once after the launch's scroll has settled: the dot
/// swells to 1.7 and back over 0.6 s while a 2 pt accent ring spreads from it to 3.4 times and fades (ease-out, as the
/// board's keyframes). Nothing under Reduce Motion.
enum NowPulse {
    struct Pose: Equatable {
        var dotScale: CGFloat = 1
        var ringScale: CGFloat = 1
        /// 0 at rest, when the ring is not drawn.
        var ringOpacity = 0.0
    }

    static let rest = Pose()
    static let duration = 0.6
    static let peakScale: CGFloat = 1.7
    /// The dot is largest at 35 % of the pulse.
    static let peakAt = 0.35
    static let ringEndScale: CGFloat = 3.4
    static let ringStartOpacity = 0.6

    static func pose(at elapsed: Double) -> Pose {
        guard elapsed >= 0, elapsed < duration else { return rest }
        let fraction = elapsed / duration
        let ease = UnitCurve.easeOut
        let dot = fraction < peakAt
            ? 1 + (peakScale - 1) * ease.value(at: fraction / peakAt)
            : peakScale - (peakScale - 1) * ease.value(at: (fraction - peakAt) / (1 - peakAt))
        let ring = ease.value(at: fraction)
        return Pose(dotScale: dot, ringScale: 1 + (ringEndScale - 1) * ring, ringOpacity: ringStartOpacity * (1 - ring))
    }
}

/// One play of a clock-drawn motion: when it started (nil at rest). `pending` covers the one frame between the new cards
/// being on screen and the view taking the start time (`onChange` runs after that frame), drawn as the motion's first frame
/// so the cards never flash at rest before they cascade.
struct MotionRun: Equatable {
    var start: Date?
    var pending = false

    static let rest = MotionRun()

    var isPlaying: Bool { start != nil || pending }

    /// Seconds since the start at `date`; nil at rest.
    func elapsed(at date: Date) -> Double? {
        if pending { return 0 }
        return start.map { date.timeIntervalSince($0) }
    }
}

extension EnvironmentValues {
    /// False in the unit test host, so snapshots draw Schedule at rest whenever they render it: no cascade, no pulse, no glide
    /// and no press (TT-164).
    @Entry var playsScheduleMotion: Bool = !UnitTestHost.isRunning
}

/// The unit test bundle is loaded into this run of the app (UI tests run the app on its own and still play the motion).
private enum UnitTestHost {
    static let isRunning = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

extension View {
    /// A timeline card (or with `moves` false, its rail marks or an empty-state card) arriving with the cascade, `order`
    /// places after the first card in view. At rest it is drawn as it is.
    func cascadeEntrance(_ run: MotionRun, order: Int, moves: Bool = true) -> some View {
        modifier(CascadeEntrance(run: run, order: order, moves: moves))
    }
}

private struct CascadeEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let run: MotionRun
    let order: Int
    let moves: Bool

    func body(content: Content) -> some View {
        // Paused (no frames) unless the cascade is playing; only the transforms below are worked out each frame.
        TimelineView(.animation(paused: run.start == nil)) { context in
            let pose = run.elapsed(at: context.date).map {
                CascadeMotion.pose(at: $0, order: order, moves: moves, reduceMotion: reduceMotion)
            } ?? CascadeMotion.rest
            content
                .opacity(pose.opacity)
                .scaleEffect(pose.scale)
                .offset(y: pose.offsetY)
        }
    }
}
