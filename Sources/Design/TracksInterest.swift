import SwiftUI

extension View {
    /// Counts a tap on this information-only element as interest (TT-209, `interest_tapped`, ids in `docs/ANALYTICS.md`).
    /// A simultaneous tap: nothing on screen changes, and a button around it (a Schedule card, TT-214) still takes the tap.
    func tracksInterest(_ element: String) -> some View {
        simultaneousGesture(TapGesture().onEnded { InterestTracker.tap(element) })
    }
}
