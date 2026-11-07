import SwiftUI

/// Alerts tab placeholder until TT-143: the empty state.
struct AlertsView: View {
    var body: some View {
        VStack {
            EmptyStateCard(systemImage: "bell", title: "alerts.empty.title", message: "alerts.empty.body")
                .padding(TTSpace.s5)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TTColor.canvas)
        .accessibilityIdentifier("alerts.root")
    }
}

#Preview {
    AlertsView()
}
