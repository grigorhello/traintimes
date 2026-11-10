import SwiftUI

/// The Notifications page (TT-168, D57): a status card with the one action that fits the permission, the five things the app
/// notifies about as plain ticked text (information, so not in a card), the "My alerts" card and a footnote. The permission
/// is read when the page opens and each time the app returns to the foreground, so coming back from the iOS Settings app
/// updates the page and the main row.
struct SettingsNotificationsPage: View {
    let viewModel: SettingsViewModel
    /// "My alerts": switches to the Alerts tab.
    let onShowAlerts: () -> Void
    @Environment(\.openURL) private var openURL
    /// Counts the times the bell should swing: on arriving with notifications on, and when they have just been allowed.
    @State private var swings = 0

    private static let kinds = [
        "settings.notifications.kind_delays",
        "settings.notifications.kind_cancellations",
        "settings.notifications.kind_back_on_time",
        "settings.notifications.kind_line_notices",
        "settings.notifications.kind_usual_train",
    ]

    /// The row that opened this page has read the permission; until then the page reads as never asked.
    private var state: NotificationPermission { viewModel.permission ?? .notAsked }

    var body: some View {
        SettingsPageScaffold(title: "settings.notifications") {
            VStack(alignment: .leading, spacing: TTSpace.s2) {
                statusCard.settingsRise(order: 0)
                kindsList.settingsRise(order: 1)
                myAlertsCard.padding(.top, TTSpace.s1).settingsRise(order: 2)
                SettingsNote(text: "settings.notifications.footnote").settingsRise(order: 3)
            }
        }
        .task { await viewModel.refreshPermission() }
        .onAppear { if state == .allowed { swings += 1 } }
        .onChange(of: viewModel.permission) { _, permission in
            if permission == .allowed { swings += 1 }
        }
    }

    // MARK: Status

    private var statusTitle: LocalizedStringKey {
        switch state {
        case .allowed: "settings.notifications.status_on"
        case .off: "settings.notifications.status_off"
        case .notAsked: "settings.notifications.status_ask"
        }
    }

    private var statusDetail: LocalizedStringKey {
        switch state {
        case .allowed: "settings.notifications.status_on_detail"
        case .off:
            viewModel.alertCount == 0
                ? "settings.notifications.status_off_detail_empty" : "settings.notifications.status_off_detail"
        case .notAsked: "settings.notifications.status_ask_detail"
        }
    }

    private var statusCard: some View {
        SettingsCard {
            HStack(spacing: 14) {
                badge
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle).font(TTFont.headline).foregroundStyle(TTColor.ink)
                    Text(statusDetail)
                        .font(TTFont.footnote)
                        .foregroundStyle(TTColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(TTSpace.s4)

            switch state {
            case .allowed:
                SettingsHairline()
                Button { openURL(viewModel.notificationSettingsURL) } label: {
                    SettingsRow(title: "settings.notifications.sounds") {
                        SettingsValue(text: Text("settings.notifications.ios_settings"))
                        SettingsExternalArrow()
                    }
                }
                .buttonStyle(SettingsRowButtonStyle())
                .accessibilityIdentifier("settings.notifications.iosSettings")
            case .off:
                Button { openURL(viewModel.notificationSettingsURL) } label: {
                    Text("settings.notifications.turn_on_ios").frame(maxWidth: .infinity)
                }
                .buttonStyle(.ttGlassPrimary)
                .padding(.horizontal, TTSpace.s4)
                .padding(.bottom, TTSpace.s4)
                .accessibilityIdentifier("settings.notifications.turnOnInSettings")
            case .notAsked:
                Button { Task { await viewModel.turnOnNotifications() } } label: {
                    Text("settings.notifications.turn_on").frame(maxWidth: .infinity)
                }
                .buttonStyle(.ttGlassPrimary)
                .padding(.horizontal, TTSpace.s4)
                .padding(.bottom, TTSpace.s4)
                .accessibilityIdentifier("settings.notifications.turnOn")
            }
        }
    }

    /// A 44 pt circle with the bell: accent on its soft fill while on, red while off, grey while never asked.
    private var badge: some View {
        let ink: Color = switch state {
        case .allowed: TTColor.accent
        case .off: TTColor.cancelInk
        case .notAsked: TTColor.inkSecondary
        }
        let fill: Color = switch state {
        case .allowed: TTColor.accentSoft
        case .off: TTColor.cancelFill
        case .notAsked: TTColor.surfaceRaised
        }
        return Image(systemName: "bell.fill")
            .font(.system(size: TTSize.iconSM))
            .foregroundStyle(ink)
            .settingsBellSwing(trigger: swings)
            .frame(width: TTSize.targetMin, height: TTSize.targetMin)
            .background(fill, in: Circle())
            .animation(.easeOut(duration: 0.25), value: viewModel.permission)
            .settingsPop(trigger: viewModel.permission, from: 0.72)
            .accessibilityHidden(true)
    }

    // MARK: Information

    /// "You'll be notified about": ticks in the accent while notifications are on, grey otherwise. Not tappable.
    private var kindsList: some View {
        let tick = state == .allowed ? TTColor.accent : TTColor.inkTertiary
        return VStack(alignment: .leading, spacing: 9) {
            Text("settings.notifications.about").font(TTFont.footnote).foregroundStyle(TTColor.inkSecondary)
            ForEach(Self.kinds, id: \.self) { kind in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(TTFont.body).foregroundStyle(tick)
                    Text(LocalizedStringKey(kind)).font(TTFont.subhead).foregroundStyle(TTColor.ink)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TTSpace.s4)
        .padding(.top, TTSpace.s2)
        .padding(.bottom, 6)
        .animation(.easeOut(duration: 0.25), value: viewModel.permission)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.notifications.kinds")
    }

    private var myAlertsCard: some View {
        SettingsCard {
            Button { onShowAlerts() } label: {
                SettingsRow(title: "settings.notifications.my_alerts") {
                    SettingsValue(text: Text(verbatim: "\(viewModel.alertCount)").monospacedDigit())
                    SettingsChevron()
                }
            }
            .buttonStyle(SettingsRowButtonStyle())
            .accessibilityIdentifier("settings.myAlerts")
        }
    }
}
