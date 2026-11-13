import SwiftUI

/// Before departure's motion (TT-177, the Live-Spec motion table): the watched strip growing the countdown, the posted
/// platform pressing in (the pending pill pulses in `PlatformTag`). Boarding's tint and the rolling digits reuse
/// `RideMotion.tint` and the ride's countdown transition.
enum DepartureMotion {
    /// The watched strip growing the countdown.
    static let growCurve = TTMotion.Curve(response: 0.46, damping: 0.82)
    /// The posted number pressing in from 0.94 as it replaces the dash.
    static let platformCurve = TTMotion.Curve(response: 0.40, damping: 0.50)
    static let platformFrom = 0.94

    static var grow: Animation { growCurve.animation }
}
