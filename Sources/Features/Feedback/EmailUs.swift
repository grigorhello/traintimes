import SwiftUI
import UIKit

/// "Email us" (TT-202, D85): opens the rider's mail app at support@traintimes.ca. With no mail app set up (a phone without
/// Mail, or the simulator) the tap would do nothing, so the address is copied and an alert says so.
struct EmailUsButton<Label: View>: View {
    @ViewBuilder let label: () -> Label
    @Environment(\.openURL) private var openURL
    @State private var showsCopied = false

    var body: some View {
        Button {
            openURL(FeedbackViewModel.mailURL) { accepted in
                guard !accepted else { return }
                UIPasteboard.general.string = FeedbackViewModel.supportEmail
                showsCopied = true
            }
        } label: {
            label()
        }
        .alert(Text("feedback.copied.title"), isPresented: $showsCopied) {
            Button("feedback.ok", role: .cancel) {}
        } message: {
            Text("feedback.copied.body")
        }
    }
}
