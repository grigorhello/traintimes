import SwiftUI

/// The Alerts tab (TT-143), as design/frames/alerts.png and alerts-empty.png: the large title with "Add alert", My alerts
/// with each rule's state, Recent updates and Line notices, each group a card of rows; a group with nothing in it is
/// hidden, and with no rule the empty card shows. A list, so a rule row swipes left to delete; "Alert deleted · Undo"
/// shows above the tab bar for 5 s. With notifications off while an alert is switched on, a card tops the list (TT-169, D58)
/// and the rows that are on read "Not delivering"; when notifications are allowed again the card folds away and a toast says so.
struct AlertsView: View {
    let viewModel: AlertsViewModel
    /// "Add alert": the Schedule tab, with "Tap the bell on a train".
    var onAddAlert: () -> Void = {}
    /// A row that needs action: Alert setup for its rule.
    var onOpenRule: (AlertSetupRequest) -> Void = { _ in }
    /// A recent update: Trip details for that trip and service date.
    var onOpenUpdate: (NotificationLink) -> Void = { _ in }
    /// A line notice: the notice sheet.
    var onOpenLineNotice: () -> Void = {}

    @Environment(\.timeFormatter) private var formatter
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    /// Counts the times the card's bell should shake: once as the card appears.
    @State private var shakes = 0

    /// Canvas `.rule`: 64 pt minimum row height.
    private static let ruleMinHeight: CGFloat = 64
    /// Canvas `.rule .txt` and `.upd .txt`: 2 pt between lines.
    private static let lineGap: CGFloat = 2
    /// Canvas empty state: the card starts 48 pt under the title bar.
    private static let emptyTop: CGFloat = TTSpace.s12

    var body: some View {
        let rules = viewModel.ruleRows(formatter)
        let updates = viewModel.updateRows(formatter)
        let notices = viewModel.noticeRows(formatter)
        List {
            header(showsAdd: !rules.isEmpty)
            if viewModel.warnsNotificationsOff {
                notificationsOffCard
            }
            if rules.isEmpty {
                emptyState
            } else {
                groupTitle("alerts.my_alerts", top: TTSpace.s2)
                ForEach(rules) { row in
                    ruleRow(row, position: .init(row.id, in: rules.map(\.id)))
                }
            }
            if !updates.isEmpty {
                groupTitle("alerts.recent_updates", top: TTSpace.s6)
                ForEach(updates) { row in
                    updateRow(row, position: .init(row.id, in: updates.map(\.id)))
                }
            }
            if !notices.isEmpty {
                groupTitle("alerts.line_notices", top: TTSpace.s6)
                ForEach(notices) { row in
                    noticeRow(row, position: .init(row.id, in: notices.map(\.id)))
                }
            }
            Color.clear.frame(height: TTSpace.s6).plainRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .background(TTColor.canvas)
        .overlay(alignment: .bottom) { toasts }
        .animation(.easeOut(duration: 0.25), value: viewModel.deleted)
        .animation(.easeOut(duration: 0.25), value: viewModel.showsNotificationsOn)
        // The card folds away on a spring when notifications are allowed again.
        .animation(.spring(response: 0.46, dampingFraction: 0.82), value: viewModel.warnsNotificationsOff)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alerts.root")
    }

    // MARK: Header and groups

    /// Large title "Alerts" with "Add alert" (canvas `.navbar`), which the empty state leaves to its card.
    private func header(showsAdd: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("tab.alerts")
                .font(TTFont.largeTitle)
                .foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: TTSpace.s3)
            if showsAdd {
                Button("button.add_alert", action: onAddAlert)
                    .buttonStyle(.ttText)
                    .accessibilityIdentifier("alerts.add")
            }
        }
        .frame(minHeight: TTSize.targetMin)
        .plainRow(EdgeInsets(top: 0, leading: TTSpace.s5, bottom: 0, trailing: TTSpace.s2))
    }

    /// "My alerts", in footnote over its card.
    private func groupTitle(_ key: LocalizedStringKey, top: CGFloat) -> some View {
        Text(key)
            .font(TTFont.footnote)
            .foregroundStyle(TTColor.inkSecondary)
            .accessibilityAddTraits(.isHeader)
            .plainRow(EdgeInsets(top: top, leading: TTSpace.s5 + TTSpace.s4, bottom: TTSpace.s2, trailing: TTSpace.s5))
    }

    /// Notifications are off while an alert is switched on (TT-169, D58): the Notifications page's off card, one button, not
    /// dismissible. Canvas `.al-in > .sg-card`: 2 pt under the title row's gap, and 20 pt above "My alerts".
    private var notificationsOffCard: some View {
        SettingsCard {
            HStack(spacing: 14) {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: TTSize.iconSM))
                    .foregroundStyle(TTColor.cancelInk)
                    .settingsBellSwing(trigger: shakes)
                    .frame(width: TTSize.targetMin, height: TTSize.targetMin)
                    .background(TTColor.cancelFill, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.notifications.status_off").font(TTFont.headline).foregroundStyle(TTColor.ink)
                    Text(verbatim: AlertsViewModel.offDetail(count: viewModel.switchedOnCount))
                        .font(TTFont.footnote)
                        .foregroundStyle(TTColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(TTSpace.s4)
            Button { openURL(AlertSetupViewModel.notificationSettingsURL) } label: {
                Text("settings.notifications.turn_on_ios").frame(maxWidth: .infinity)
            }
            .buttonStyle(.ttGlassPrimary)
            .padding(.horizontal, TTSpace.s4)
            .padding(.bottom, TTSpace.s4)
            .accessibilityIdentifier("alerts.turnOnInSettings")
        }
        .onAppear { shakes += 1 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alerts.notificationsOff")
        .plainRow(EdgeInsets(top: TTSpace.s2 + 2, leading: TTSpace.s5, bottom: TTSpace.s3, trailing: TTSpace.s5))
    }

    /// The bell card, "No alerts yet" and the primary "Add alert", then the footnote (`alerts-empty.png`).
    private var emptyState: some View {
        VStack(spacing: TTSpace.s4) {
            EmptyStateCard(
                systemImage: "bell", title: "alerts.empty.title", message: "alerts.empty.body", actionTitle: "button.add_alert",
                isPrimaryAction: true, action: onAddAlert
            )
            Text("alerts.empty.footnote")
                .font(TTFont.footnote)
                .foregroundStyle(TTColor.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TTSpace.s3)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alerts.empty")
        .plainRow(EdgeInsets(top: Self.emptyTop, leading: TTSpace.s5, bottom: 0, trailing: TTSpace.s5))
    }

    // MARK: Rows

    /// Canvas `.rule`: the train and direction, the days or date, the state in words; a switch or a chevron.
    @ViewBuilder private func ruleRow(_ row: AlertsViewModel.RuleRow, position: CardPosition) -> some View {
        let content = HStack(spacing: TTSpace.s3) {
            VStack(alignment: .leading, spacing: Self.lineGap) {
                Text(verbatim: row.title)
                    .font(TTFont.headline)
                    .monospacedDigit()
                    .foregroundStyle(TTColor.ink)
                Text(verbatim: row.days)
                    .font(TTFont.footnote)
                    .foregroundStyle(TTColor.inkSecondary)
                AlertStateLabel(state: row.state)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: row.state)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("alerts.rule.state")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            switch row.accessory {
            case .toggle(let isOn, let isEnabled):
                Toggle(isOn: Binding(get: { isOn }, set: { _ = viewModel.setOn($0, for: row.id) })) {
                    Text(verbatim: row.title)
                }
                .labelsHidden()
                .tint(TTColor.accent)
                .disabled(!isEnabled)
                .accessibilityIdentifier("alerts.rule.switch")
            case .chevron:
                Image(systemName: "chevron.right")
                    .font(TTFont.body)
                    .foregroundStyle(TTColor.inkSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, TTSpace.s4)
        .padding(.vertical, TTSpace.s3)
        .frame(minHeight: Self.ruleMinHeight)
        .cardBackground(position, colorScheme: colorScheme)

        Group {
            if row.accessory == .chevron {
                Button {
                    if let request = viewModel.setupRequest(for: row.id) { onOpenRule(request) }
                } label: {
                    content.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(row.testID)
        .cardRow()
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { _ = viewModel.delete(row.id) } label: { Text("button.delete") }
        }
    }

    /// Canvas `.upd`: the status icon, the notification's title and body, and when it arrived.
    @ViewBuilder private func updateRow(_ row: AlertsViewModel.UpdateRow, position: CardPosition) -> some View {
        let content = message(
            symbol: row.kind.symbol, ink: row.kind.ink, title: row.title, body: row.body, time: row.time, position: position
        )
        Group {
            if let link = row.link {
                Button { onOpenUpdate(link) } label: { content.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
        .accessibilityIdentifier("alerts.update.\(row.id)")
        .cardRow()
    }

    private func noticeRow(_ row: AlertsViewModel.NoticeRow, position: CardPosition) -> some View {
        Button(action: onOpenLineNotice) {
            message(
                symbol: "exclamationmark.triangle", ink: TTColor.delayInk, title: row.line, body: row.summary, time: row.time,
                position: position
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("alerts.notice.\(row.id)")
        .cardRow()
    }

    private func message(symbol: String, ink: Color, title: String, body: String, time: String, position: CardPosition) -> some View {
        HStack(alignment: .top, spacing: TTSpace.s3) {
            Image(systemName: symbol)
                .font(.system(size: TTSize.iconButtonGlyph, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: TTSize.iconMD, height: TTSize.iconMD)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Self.lineGap) {
                Text(verbatim: title)
                    .font(TTFont.headline)
                    .monospacedDigit()
                    .foregroundStyle(TTColor.ink)
                Text(verbatim: body)
                    .font(TTFont.subhead)
                    .monospacedDigit()
                    .foregroundStyle(TTColor.inkSecondary)
                Text(verbatim: time)
                    .font(TTFont.footnote)
                    .monospacedDigit()
                    .foregroundStyle(TTColor.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, TTSpace.s4)
        .padding(.vertical, TTSpace.s3)
        .accessibilityElement(children: .combine)
        .cardBackground(position, colorScheme: colorScheme)
    }

    // MARK: Toast

    /// "Alert deleted" with Undo, for 5 s after a swipe; or "Notifications are on" for 2.5 s once the rider has turned them
    /// on again (TT-169).
    @ViewBuilder private var toasts: some View {
        if viewModel.deleted != nil {
            Toast(
                message: String(localized: "alerts.deleted"), systemImage: "trash", tint: TTColor.inkSecondary, actionTitle: "button.undo"
            ) {
                Task { await viewModel.undo() }
            }
            .padding(.horizontal, TTSpace.s5)
            .padding(.bottom, TTSpace.s2)
        } else if viewModel.showsNotificationsOn {
            Toast(message: String(localized: "alerts.notifications_on"), systemImage: "checkmark.circle.fill")
                .padding(.horizontal, TTSpace.s5)
                .padding(.bottom, TTSpace.s2)
        }
    }
}

/// Where a row sits in its group's card: the first rounds the top corners, the last the bottom ones and casts the card's
/// shadow, and every row after the first starts with a hairline.
struct CardPosition: Equatable {
    var isFirst: Bool
    var isLast: Bool

    init<ID: Equatable>(_ id: ID, in ids: [ID]) {
        isFirst = ids.first == id
        isLast = ids.last == id
    }
}

private extension View {
    /// A list row with no separator, no background of its own and the given insets.
    func plainRow(_ insets: EdgeInsets = EdgeInsets()) -> some View {
        listRowInsets(insets)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    /// A row of a group's card: 20 pt from the screen edges, rows touching.
    func cardRow() -> some View {
        plainRow(EdgeInsets(top: 0, leading: TTSpace.s5, bottom: 0, trailing: TTSpace.s5))
    }

    /// One row's part of its group's card (canvas `.list`): surface, 18 pt radius at the card's ends, hairlines between
    /// rows, and the card shadow under the last row in light mode.
    func cardBackground(_ position: CardPosition, colorScheme: ColorScheme) -> some View {
        let radius = TTRadius.lg
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: position.isFirst ? radius : 0,
            bottomLeadingRadius: position.isLast ? radius : 0,
            bottomTrailingRadius: position.isLast ? radius : 0,
            topTrailingRadius: position.isFirst ? radius : 0
        )
        return frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape
                    .fill(TTColor.surface)
                    .shadow(color: .black.opacity(position.isLast && colorScheme != .dark ? 0.06 : 0), radius: 1, x: 0, y: 1)
            }
            .overlay(alignment: .top) {
                if !position.isFirst {
                    Rectangle().fill(TTColor.hairline).frame(height: 1)
                }
            }
    }
}

private extension AlertUpdate.Kind {
    /// The status icons of the timeline's badges: delay, on time, cancel.
    var symbol: String {
        switch self {
        case .delay: "clock.badge.exclamationmark"
        case .recovery: "checkmark.circle.fill"
        case .cancelled, .skipped: "xmark.circle.fill"
        }
    }

    var ink: Color {
        switch self {
        case .delay: TTColor.delayInk
        case .recovery: TTColor.ontimeInk
        case .cancelled, .skipped: TTColor.cancelInk
        }
    }
}
