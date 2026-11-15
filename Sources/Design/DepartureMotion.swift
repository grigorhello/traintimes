import SwiftUI

/// Before departure's motion (TT-177, the Live-Spec motion table): the posted platform pressing in (the pending pill pulses
/// in `PlatformTag`). The rolling digits reuse the ride's countdown transition.
enum DepartureMotion {
    /// The posted number pressing in from 0.94 as it replaces the dash.
    static let platformCurve = TTMotion.Curve(response: 0.40, damping: 0.50)
    static let platformFrom = 0.94
}
