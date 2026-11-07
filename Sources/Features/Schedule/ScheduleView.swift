import SwiftUI

/// Schedule tab: inline "Train Times" header and the Settings gear. The timeline arrives in TT-112.
struct ScheduleView: View {
    let onSettings: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("app.name")
                    .font(TTFont.navTitle)
                    .foregroundStyle(TTColor.ink)
                    .accessibilityIdentifier("schedule.title")
                Spacer()
                IconButton(systemName: "gearshape", label: "nav.settings", action: onSettings)
                    .accessibilityIdentifier("schedule.settings")
            }
            .padding(.leading, TTSpace.s5)
            .padding(.trailing, TTSpace.s2)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TTColor.canvas)
        // Title stays set so Settings' back button reads "Train Times"; the header above replaces the bar.
        .navigationTitle(Text("app.name"))
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    NavigationStack { ScheduleView(onSettings: {}) }
}
