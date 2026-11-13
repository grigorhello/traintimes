import SwiftUI

/// The app's shared springs (TT-165, D59; the Motion-Spec board on the canvas has the table). One name per moment, written
/// once: the picker (D54, `PickerMotion`) and Settings (D57, `SettingsMotion`) keep their own. The bounce is on
/// transforms and never below a damping fraction of 0.45. Reduce Motion turns every transform off and leaves opacity only,
/// on `fade`.
enum TTMotion {
    /// A spring as numbers, so a view can draw it frame by frame (`progress(at:)`) from the same numbers as its
    /// `Animation`.
    struct Curve: Sendable {
        let response: Double
        let damping: Double

        var animation: Animation { .spring(response: response, dampingFraction: damping) }
        /// The same spring for a keyframe (`SpringKeyframe`).
        var spring: Spring { Spring(response: response, dampingRatio: damping) }

        /// How far the spring has got `time` seconds after the start, with no initial velocity: 0 at the start, 1 at rest,
        /// a little past 1 on the way for a bouncy one. The closed form of SwiftUI's `spring(response:dampingFraction:)`
        /// (natural frequency 2π ÷ response); it matches the curves sampled for the canvas.
        func progress(at time: Double) -> Double {
            let t = max(0, time)
            let omega = 2 * Double.pi / response
            guard damping < 1 else { return 1 - exp(-omega * t) * (1 + omega * t) }
            let root = (1 - damping * damping).squareRoot()
            let omegaDamped = omega * root
            let phase = omegaDamped * t
            return 1 - exp(-damping * omega * t) * (cos(phase) + damping / root * sin(phase))
        }
    }

    /// The two station names trading rows when the route is swapped (the vertical move; the arc rides on top of it).
    static let crossCurve = Curve(response: 0.55, damping: 0.74)
    /// The swap arrows turning half a turn, swinging about 19° past upright before they settle.
    static let turnCurve = Curve(response: 0.50, damping: 0.58)
    /// A pressed glass button springing back (0.88 to 1 on the swap button).
    static let pressCurve = Curve(response: 0.40, damping: 0.50)
    /// A small pop: the route pin after the swap lands, and a card's bell springing back from its swell (TT-166).
    static let popCurve = Curve(response: 0.35, damping: 0.45)
    /// The selected day's accent tile gliding to the tapped day (TT-164, D61).
    static let glideCurve = Curve(response: 0.45, damping: 0.72)
    /// Timeline cards arriving when a new set of trains is shown: from 20 pt up and 0.96 to rest (TT-164, D61); the day
    /// panel's tiles arriving from 6 pt down and 0.94 (TT-191).
    static let cascadeCurve = Curve(response: 0.44, damping: 0.62)
    /// The bell's toast rising 32 pt into place (TT-166); the alert capsule rising 12 pt from 0.94 since TT-191.
    static let toastCurve = Curve(response: 0.45, damping: 0.68)
    /// The Trip details journey card riding 12 pt down into place as the sheet's content arrives (TT-167).
    static let cardCurve = Curve(response: 0.42, damping: 0.72)
    /// Each Trip details stop row riding 10 pt down into place, `stopDelay` after the first (TT-167).
    static let stopsCurve = Curve(response: 0.40, damping: 0.70)
    /// The Trip details alert button growing from 0.9, `buttonDelay` after the card (TT-167).
    static let growCurve = Curve(response: 0.45, damping: 0.60)
    /// The alert capsule growing into the day panel, with no overshoot (TT-191, D71).
    static let morphCurve = Curve(response: 0.42, damping: 1.0)
    /// A day tile lit in the day panel, pressing in from 0.92 (TT-191).
    static let tilePressCurve = Curve(response: 0.30, damping: 0.75)
    /// A card's bell turned off: the outline settling from 0.86, quiet on purpose (TT-191).
    static let settleCurve = Curve(response: 0.40, damping: 0.70)
    /// Trip details' "Alert on" drawing in to make room for Repeat, with no overshoot (TT-192).
    static let drawInCurve = Curve(response: 0.28, damping: 1.0)
    /// A departed card rising 88 pt above the Now line as it presses to 0.96, about 2 pt past and back, and its rail dot
    /// following 30 pt (TT-203, D86).
    static let stepUpCurve = Curve(response: 0.55, damping: 0.78)
    /// The Now line gliding the minute's 7 pt onto a departing train's ring (TT-203).
    static let nowGlideCurve = Curve(response: 0.35, damping: 0.85)
    /// The next card springing back from its 1.03 lift: the departure's one bouncy moment (TT-203).
    static let liftBackCurve = Curve(response: 0.35, damping: 0.45)
    /// The next card's time growing from 32 to 34 pt as it takes the lead (TT-203).
    static let leadTimeCurve = Curve(response: 0.45, damping: 0.72)

    static var cross: Animation { crossCurve.animation }
    static var turn: Animation { turnCurve.animation }
    static var press: Animation { pressCurve.animation }
    static var pop: Animation { popCurve.animation }
    static var glide: Animation { glideCurve.animation }
    static var cascade: Animation { cascadeCurve.animation }
    static var toast: Animation { toastCurve.animation }
    static var card: Animation { cardCurve.animation }
    static var stops: Animation { stopsCurve.animation }
    static var grow: Animation { growCurve.animation }
    static var morph: Animation { morphCurve.animation }
    static var drawIn: Animation { drawInCurve.animation }
    /// An arriving element fading in while its spring moves it: the Trip details card, stop rows and button (TT-167).
    static var appear: Animation { .easeOut(duration: 0.15) }
    /// When Trip details stop row `index` starts, after the first: 24 ms apart, and from the ninth row on with the eighth,
    /// so a long trip is still by about 0.7 s (TT-167).
    static func stopDelay(_ index: Int) -> Double { 0.024 * Double(min(max(index, 0), 8)) }
    /// The Trip details alert button starts 120 ms after the card and the first stop (TT-167).
    static let buttonDelay = 0.12
    /// The bell's swell to 1.3 before `pop`; the glyph swaps at its top (TT-166).
    static var swell: Animation { .easeOut(duration: 0.1) }
    /// Status changes, and every transform-free stand-in under Reduce Motion.
    static var fade: Animation { .easeOut(duration: 0.18) }

    /// When the card `index` places after the first in view starts its cascade: 60 ms, then 40 ms apart, and from the
    /// sixth card on all together, so a day change is still by about 0.7 s where the rider looks (TT-164).
    static func cascadeDelay(_ index: Int) -> Double { 0.06 + 0.04 * Double(min(max(index, 0), 5)) }
}
