import SwiftUI

/// Schedule's motion (TT-164, D61; the Motion-Spec board on the canvas): the cards cascading in when a new set of trains is
/// shown, and the Now dot's pulse on the way back to Now. Both are drawn from the clock, as the swap is (`SwapMotion`), so
/// that a card that has only just been inserted starts from its first pose in its first frame. The day tile's glide is a
/// SwiftUI spring (`TTMotion.glide`) in `ScheduleView`, and its press (`DayPressMotion`) a SwiftUI animation too, so a
/// slow frame after the tap delays both rather than eating their first frames.
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

/// The tapped day pressing to 0.90 and springing back to about 1.016 on `TTMotion.press`'s curve, from rest, over 0.75 s:
/// the screen's one bouncy moment (TT-164, D61).
enum DayPressMotion {
    static let pressed: CGFloat = 0.90
    static let duration = 0.75

    /// The scale `elapsed` seconds into a press; 1 at rest.
    static func scale(at elapsed: Double) -> CGFloat {
        guard elapsed > 0, elapsed < duration else { return 1 }
        return pressed + (1 - pressed) * TTMotion.pressCurve.progress(at: elapsed)
    }

    /// The scale while a tile's tap count animates linearly from one whole number to the next over `duration`: each tap
    /// plays one press, and a whole number is at rest.
    static func scale(presses: Double) -> CGFloat {
        scale(at: (presses - presses.rounded(.down)) * duration)
    }
}

/// When the cascade and the Now pulse started, kept apart from the screen: only the cards, their rail marks and the Now dot
/// read it, so starting or ending a play redraws them and not the timeline around them (a full redraw of a day of cards
/// took a moment in a Debug build, TT-164).
@MainActor @Observable final class ScheduleMotionClock {
    /// The last `ScheduleViewModel.entranceRequest` whose cascade has been started.
    var cascadeSeen: Int
    var cascadeStart: Date?
    var pulseStart: Date?

    init(cascadeSeen: Int = 0) {
        self.cascadeSeen = cascadeSeen
    }
}

/// What a card or rail mark needs to work out its part of the cascade: the clock, the latest request for one, whether new
/// trains are still awaited, and whether Schedule plays motion at all.
struct CascadeCue: Sendable {
    var clock: ScheduleMotionClock?
    var request = 0
    var awaitsNewTrains = false
    var plays = false

    static let rest = CascadeCue()

    /// Read in the entering view's own body, so the clock's changes redraw that view only. Pending, unseen at the first
    /// pose, from the tap that asks for new trains until the start is taken.
    @MainActor var run: MotionRun {
        guard let clock else { return .rest }
        return MotionRun(start: clock.cascadeStart, pending: plays && (request != clock.cascadeSeen || awaitsNewTrains))
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
    func cascadeEntrance(_ cue: CascadeCue, order: Int, moves: Bool = true) -> some View {
        modifier(CascadeEntrance(cue: cue, order: order, moves: moves))
    }

    /// A day tile pressing (`DayPressMotion`) each time `count`, its taps, goes up. A SwiftUI animation starts on its first
    /// frame, so a slow frame after the tap (the new trains being built) holds the tile at rest and the press still plays
    /// in full; a keyframe's clock ran on through that frame and the 0.90 was never drawn. Played from the tap rather than
    /// from the button's pressed state, which a quick tap in a scroll view may never draw; holding a tile still shows the
    /// usual 0.97 press.
    func dayPress(_ count: Int, animated: Bool) -> some View {
        modifier(DayPress(presses: Double(count)))
            .animation(animated ? .linear(duration: DayPressMotion.duration) : nil, value: count)
    }
}

private struct CascadeEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cue: CascadeCue
    let order: Int
    let moves: Bool

    func body(content: Content) -> some View {
        let run = cue.run
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

private struct DayPress: ViewModifier, Animatable {
    /// The tile's tap count, animated from one whole number to the next.
    var presses: Double

    // `ViewModifier` is main-actor isolated, `Animatable` is not: the witness is `nonisolated` (it only reads and writes a Double).
    nonisolated var animatableData: Double {
        get { presses }
        set { presses = newValue }
    }

    func body(content: Content) -> some View {
        content.scaleEffect(DayPressMotion.scale(presses: presses))
    }
}
