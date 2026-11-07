import SwiftUI

/// Settings, pushed from the Schedule gear. Content arrives in TT-105.
struct SettingsView: View {
    var body: some View {
        TTColor.canvas
            .ignoresSafeArea()
            .navigationTitle(Text("nav.settings"))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("settings.root")
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
