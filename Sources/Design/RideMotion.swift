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

    /// The ride card's rows rise one after another: the first 120 ms after the card appears, then 40 ms apart.
    static func riseDelay(order: Int) -> Double { 0.12 + 0.04 * Double(order) }

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

/// The ring around your stop's pin while it is next (Live-Ride round 3): 20 pt, 2 pt in the accent, spreading to 1.9 times
/// and fading, every 1.8 s. Still in snapshots and with Reduce Motion.
struct PinRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.playsRideMotion) private var playsMotion

    private static let size: CGFloat = 20

    var body: some View {
        let animates = playsMotion && !reduceMotion
        TimelineView(.animation(minimumInterval: nil, paused: !animates)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let phase = time.truncatingRemainder(dividingBy: RideMotion.rippleLoop) / RideMotion.rippleLoop
            let progress = RideMotion.rippleEase(phase / RideMotion.rippleSpread)
            Circle()
                .strokeBorder(TTColor.accent, lineWidth: 2)
                .frame(width: Self.size, height: Self.size)
                .scaleEffect(1 + 0.9 * progress)
                .opacity(animates && phase < RideMotion.rippleSpread ? 0.7 * (1 - progress) : 0)
        }
        .frame(width: Self.size, height: Self.size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
