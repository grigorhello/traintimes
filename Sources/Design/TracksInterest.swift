import SwiftUI

extension View {
    /// Counts a tap on this information-only element as interest (TT-209, `interest_tapped`, ids in `docs/ANALYTICS.md`).
    /// A simultaneous tap: nothing on screen changes.
    func tracksInterest(_ element: String) -> some View {
        simultaneousGesture(TapGesture().onEnded { InterestTracker.tap(element) })
    }

    /// The same inside a view with a tap of its own (a Schedule card): a child's gesture takes the tap from its parent, so
    /// this one does the parent's `action` too, and the tap still does what it did.
    func tracksInterest(_ element: String, then action: @escaping () -> Void) -> some View {
        onTapGesture {
            InterestTracker.tap(element)
            action()
        }
    }
}
