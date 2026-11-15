import SwiftUI

extension View {
    /// Counts a tap on this information-only element as interest (TT-209, `interest_tapped`, ids in `docs/ANALYTICS.md`).
    /// A simultaneous tap: nothing on screen changes. Not inside a button: a child's gesture takes the tap from it (the Schedule
    /// card counts its own, `DepartureCardView`, TT-214).
    func tracksInterest(_ element: String) -> some View {
        simultaneousGesture(TapGesture().onEnded { InterestTracker.tap(element) })
    }
}
