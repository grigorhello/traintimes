import SwiftUI

extension View {
    /// Counts a tap on this information-only element as interest (TT-209, `interest_tapped`, ids in `docs/ANALYTICS.md`).
    /// A simultaneous tap: nothing on screen changes, and a card or button around it still gets its own tap.
    func tracksInterest(_ element: String) -> some View {
        simultaneousGesture(TapGesture().onEnded { InterestTracker.tap(element) })
    }
}
