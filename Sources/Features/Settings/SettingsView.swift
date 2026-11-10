import SwiftUI

/// The pages Settings pushes (TT-168, D57).
enum SettingsPage: Hashable {
    case notifications, about, testing
}

/// Settings, the third tab (TT-105, redesigned in TT-168, D57): the large title and five single-line rows in two cards, four
/// in App Store builds. Appearance and Time format change in one tap; Notifications, About and Testing open their own pages.
/// Nothing here is needed to use the timetable; no login, payment, advertising or rating prompt (D5).
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @State private var path: [SettingsPage] = []
    /// "My alerts" on the Notifications page: switches to the Alerts tab.
    private let onShowAlerts: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: SettingsViewModel, onShowAlerts: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: viewModel)
        self.onShowAlerts = onShowAlerts
    }

    var body: some View {
        NavigationStack(path: $path) {
            SettingsMainPage(viewModel: viewModel, open: { path.append($0) })
                .navigationDestination(for: SettingsPage.self) { page in
                    switch page {
                    case .notifications: SettingsNotificationsPage(viewModel: viewModel, onShowAlerts: onShowAlerts)
                    case .about: SettingsAboutPage(viewModel: viewModel)
                    case .testing: SettingsTestingPage(viewModel: viewModel)
                    }
                }
        }
        // Reads the permission when Settings appears and again each time the app returns to the foreground, also from the
        // iOS Settings app while the Notifications page is open.
        .task(id: scenePhase) {
            if scenePhase == .active { await viewModel.refreshPermission() }
        }
    }
}

/// The main view: title, then the two cards of design/frames/settings.png.
struct SettingsMainPage: View {
    @Bindable var viewModel: SettingsViewModel
    let open: (SettingsPage) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TTSpace.s3) {
                Text("nav.settings")
                    .font(TTFont.largeTitle)
                    .foregroundStyle(TTColor.ink)
                    .padding(.bottom, TTSpace.s1)
                    .frame(height: 52, alignment: .bottomLeading)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("settings.title")

                SettingsCard {
                    appearanceRow
                    SettingsHairline()
                    timeFormatRow
                    SettingsHairline()
                    notificationsRow
                }
                SettingsCard {
                    aboutRow
                    if viewModel.showsTesting {
                        SettingsHairline()
                        testingRow
                    }
                }
            }
            .padding(.horizontal, TTSpace.s5)
            .padding(.bottom, TTSpace.s6)
        }
        .background(TTColor.canvas)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Rows

    private var appearanceRow: some View {
        SettingsRow(title: "settings.appearance", trailingInset: TTSpace.s2) {
            GlassSwitch(
                selection: $viewModel.appearance,
                options: [
                    .init(
                        value: .system, label: .symbol("circle.lefthalf.filled"), name: "settings.appearance.system",
                        identifier: "settings.appearance.system"
                    ),
                    .init(
                        value: .light, label: .symbol("sun.max.fill"), name: "settings.appearance.light",
                        identifier: "settings.appearance.light"
                    ),
                    .init(
                        value: .dark, label: .symbol("moon.fill"), name: "settings.appearance.dark",
                        identifier: "settings.appearance.dark"
                    ),
                ],
                segmentWidth: 46, turns: true
            )
        }
    }

    private var timeFormatRow: some View {
        SettingsRow(title: "settings.time_format", trailingInset: TTSpace.s2) {
            GlassSwitch(
                selection: $viewModel.timeFormat,
                options: [
                    .init(
                        value: .device, label: .text("settings.time_format.device"), name: "settings.time_format.device.name",
                        identifier: "settings.timeFormat.device"
                    ),
                    .init(
                        value: .twelveHour, label: .text("settings.time_format.12h"), name: "settings.time_format.12h.name",
                        identifier: "settings.timeFormat.12h"
                    ),
                    .init(
                        value: .twentyFourHour, label: .text("settings.time_format.24h"), name: "settings.time_format.24h.name",
                        identifier: "settings.timeFormat.24h"
                    ),
                ],
                segmentWidth: 52
            )
        }
    }

    /// A dot and a word: green On, red Off, grey Off (never asked). Empty until the permission is read.
    private var notificationsRow: some View {
        Button { open(.notifications) } label: {
            SettingsRow(title: "settings.notifications") {
                HStack(spacing: 6) {
                    if let dot = viewModel.notificationDot {
                        Circle()
                            .fill(dot.color)
                            .frame(width: 8, height: 8)
                            .settingsPop(trigger: viewModel.permission, from: 0.2)
                    }
                    if let word = viewModel.notificationWord {
                        SettingsValue(text: Text(verbatim: word))
                    }
                }
                SettingsChevron()
            }
        }
        .buttonStyle(SettingsRowButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("settings.notifications")
    }

    private var aboutRow: some View {
        Button { open(.about) } label: {
            SettingsRow(title: "settings.about") {
                SettingsValue(text: Text(verbatim: viewModel.versionValue).monospacedDigit())
                SettingsChevron()
            }
        }
        .buttonStyle(SettingsRowButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("settings.about")
    }

    /// "Off", or in amber with a dot what is on, "Delays · Mock time".
    private var testingRow: some View {
        let active = viewModel.isTestingActive
        return Button { open(.testing) } label: {
            SettingsRow(title: "settings.testing") {
                HStack(spacing: 6) {
                    if active { Circle().fill(TTColor.delayInk).frame(width: 8, height: 8) }
                    Text(verbatim: viewModel.testingValue)
                        .font(TTFont.body)
                        .foregroundStyle(active ? TTColor.delayInk : TTColor.inkSecondary)
                        .lineLimit(1)
                }
                SettingsChevron()
            }
        }
        .buttonStyle(SettingsRowButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("settings.testing")
    }
}

extension SettingsViewModel.NotificationDot {
    /// Accent, cancel ink or ink-tertiary.
    var color: Color {
        switch self {
        case .green: TTColor.accent
        case .red: TTColor.cancelInk
        case .grey: TTColor.inkTertiary
        }
    }
}

#Preview {
    SettingsView(viewModel: SettingsViewModel(settings: AppSettings()))
}
