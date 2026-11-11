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
    /// The bell's toast rising 32 pt into place (TT-166).
    static let toastCurve = Curve(response: 0.45, damping: 0.68)
    /// The Enable alerts check popping in from 0.6 (TT-166).
    static let confirmCurve = Curve(response: 0.35, damping: 0.50)

    static var cross: Animation { crossCurve.animation }
    static var turn: Animation { turnCurve.animation }
    static var press: Animation { pressCurve.animation }
    static var pop: Animation { popCurve.animation }
    static var toast: Animation { toastCurve.animation }
    static var confirm: Animation { confirmCurve.animation }
    /// The bell's swell to 1.3 before `pop`; the glyph swaps at its top (TT-166).
    static var swell: Animation { .easeOut(duration: 0.1) }
    /// Status changes, and every transform-free stand-in under Reduce Motion.
    static var fade: Animation { .easeOut(duration: 0.18) }
}
