import SwiftUI

/// Settings, the third tab (TT-105, D48): the large title, then the cards of design/frames/settings.png.
/// Nothing here is needed to use the timetable; no login, payment, advertising or rating prompt (D5).
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TTSpace.s2) {
                Text("nav.settings")
                    .font(TTFont.largeTitle)
                    .foregroundStyle(TTColor.ink)
                    .frame(minHeight: TTSize.targetMin)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("settings.title")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        segmentRow("settings.appearance", selection: $viewModel.appearance, options: [
                            (Appearance.system, "settings.appearance.system"),
                            (Appearance.light, "settings.appearance.light"),
                            (Appearance.dark, "settings.appearance.dark"),
                        ])
                        hairline
                        segmentRow("settings.time_format", selection: $viewModel.timeFormat, options: [
                            (TimeFormat.device, "settings.time_format.device"),
                            (TimeFormat.twelveHour, "settings.time_format.12h"),
                            (TimeFormat.twentyFourHour, "settings.time_format.24h"),
                        ])
                    }
                }

                header("settings.notifications")
                Card(padding: 0) { permissionRow }
                footnote("settings.notifications_footnote")

                if viewModel.showsTesting {
                    header("settings.testing")
                    Card(padding: 0) {
                        segmentRow("settings.demo_trains", selection: $viewModel.demoTrains, options: [
                            (DemoTrains.off, "settings.demo_trains.off"),
                            (DemoTrains.delays, "settings.demo_trains.delays"),
                            (DemoTrains.offline, "settings.demo_trains.offline"),
                        ])
                    }
                    footnote("settings.demo_trains_footnote")
                }

                header("settings.data_privacy")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        linkRow("settings.schedule_data", "settings.schedule_data_sub", SettingsViewModel.dataURL, id: "settings.scheduleData")
                        hairline
                        linkRow("settings.privacy", "settings.privacy_sub", SettingsViewModel.privacyURL, id: "settings.privacy")
                        hairline
                        linkRow(
                            "settings.official_updates", "settings.official_updates_sub", SettingsViewModel.officialUpdatesURL,
                            id: "settings.officialUpdates"
                        )
                    }
                }
                footnote("settings.independent")

                header("settings.about")
                Card(padding: 0) { aboutRow }
            }
            .padding(.horizontal, TTSpace.s5)
            .padding(.bottom, TTSpace.s6)
        }
        .background(TTColor.canvas)
        // Reads the permission when Settings appears and again each time the app returns to the foreground.
        .task(id: scenePhase) {
            if scenePhase == .active { await viewModel.refreshPermission() }
        }
    }

    // MARK: Rows

    private func segmentRow<Value: Hashable>(
        _ title: LocalizedStringKey, selection: Binding<Value>, options: [(value: Value, title: LocalizedStringKey)]
    ) -> some View {
        VStack(alignment: .leading, spacing: TTSpace.s2) {
            Text(title).font(TTFont.body).foregroundStyle(TTColor.ink)
            SegmentedControl(selection: selection, options: options)
        }
        .padding(.horizontal, TTSpace.s4)
        .padding(.vertical, TTSpace.s3)
    }

    private var permissionRow: some View {
        HStack(spacing: TTSpace.s3) {
            VStack(alignment: .leading, spacing: TTSpace.s1 / 2) {
                Text("settings.notification_permission").font(TTFont.body).foregroundStyle(TTColor.ink)
                if let permission = viewModel.permission {
                    HStack(spacing: TTSpace.s1) {
                        if let symbol = permission.symbol {
                            Image(systemName: symbol).font(.system(size: TTSize.iconSM))
                        }
                        Text(permission.title).font(TTFont.footnote)
                    }
                    .foregroundStyle(permission.ink)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("settings.permission")
                }
            }
            Spacer(minLength: 0)
            if viewModel.permission == .off {
                Button("button.open_settings") { openURL(viewModel.notificationSettingsURL) }
                    .buttonStyle(.ttText)
                    .accessibilityIdentifier("settings.openSettings")
            }
        }
        .modifier(SettingsRow())
    }

    private func linkRow(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ url: URL, id: String) -> some View {
        Button { openURL(url) } label: {
            HStack(spacing: TTSpace.s3) {
                VStack(alignment: .leading, spacing: TTSpace.s1 / 2) {
                    Text(title).font(TTFont.body).foregroundStyle(TTColor.ink)
                    Text(subtitle).font(TTFont.footnote).foregroundStyle(TTColor.inkSecondary)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(TTFont.body).foregroundStyle(TTColor.inkSecondary)
            }
            .modifier(SettingsRow())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var aboutRow: some View {
        HStack(spacing: TTSpace.s3) {
            // The app icon at 36 pt keeps its light look in both modes, as on the canvas.
            Image("TrainTimesSymbol")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(TTColor.onAccent)
                .frame(width: TTSize.appMark, height: TTSize.appMark)
                .background(TTColor.accent)
                .clipShape(RoundedRectangle(cornerRadius: TTRadius.sm, style: .continuous))
                .environment(\.colorScheme, .light)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: TTSpace.s1 / 2) {
                Text("app.name").font(TTFont.headline).foregroundStyle(TTColor.ink)
                Text(viewModel.versionLine).font(TTFont.footnote).foregroundStyle(TTColor.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .modifier(SettingsRow())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.about")
    }

    // MARK: Parts

    private var hairline: some View {
        Divider().overlay(TTColor.hairline)
    }

    private func header(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(TTFont.footnote)
            .foregroundStyle(TTColor.inkSecondary)
            .padding(.horizontal, TTSpace.s4)
            .padding(.top, TTSpace.s3)
            .accessibilityAddTraits(.isHeader)
    }

    private func footnote(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(TTFont.footnote)
            .foregroundStyle(TTColor.inkSecondary)
            .padding(.horizontal, TTSpace.s4)
    }
}

/// A list cell: 16 pt sides, 12 pt top and bottom, 52 pt minimum height.
private struct SettingsRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, TTSpace.s4)
            .padding(.vertical, TTSpace.s3)
            .frame(maxWidth: .infinity, minHeight: TTSize.targetMin + TTSpace.s2, alignment: .leading)
    }
}

private extension NotificationPermission {
    var title: LocalizedStringKey {
        switch self {
        case .allowed: "settings.permission.allowed"
        case .off: "settings.permission.off"
        case .notAsked: "settings.permission.not_asked"
        }
    }

    var symbol: String? {
        switch self {
        case .allowed: "checkmark.circle.fill"
        case .off: "xmark.circle.fill"
        case .notAsked: nil
        }
    }

    var ink: Color {
        switch self {
        case .allowed: TTColor.accent
        case .off: TTColor.cancelInk
        case .notAsked: TTColor.inkSecondary
        }
    }
}

#Preview {
    NavigationStack { SettingsView(viewModel: SettingsViewModel(settings: AppSettings())) }
}
