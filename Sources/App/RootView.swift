import SwiftUI

/// Placeholder root until the app shell with the Schedule and Alerts tabs lands (TT-104).
/// Uses system styles only because the design tokens arrive in TT-102.
struct RootView: View {
    var body: some View {
        Text("app.name")
            .font(.title2.weight(.semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("root.title")
    }
}

#Preview {
    RootView()
}
