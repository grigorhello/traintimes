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

/// The Now line playing once when the timeline shows: after the launch's scroll settles, on the Schedule tab or the Today
/// tile, and on coming back to the tab or the app (TT-164, D61; TT-197, D80). The rule draws across from the rail on
/// `TTMotion.drawInCurve`, the dot swells to 1.7 and back over 0.6 s while a 2 pt accent ring spreads from it to 3.4 times
/// and fades, a second ring follows 0.3 s later, and the "Now" label pops to 1.15 and back. Under Reduce Motion nothing
/// moves: the line, dot and label dip to 45 % and come back over 0.6 s.
enum NowPulse {
    struct Pose: Equatable {
        var dotScale: CGFloat = 1
        var ringScale: CGFloat = 1
        /// 0 at rest, when the ring is not drawn.
        var ringOpacity = 0.0
        /// The second ring, 0.3 s behind the first.
        var echoScale: CGFloat = 1
        var echoOpacity = 0.0
        /// How much of the rule is drawn, from the rail; 1 at rest.
        var ruleReveal: CGFloat = 1
        var labelScale: CGFloat = 1
        /// The line, dot and label together; only Reduce Motion changes it.
        var opacity = 1.0
        /// The line, dot and label gliding down onto a departing train's ring (TT-203); 0 at rest.
        var offsetY: CGFloat = 0
    }

    static let rest = Pose()
    /// One ring's spread, and the dot's swell.
    static let ringDuration = 0.6
    static let echoDelay = 0.3
    static let duration = echoDelay + ringDuration
    static let reducedDuration = 0.6
    static let peakScale: CGFloat = 1.7
    /// The dot is largest at 35 % of its swell.
    static let peakAt = 0.35
    static let ringEndScale: CGFloat = 3.4
    static let ringStartOpacity = 0.6
    static let labelPeak: CGFloat = 1.15
    static let labelDuration = 0.45
    static let reducedDip = 0.55

    static func pose(at elapsed: Double, reduceMotion: Bool = false) -> Pose {
        guard elapsed >= 0 else { return rest }
        if reduceMotion {
            guard elapsed < reducedDuration else { return rest }
            return Pose(opacity: 1 - reducedDip * sin(Double.pi * elapsed / reducedDuration))
        }
        guard elapsed < duration else { return rest }
        let ease = UnitCurve.easeOut
        var pose = Pose()
        if elapsed < ringDuration {
            let fraction = elapsed / ringDuration
            pose.dotScale = fraction < peakAt
                ? 1 + (peakScale - 1) * ease.value(at: fraction / peakAt)
                : peakScale - (peakScale - 1) * ease.value(at: (fraction - peakAt) / (1 - peakAt))
            (pose.ringScale, pose.ringOpacity) = ring(at: fraction)
        }
        let echo = (elapsed - echoDelay) / ringDuration
        if echo >= 0, echo < 1 { (pose.echoScale, pose.echoOpacity) = ring(at: echo) }
        pose.ruleReveal = min(1, TTMotion.drawInCurve.progress(at: elapsed))
        if elapsed < labelDuration { pose.labelScale = 1 + (labelPeak - 1) * sin(Double.pi * elapsed / labelDuration) }
        return pose
    }

    /// A ring `fraction` of the way through its spread: its scale and opacity.
    private static func ring(at fraction: Double) -> (CGFloat, Double) {
        let spread = UnitCurve.easeOut.value(at: fraction)
        return (1 + (ringEndScale - 1) * spread, ringStartOpacity * (1 - spread))
    }
}

/// A train leaving Today's timeline at the minute tick (TT-203, D86; the Departed-A2 board on the canvas): the Now line glides
/// onto its ring and the dot swells with one ring; the card presses to 0.96 and rises 88 pt, going flat and grey, while its
/// ring follows 30 pt up and fills to a small dot; "Departed" cross-fades in; the Now rule draws out from the rail under
/// where the card was; the next card lifts to 1.03 and springs back as its time grows to 34 pt and its countdown and glint
/// start. Still by about 1.05 s. Under Reduce Motion the card and its dot fade in at their new place over 0.28 s.
enum DeparturePlay {
    /// A card's pose: offset and scale on top of its place, how far it has gone flat and grey (`look`, 1 departed), its
    /// status swap, its time's scale and the countdown's opacity.
    struct Card: Equatable {
        var offsetY: CGFloat = 0
        var scale: CGFloat = 1
        var look: CGFloat = 0
        /// The departed status's opacity; the old status shows at `statusOut`.
        var statusIn = 0.0
        var statusOut = 1.0
        var timeScale: CGFloat = 1
        var countdown = 1.0
        var opacity = 1.0

        /// At rest: departed cards flat, grey and pressed back, the others as they are.
        static func rest(departed: Bool) -> Card {
            departed ? Card(scale: TTTimeline.departedScale, look: 1, statusIn: 1, statusOut: 0) : Card()
        }
    }

    /// A departing train's ring on the rail: offset above its rest place, and how far it has filled into the small dot.
    struct Rail: Equatable {
        var offsetY: CGFloat = 0
        var fill: CGFloat = 1
        var opacity = 1.0
    }

    static let delay = 0.06
    static let lookDuration = 0.26
    static let statusOutDuration = 0.14
    static let statusInDelay = 0.16
    static let statusInDuration = 0.2
    static let ruleDelay = 0.16
    static let nextDelay = 0.3
    static let nextUp = 0.12
    static let nextLift: CGFloat = 1.03
    static let countdownDuration = 0.2
    /// The glint starts on the next train's connector this long after the tick.
    static let glintDelay = 0.35
    static let dotPeak: CGFloat = 1.6
    static let dotOut = 0.16
    static let dotBack = 0.3
    static let ringEnd: CGFloat = 3.2
    static let ringDuration = 0.58
    static let duration = 1.1
    static let reducedDuration = 0.28
    /// The lead's 34 pt time against the others' 32 pt.
    static let leadTimeRatio: CGFloat = 34.0 / 32.0

    private static func fraction(_ time: Double, _ duration: Double) -> Double { min(max(time / duration, 0), 1) }
    private static func easeOut(_ time: Double, _ duration: Double) -> Double {
        UnitCurve.easeOut.value(at: fraction(time, duration))
    }
    /// The card's and its ring's spring, from `delay`.
    private static func stepUp(_ elapsed: Double) -> CGFloat {
        guard elapsed > delay else { return 0 }
        return CGFloat(TTMotion.stepUpCurve.progress(at: elapsed - delay))
    }

    /// The departing card `elapsed` seconds into the play; `wasLead` when it was the next train (34 pt time).
    static func departing(at elapsed: Double, wasLead: Bool, reduceMotion: Bool = false) -> Card {
        var pose = Card.rest(departed: true)
        if reduceMotion {
            pose.opacity = easeOut(elapsed, reducedDuration)
            return pose
        }
        guard elapsed < duration else { return pose }
        let progress = stepUp(elapsed)
        let look = CGFloat(easeOut(elapsed - delay, lookDuration))
        pose.offsetY = TTTimeline.departedLift * (1 - progress)
        pose.scale = 1 - (1 - TTTimeline.departedScale) * progress
        pose.look = look
        pose.statusOut = 1 - easeOut(elapsed, statusOutDuration)
        pose.statusIn = easeOut(elapsed - statusInDelay, statusInDuration)
        pose.timeScale = wasLead ? 1 + (leadTimeRatio - 1) * (1 - look) : 1
        return pose
    }

    /// The new next card `elapsed` seconds into the play.
    static func next(at elapsed: Double, reduceMotion: Bool = false) -> Card {
        var pose = Card()
        guard !reduceMotion, elapsed < duration else { return pose }
        let time = elapsed - nextDelay
        let smallTime: CGFloat = 1 / leadTimeRatio
        guard time > 0 else {
            pose.timeScale = smallTime
            pose.countdown = 0
            return pose
        }
        if time < nextUp {
            pose.scale = 1 + (nextLift - 1) * CGFloat(easeOut(time, nextUp))
        } else {
            pose.scale = nextLift - (nextLift - 1) * CGFloat(TTMotion.liftBackCurve.progress(at: time - nextUp))
        }
        pose.timeScale = smallTime + (1 - smallTime) * CGFloat(TTMotion.leadTimeCurve.progress(at: time))
        pose.countdown = easeOut(time, countdownDuration)
        return pose
    }

    /// The departing train's ring `elapsed` seconds into the play.
    static func rail(at elapsed: Double, reduceMotion: Bool = false) -> Rail {
        if reduceMotion { return Rail(opacity: easeOut(elapsed, reducedDuration)) }
        guard elapsed < duration else { return Rail() }
        let progress = stepUp(elapsed)
        return Rail(offsetY: TTTimeline.departedRailLift * (1 - progress), fill: min(max(progress, 0), 1))
    }

    /// The Now line, dot and label `elapsed` seconds into the play, after a move of `glide` points.
    static func now(at elapsed: Double, glide: CGFloat, reduceMotion: Bool = false) -> NowPulse.Pose {
        var pose = NowPulse.Pose()
        guard !reduceMotion, elapsed < duration else { return pose }
        pose.offsetY = -glide * (1 - CGFloat(TTMotion.nowGlideCurve.progress(at: elapsed)))
        let dot = elapsed - delay
        if dot > 0, dot < dotOut {
            pose.dotScale = 1 + (dotPeak - 1) * CGFloat(easeOut(dot, dotOut))
        } else if dot >= dotOut, dot < dotOut + dotBack {
            pose.dotScale = dotPeak - (dotPeak - 1) * CGFloat(UnitCurve.easeInOut.value(at: fraction(dot - dotOut, dotBack)))
        }
        if dot > 0, dot < ringDuration {
            let spread = easeOut(dot, ringDuration)
            pose.ringScale = 1 + (ringEnd - 1) * CGFloat(spread)
            pose.ringOpacity = NowPulse.ringStartOpacity * (1 - spread)
        }
        pose.ruleReveal = elapsed <= ruleDelay ? 0 : CGFloat(min(1, TTMotion.drawInCurve.progress(at: elapsed - ruleDelay)))
        return pose
    }
}

/// What the timeline needs for a departure's play: the clock, the latest request, which cards it moves and how far the Now
/// line went. Only the views it moves read the clock, so its start redraws them alone.
struct DepartureCue: Sendable {
    var clock: ScheduleMotionClock?
    var request = 0
    var departing: Set<TripKey> = []
    var lead: TripKey?
    var next: TripKey?
    var glide: CGFloat = 0
    var plays = false

    static let rest = DepartureCue()

    /// Pending from the update that moved the trains until the start is taken, so they never flash at their new place.
    @MainActor var run: MotionRun {
        guard plays, let clock else { return .rest }
        return MotionRun(start: clock.departureStart, pending: request != clock.departureSeen)
    }

    func moves(_ id: TripKey) -> Bool { departing.contains(id) || next == id }
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
    /// The last `ScheduleViewModel.departureRequest` whose play has been started, and when it started (TT-203).
    var departureSeen: Int
    var departureStart: Date?

    init(cascadeSeen: Int = 0, departureSeen: Int = 0) {
        self.cascadeSeen = cascadeSeen
        self.departureSeen = departureSeen
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
enum UnitTestHost {
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
