import SwiftUI

/// On board's motion (TT-172, the Live-Spec motion table): the springs by name, the Live dot's ripple and the ring around
/// your stop's pin. Reduce Motion keeps fades only: the train marker jumps and the dot breathes.
enum RideMotion {
    /// Rows rising into place, the next stop's name sliding up, the ride strip dropping in.
    static let riseCurve = TTMotion.Curve(response: 0.44, damping: 0.62)
    /// The train marker gliding along the rail.
    static let glideCurve = TTMotion.Curve(response: 0.60, damping: 1.00)
    /// The card pressing in when the train is about to arrive, and when it stops.
    static let pressCurve = TTMotion.Curve(response: 0.40, damping: 0.50)
    /// Your stop's pin turning into the tick.
    static let tickCurve = TTMotion.Curve(response: 0.35, damping: 0.50)
    /// "Yes, on board" folding the question card into the ride strip (TT-175); the card lands on `pressCurve`.
    static let foldCurve = TTMotion.Curve(response: 0.46, damping: 0.82)

    static var rise: Animation { riseCurve.animation }
    static var glide: Animation { glideCurve.animation }
    static var press: Animation { pressCurve.animation }
    static var tick: Animation { tickCurve.animation }
    static var fold: Animation { foldCurve.animation }
    /// Your stop's tint and the card's tint cross-fading.
    static var tint: Animation { .easeOut(duration: 0.25) }
    /// The arrival wish (TT-223, D103; board 23's `ra-out` and `.w`): "Now" rolls up and out in 300 ms, the wish rolls in
    /// from below in 380 ms, each a third of the 68 pt line away and blurred 4 pt while it moves.
    static var wishOut: Animation { .easeInOut(duration: 0.3) }
    static var wishIn: Animation { .timingCurve(0.2, 0.7, 0.2, 1, duration: 0.38) }
    static let wishTravel: CGFloat = 23
    static let wishBlur: CGFloat = 4

    /// The ride card's rows rise one after another: the first 120 ms after the card appears, then 40 ms apart.
    static func riseDelay(order: Int) -> Double { 0.12 + 0.04 * Double(order) }

    // MARK: The ride screen alive (TT-224, D106; Live view canvas boards 18 to 22, `alive.css`)

    /// The one loop while the train moves: every 2.4 s, 1.5 s in the last minute (arriving).
    static let movingLoop = 2.4
    static let arrivingLoop = 1.5
    /// The share of a loop where a moment of it is (`alive.css` keyframes): the halo spreads until 46 %, the glint shows from
    /// 14 % and reaches the next stop at 60 %, that stop's dot answers from 57 % (1.5 at 66 %, back at 84 %), your pin's ring
    /// from 60 %.
    static let haloEnd = 0.46
    static let glintStart = 0.14
    static let glintEnd = 0.60
    static let answerStart = 0.57
    static let answerPeak = 0.66
    static let answerEnd = 0.84
    static let pinAnswerStart = 0.60
    /// The halo: scale 0.7 to 1.95, opacity 0.3 to 0. The glint: 4 by 20 pt.
    static let haloScale: ClosedRange<Double> = 0.7...1.95
    static let haloOpacity = 0.3
    static let glintSize = CGSize(width: 4, height: 20)
    /// The next stop's dot at the peak of its answer; your pin's ring spreading to 1.9 from 0.75.
    static let answerScale = 1.5
    static let pinAnswerScale = 1.9
    static let pinAnswerOpacity = 0.75

    /// A stop passes: the dot pops (1 to 1.75 to 1, 460 ms) and one ring leaves it (to 3.4, 0.75 to 0, 560 ms), 320 ms after
    /// the event, when the name and time fade to the passed style and the Tick plays.
    static let passDelay = 0.32
    static let popScale = 1.75
    static let popDuration = 0.46
    static let passRingScale = 3.4
    static let passRingOpacity = 0.75
    static let passRingDuration = 0.56
    /// `cubic-bezier(0.34, 1.56, 0.64, 1)`: the pops' overshoot.
    static func pop(duration: Double) -> Animation { .timingCurve(0.34, 1.56, 0.64, 1, duration: duration) }
    /// The row fading to the passed style.
    static var passFade: Animation { .easeOut(duration: 0.3).delay(passDelay) }

    /// Your stop is next: the rail from the train to your pin in the accent at 34 %, fading in over 600 ms. The train stops
    /// 24 pt short of your pin's centre until it gets there.
    static let softRailOpacity = 0.34
    static var softRail: Animation { .easeOut(duration: 0.6) }
    static let pinClearance: CGFloat = 24

    /// At your stop, 450 ms after the event: the train slides into the pin, the check pops in (380 ms) and draws (320 ms,
    /// 120 ms later), one ring (1 to 1.6, 0.5 to 0, 700 ms), one sheen across the hero card (a band 45 % of its width, 900 ms),
    /// and the card's press 120 ms after the check's pop.
    static let arrivalDelay = 0.45
    static let checkDrawDelay = 0.12
    static let checkDrawDuration = 0.32
    static let arrivalRingScale = 1.6
    static let arrivalRingOpacity = 0.5
    static let arrivalRingDuration = 0.7
    static let sheenWidth = 0.45
    static let sheenDuration = 0.9
    static var sheen: Animation { .timingCurve(0.4, 0, 0.2, 1, duration: sheenDuration) }
    static let arrivalPressDelay = arrivalDelay + checkDrawDelay

    /// The train creeping by the clock between two redraws a second apart.
    static var creep: Animation { .linear(duration: 1) }

    /// Where `time` (seconds, the reference date's) falls in a loop of `loop` seconds, 0 to 1: every piece of the loop reads
    /// the same clock, so the halo, the glint and the answers stay in step without sharing state.
    static func loopPhase(at time: Double, loop: Double) -> Double {
        guard loop > 0 else { return 0 }
        let phase = time.truncatingRemainder(dividingBy: loop) / loop
        return phase < 0 ? phase + 1 : phase
    }

    /// `x` from `start` to `end` of a loop as 0 to 1, clamped.
    static func progress(_ x: Double, from start: Double, to end: Double) -> Double {
        guard end > start else { return x >= end ? 1 : 0 }
        return min(max((x - start) / (end - start), 0), 1)
    }

    /// One ripple loop and the share of it a ring takes to spread and fade (the canvas's `ldot-ring` and `pin-ring`).
    static let rippleLoop = 1.8
    static let rippleSpread = 0.75

    /// The ripple's easing, cubic-bezier(0.2, 0.6, 0.3, 1) sampled closely enough for a 1.35 s fade.
    static func rippleEase(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return 1 - pow(1 - t, 2.4)
    }
}

extension EnvironmentValues {
    /// False in snapshot tests: the rows are drawn settled and the ripples still.
    @Entry var playsRideMotion: Bool = true
}

/// The Live dot (Live-Spec): 8 pt in the accent, with two rings spreading from it 0.9 s apart while the train's position
/// is measured; grey and still on the timetable; grey and rippling while train detection checks (TT-175). Reduce Motion:
/// the dot breathes.
struct LiveDot: View {
    var isLive = true
    var isChecking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.playsRideMotion) private var playsMotion

    private static let size: CGFloat = 8
    private static let ring: CGFloat = 2
    private static let spread = 3.1

    var body: some View {
        let colour = isLive && !isChecking ? TTColor.accent : TTColor.inkTertiary
        let animates = (isLive || isChecking) && playsMotion
        TimelineView(.animation(minimumInterval: nil, paused: !animates)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Circle()
                .fill(colour)
                .frame(width: Self.size, height: Self.size)
                .scaleEffect(animates && reduceMotion ? breath(at: time) : 1)
                .overlay {
                    if animates && !reduceMotion {
                        ripple(at: time, colour: colour)
                        ripple(at: time - RideMotion.rippleLoop / 2, colour: colour)
                    }
                }
        }
        .frame(width: Self.size, height: Self.size)
        .accessibilityHidden(true)
    }

    private func ripple(at time: Double, colour: Color) -> some View {
        let phase = time.truncatingRemainder(dividingBy: RideMotion.rippleLoop) / RideMotion.rippleLoop
        let progress = RideMotion.rippleEase(phase / RideMotion.rippleSpread)
        return Circle()
            .strokeBorder(colour, lineWidth: Self.ring)
            .frame(width: Self.size, height: Self.size)
            .scaleEffect(1 + (Self.spread - 1) * progress)
            .opacity(phase < RideMotion.rippleSpread ? 0.8 * (1 - progress) : 0)
    }

    /// 1 to 0.85 and back over the loop.
    private func breath(at time: Double) -> Double {
        let phase = time.truncatingRemainder(dividingBy: RideMotion.rippleLoop) / RideMotion.rippleLoop
        return 1 - 0.15 * (0.5 - 0.5 * cos(2 * .pi * phase))
    }
}
