import SwiftUI

/// The swap button's motion in the route card (TT-165, D59, variant B "Cross" on the canvas): the two station names trade
/// rows along arcs, lifting on a raised pill as they pass; the arrows turn half a turn; the glass button presses and springs
/// back; the three rail dots light up from top to bottom and the pin pops.
///
/// The card draws it frame by frame from `pose(at:step:carry:)`, a function of the seconds since the tap, so that a second
/// tap can carry on from where the first one is, and a test can read any moment. Nothing here animates by itself.
enum SwapMotion {
    /// By now every spring is within 0.1 % of rest and the card is drawn at rest.
    static let duration: TimeInterval = 1.0
    /// How far each name arcs to the side at the peak (the one moving up goes right, the one moving down goes left).
    static let reach: CGFloat = 18
    /// How much bigger a name is at the peak of its arc.
    static let lift: CGFloat = 0.06
    /// The arc: nothing at 0, the peak at 20 % of 0.65 s, back at rest by 60 %.
    static let peakTime = 0.13
    static let restTime = 0.39
    /// The glass button starts this much smaller.
    static let pressScale: CGFloat = 0.88
    /// The pin: up to this scale over 0.1 s from 0.25 s, then a pop spring back from 0.35 s.
    static let pinPeak: CGFloat = 1.2
    static let pinStart = 0.25
    static let pinLand = 0.35
    /// The rail dots: 40 ms for the first, 70 ms between them, 0.32 s each (35 % up, the rest back down).
    static let dotStart = 0.04
    static let dotGap = 0.07
    static let dotLength = 0.32
    static let dotCount = 3
    /// What a second tap carries over from the first fades out over this long.
    static let carryFade = 0.2

    /// How one station name is drawn: moved off its row, pushed to the side, enlarged, on a raised pill (0 is none).
    struct NamePose: Equatable {
        var y: CGFloat = 0
        var x: CGFloat = 0
        var scale: CGFloat = 1
        var pill = 0.0
    }

    /// The whole card at one moment. `from` and `to` are the names in the From and To rows.
    struct Pose: Equatable {
        var from = NamePose()
        var to = NamePose()
        /// The swap glyph's turn in degrees: -180 at the start, 0 at rest, about 19 past it on the way.
        var arrowDegrees = 0.0
        var buttonScale: CGFloat = 1
        /// How lit each rail dot is, 0 to 1.
        var dotLights = [Double](repeating: 0, count: SwapMotion.dotCount)
        var pinScale: CGFloat = 1
    }

    /// What the card keeps from a motion that a second tap interrupts: how each name and the arrows were drawn. The name in
    /// the From row goes to the To row (and the other way round), so the poses are swapped by whoever builds it.
    struct Carry: Equatable {
        var from = NamePose()
        var to = NamePose()
        var arrowDegrees = 0.0
    }

    static let rest = Pose()

    /// The card `elapsed` seconds after a tap. `step` is the distance between the two rows (a row and its hairline): at the
    /// start each name stands in the other's row, so the names have traded in the data and still show the old order.
    static func pose(at elapsed: TimeInterval, step: CGFloat, carry: Carry = Carry()) -> Pose {
        guard elapsed < duration else { return rest }
        let t = max(0, elapsed)
        let moved = 1 - TTMotion.crossCurve.progress(at: t)
        let arcAmount = arcShape(at: t)
        let fade = 1 - smooth(t / carryFade)

        func name(start: CGFloat, direction: CGFloat, carry: NamePose) -> NamePose {
            NamePose(
                y: (start + carry.y) * CGFloat(moved),
                x: direction * reach * CGFloat(arcAmount) + carry.x * CGFloat(fade),
                scale: 1 + lift * CGFloat(arcAmount) + (carry.scale - 1) * CGFloat(fade),
                pill: max(arcAmount, carry.pill * fade)
            )
        }

        return Pose(
            from: name(start: step, direction: 1, carry: carry.from),
            to: name(start: -step, direction: -1, carry: carry.to),
            arrowDegrees: (-180 + carry.arrowDegrees) * (1 - TTMotion.turnCurve.progress(at: t)),
            buttonScale: 1 - (1 - pressScale) * CGFloat(1 - TTMotion.pressCurve.progress(at: t)),
            dotLights: (0..<dotCount).map { dotLight(at: t - dotStart - dotGap * Double($0)) },
            pinScale: pinScale(at: t)
        )
    }

    /// The carry for a second tap `elapsed` seconds into a motion that began with `carry`: the pose just before the tap, with
    /// the names exchanged.
    static func carry(at elapsed: TimeInterval, step: CGFloat, from previous: Carry = Carry()) -> Carry {
        let current = pose(at: elapsed, step: step, carry: previous)
        return Carry(from: current.to, to: current.from, arrowDegrees: current.arrowDegrees)
    }

    /// 0 to 1 to 0: ease-in-out up to the peak, ease-in-out down to rest.
    private static func arcShape(at t: Double) -> Double {
        if t <= 0 || t >= restTime { return 0 }
        if t < peakTime { return smooth(t / peakTime) }
        return 1 - smooth((t - peakTime) / (restTime - peakTime))
    }

    /// One dot's glow `t` seconds after its start: ease-out up in 35 % of its length, ease-out back down.
    private static func dotLight(at t: Double) -> Double {
        let peak = 0.35 * dotLength
        if t <= 0 || t >= dotLength { return 0 }
        if t < peak { return easeOut(t / peak) }
        return 1 - easeOut((t - peak) / (dotLength - peak))
    }

    private static func pinScale(at t: Double) -> CGFloat {
        if t <= pinStart { return 1 }
        if t < pinLand { return 1 + (pinPeak - 1) * CGFloat(easeOut((t - pinStart) / (pinLand - pinStart))) }
        return pinPeak - (pinPeak - 1) * CGFloat(TTMotion.popCurve.progress(at: t - pinLand))
    }

    private static func smooth(_ x: Double) -> Double {
        let x = min(1, max(0, x))
        return x * x * (3 - 2 * x)
    }

    private static func easeOut(_ x: Double) -> Double {
        let x = min(1, max(0, x))
        return 1 - (1 - x) * (1 - x)
    }
}

extension EnvironmentValues {
    /// Snapshot tests set this to draw the route card as if a swap were that many seconds old (the names already traded in
    /// the data); nil is the app, which draws it from the clock.
    @Entry var swapFrozenAt: TimeInterval? = nil
}
