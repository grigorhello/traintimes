import SwiftUI

/// The Alerts tab as cards (TT-253, D129; Alerts canvas boards 35 to 44): the title, then each alert as Schedule's train
/// card for its next train, under its route said once as Schedule's marks, with a fourth row: the days it rings and "See
/// trains". The bell switches the alert off and on in place. A Time changed card offers "Pick a new train". With no alert,
/// the next three trains of Schedule's route as plain cards with their real bells. With notifications off the D58 card tops
/// the tab and every bell is crossed (a tap nudges the card's button). "Couldn't … · Try again", "Alert removed · Undo"
/// and "Notifications are on" show as the glass capsule above the tab bar (D71).
struct AlertsView: View {
    let viewModel: AlertsViewModel
    /// The empty tab's bells and their capsule, and the permission ask's face (TT-191); nil shows none.
    var bells: AlertBellModel?
    /// "See trains" on the empty tab with no route or no more trains today: the Schedule tab.
    var onSeeTrains: () -> Void = {}
    /// A card's "See trains": Schedule on the alert's route and its train's day.
    var onShowInSchedule: (AlertsViewModel.Jump) -> Void = { _ in }
    /// A tap on a card: its train's Trip details.
    var onOpenTrip: (AlertsViewModel.Jump) -> Void = { _ in }
    /// "Pick a new train" on a Time changed card: Schedule on that route, with "Tap the bell of your new train".
    var onPickNewTrain: (AlertRule) -> Void = { _ in }

    @Environment(\.timeFormatter) private var formatter
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counts the times the notifications-off card's bell should shake: once as the card appears.
    @State private var shakes = 0

    var body: some View {
        let muted = viewModel.warnsNotificationsOff
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .center, spacing: TTSpace.s2) {
                        Text("tab.alerts")
                            .font(TTFont.largeTitle)
                            .foregroundStyle(TTColor.ink)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                        // The Feedback button on every tab (TT-252, D128).
                        TabFeedbackEntry(tab: .alerts, source: .alertsTab, isBusy: viewModel.capsule != nil)
                    }
                    .frame(height: 48, alignment: .bottom)
                    if let offline = viewModel.offlineLine(formatter) {
                        Text(verbatim: offline)
                            .font(TTFont.footnote)
                            .monospacedDigit()
                            .foregroundStyle(TTColor.inkSecondary)
                            .accessibilityIdentifier("alerts.offline")
                    }
                }
                .padding(.bottom, TTSpace.s1)
                if muted {
                    notificationsOffCard
                }
                if viewModel.showsSuggestions {
                    emptyState
                        .transition(.opacity)
                } else {
                    ForEach(viewModel.sections(formatter)) { section in
                        AlertRouteLabel(from: section.from, to: section.to, line: section.line)
                        ForEach(section.cards) { item in
                            alertCard(item)
                                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.scale(scale: 0.96).combined(with: .opacity))
                        }
                    }
                }
            }
            .padding(.horizontal, TTSpace.s5)
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(TTColor.canvas)
        .overlay(alignment: .bottom) { capsuleLayer }
        // While the tab shows: its own load and live poll.
        .task { await viewModel.run() }
        // A bell here or on Schedule, a new alert: the cards read their trains again (the trips are kept for the day).
        .onChange(of: viewModel.rules.rules) { Task { await viewModel.load() } }
        .animation(reduceMotion ? TTMotion.fade : TTMotion.cascade, value: viewModel.showsSuggestions)
        // The card folds away on a spring when notifications are allowed again.
        .animation(.spring(response: 0.46, dampingFraction: 0.82), value: muted)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alerts.root")
    }

    // MARK: Notifications off (TT-169, D58)

    /// The Notifications page's off card, saying it once: "3 alerts can’t reach you." Its button nudges when a bell is
    /// tapped.
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
                    Text(verbatim: AlertsViewModel.offLine(count: viewModel.switchedOnCount))
                        .font(TTFont.footnote)
                        .foregroundStyle(TTColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(TTSpace.s4)
            Button { openURL(AlertBellModel.notificationSettingsURL) } label: {
                Text("settings.notifications.turn_on_ios").frame(maxWidth: .infinity)
            }
            .buttonStyle(.ttGlassPrimary)
            .keyframeAnimator(initialValue: 1.0, trigger: viewModel.nudges) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                LinearKeyframe(1.04, duration: 0.13, timingCurve: .easeOut)
                LinearKeyframe(1.0, duration: 0.25, timingCurve: .easeOut)
            }
            .padding(.horizontal, TTSpace.s4)
            .padding(.bottom, TTSpace.s4)
            .accessibilityIdentifier("alerts.turnOnInSettings")
        }
        .onAppear { shakes += 1 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alerts.notificationsOff")
        .padding(.bottom, TTSpace.s1)
    }

    // MARK: Cards

    /// One alert: Schedule's card with the days row, or, with no train to show, the card from the alert alone.
    @ViewBuilder private func alertCard(_ item: AlertsViewModel.Item) -> some View {
        Group {
            switch item.body {
            case let .train(card, trip, route):
                DepartureCardView(
                    card: card,
                    bell: face(item, trip: trip, route: route),
                    shakes: bells?.shakes(for: trip) ?? 0,
                    onOpen: { if let jump = viewModel.trip(item.id) { onOpenTrip(jump) } },
                    onBell: { viewModel.tapBell(item.id) },
                    onSize: { _ in },
                    footer: AnyView(AlertDaysRow(dots: item.dots, words: item.words, greys: item.greysDays)),
                    footerAccessory: AnyView(seeTrains(item)),
                    cardID: "alerts.card.\(trip.key.tripId)",
                    bellID: "alerts.bell.\(trip.key.tripId)",
                    tracksInterest: false,
                    keepsBell: true
                )
                // The card moving on to its next train: rows 1 to 3 cross-fade; the days row stays as it is.
                .animation(reduceMotion ? TTMotion.fade : TTMotion.cross, value: card.id)
            case .pending, .noTrain, .changed:
                // The permission rule is asked about the alert's own train while there is none read (`mayAlert`).
                let trip = viewModel.rule(item.id).map { AlertsViewModel.departure(of: $0).trip }
                let asks = trip != nil && bells?.asking == trip?.key
                AlertPlainCard(
                    item: item,
                    bell: asks ? item.bell.map { _ in BellFace.asking } : item.bell,
                    shakes: trip.flatMap { bells?.shakes(for: $0) } ?? 0,
                    onBell: { viewModel.tapBell(item.id) },
                    // A Time changed card opens Trip details on the alert alone (TT-254); the others have nothing to open.
                    onOpen: { if let jump = viewModel.trip(item.id) { onOpenTrip(jump) } },
                    accessory: item.bell == nil ? AnyView(pickNewTrain(item)) : AnyView(seeTrains(item))
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(item.testID)
    }

    /// The card's bell: the model's face, or the permission ask's while iOS asks.
    private func face(_ item: AlertsViewModel.Item, trip: Trip, route: Route) -> BellFace {
        if bells?.bell(for: trip, on: route) == .asking { return .asking }
        return item.bell ?? .off
    }

    /// The 32 pt pill: the Schedule tab's glyph and "See trains", accent on the neutral fill; a 44 pt target.
    private func seeTrains(_ item: AlertsViewModel.Item) -> some View {
        AlertCardPill(title: "alerts.see_trains", systemImage: "tram.fill", isFilled: false) {
            if let jump = viewModel.seeTrains(item.id) { onShowInSchedule(jump) }
        }
        .accessibilityIdentifier("alerts.seeTrains")
    }

    /// A Time changed card's filled "Pick a new train".
    private func pickNewTrain(_ item: AlertsViewModel.Item) -> some View {
        AlertCardPill(title: "alerts.pick_new_train", systemImage: nil, isFilled: true) {
            if let rule = viewModel.rule(item.id) { onPickNewTrain(rule) }
        }
        .accessibilityIdentifier("alerts.pickNewTrain")
    }

    // MARK: Empty

    /// "Tap the bell on a train you take. It stays here and on your widgets, and we tell you if it is late or cancelled.", then Schedule's route and its next three trains as plain
    /// cards with their bells; a bell tapped grows that card's days row. With no route or no more trains today, one row
    /// "See trains".
    private var emptyState: some View {
        let suggestions = viewModel.suggestions(formatter)
        return VStack(alignment: .leading, spacing: 10) {
            Text("alerts.empty.lead")
                .font(TTFont.subhead)
                .foregroundStyle(TTColor.inkSecondary)
                .frame(maxWidth: 300, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, TTSpace.s4)
            if let suggestions {
                AlertRouteLabel(
                    from: suggestions.route.from.name, to: suggestions.route.to.name, line: suggestions.route.line
                )
                ForEach(suggestions.trains) { train in
                    suggestionCard(train)
                }
            } else {
                SettingsCard {
                    Button(action: onSeeTrains) {
                        HStack {
                            Text("alerts.see_trains").font(TTFont.subhead.weight(.semibold)).foregroundStyle(TTColor.ink)
                            Spacer(minLength: TTSpace.s3)
                            Image(systemName: "chevron.right")
                                .font(TTFont.footnote.weight(.semibold))
                                .foregroundStyle(TTColor.inkTertiary)
                        }
                        .padding(.horizontal, TTSpace.s4)
                        .frame(height: TTSize.targetMin + TTSpace.s3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("alerts.seeTrains")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alerts.empty")
    }

    /// A next train as Schedule's card with its real bell (Schedule's bell model: on, off, refusals and its capsule); once
    /// it has an alert, the alert's days row grows under it.
    private func suggestionCard(_ train: AlertsViewModel.Suggestion) -> some View {
        let footer: AnyView? = train.alert.map { alert in
            AnyView(AlertDaysRow(dots: train.dots, words: train.words, greys: alert.paused))
        }
        let accessory: AnyView? = train.alert.map { alert in
            AnyView(
                AlertCardPill(title: "alerts.see_trains", systemImage: "tram.fill", isFilled: false) {
                    if let jump = viewModel.seeTrains(alert.id) { onShowInSchedule(jump) }
                }
                .accessibilityIdentifier("alerts.seeTrains")
            )
        }
        return DepartureCardView(
            card: train.card,
            bell: bells?.bell(for: train.trip, on: train.route) ?? .off,
            shakes: bells?.shakes(for: train.trip) ?? 0,
            onOpen: {
                onOpenTrip(AlertsViewModel.Jump(key: train.trip.key, originId: train.route.from.id, destinationId: train.route.to.id))
            },
            onBell: {
                guard let bells else { return }
                Task { await bells.tap(train.trip, on: train.route) }
            },
            onSize: { _ in },
            footer: footer,
            footerAccessory: accessory,
            cardID: "alerts.card.\(train.trip.key.tripId)",
            bellID: "alerts.next.bell.\(train.trip.key.tripId)",
            tracksInterest: false
        )
        .animation(reduceMotion ? TTMotion.fade : TTMotion.cascade, value: train.alert == nil)
    }

    // MARK: Capsule (D71)

    /// The tab's own capsule, or the one a bell raised (the empty tab's, or a refusal's from a card's bell).
    private var shownCapsule: TabCapsule? {
        if let own = viewModel.capsule { return .own(own) }
        guard let bell = bells?.capsule, !bell.isPanelOpen else { return nil }
        switch bell.kind {
        case .on, .failed, .notificationsOff, .notificationsOn: return .bell(bell)
        // Trip details' Remove alert from the tab shows the tab's own "Alert removed" (TT-254).
        case .off, .newTrain, .removed: return nil
        }
    }

    @ViewBuilder private var capsuleLayer: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                CapsuleVeil(isShown: shownCapsule != nil, isTall: false)
                    // From the screen's bottom edge, under the tab bar.
                    .offset(y: proxy.safeAreaInsets.bottom)
                GlassCapsuleStage(item: shownCapsule) { capsule in
                    capsuleView(capsule)
                }
                .padding(.bottom, TTSpace.s3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func capsuleView(_ capsule: TabCapsule) -> some View {
        switch capsule {
        case .own(let own):
            let action: AlertCapsuleView.Action? = switch own.kind {
            case .removed: AlertCapsuleView.Action(title: "button.undo") { Task { await viewModel.undo() } }
            case .failed: AlertCapsuleView.Action(title: "button.try_again") { Task { await viewModel.tryAgain() } }
            case .notificationsOn: nil
            }
            return AlertCapsuleView(glyph: own.glyph, words: own.words, action: action)
        case .bell(let bell):
            let today = viewModel.today
            // On the Alerts tab the new alert already has its card: no Repeat.
            let action: AlertCapsuleView.Action? = switch bell.kind {
            case .failed:
                AlertCapsuleView.Action(title: "button.try_again") { Task { await bells?.tryAgain() } }
            case .notificationsOff:
                AlertCapsuleView.Action(title: "capsule.turn_on") {
                    bells?.turnOnInSettings()
                    openURL(AlertBellModel.notificationSettingsURL)
                }
            default: nil
            }
            return AlertCapsuleView(glyph: ScheduleView.glyph(bell.kind), words: bell.words(formatter, today: today), action: action)
        }
    }
}

/// The route said once above its cards (board 53's option A): Schedule's marks on one line, the origin ring, its name,
/// three dots, the accent pin, the destination, and the 20 pt line tile at the right. Too long, the origin shortens; the
/// destination never does. No tap.
struct AlertRouteLabel: View {
    let from: String
    let to: String
    let line: Line?

    var body: some View {
        HStack(spacing: TTSpace.s3) {
            HStack(spacing: 0) {
                Circle()
                    .strokeBorder(TTColor.inkSecondary, lineWidth: 2.5)
                    .frame(width: 12, height: 12)
                    .padding(.trailing, 6)
                Text(verbatim: from)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(TTColor.inkTertiary).frame(width: 3, height: 3)
                    }
                }
                .padding(.leading, TTSpace.s2)
                .padding(.trailing, 6)
                RoutePin()
                    .fill(TTColor.accent, style: FillStyle(eoFill: true))
                    .frame(width: 18, height: 18)
                    .padding(.trailing, 3)
                Text(verbatim: to)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 0)
            if let line {
                LineTile(line: line, kind: .widgetSmall)
            }
        }
        .font(TTFont.subhead.weight(.semibold))
        .tracking(-0.2)
        .foregroundStyle(TTColor.ink)
        .frame(height: 20)
        .padding(.leading, TTSpace.s4)
        .padding(.trailing, 10)
        .padding(.top, 6)
        .padding(.bottom, -2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: String(format: String(localized: "schedule.route_title"), from, to)))
        .accessibilityAddTraits(.isHeader)
    }
}

/// The days row (board 53, option A): seven 8 pt dots, Monday first, 4 pt apart and 8 pt before Saturday, lit in the
/// accent (a one-day alert's own day a ring), then the words in 15 pt. Grey when the alert is off or its train changed.
struct AlertDaysRow: View {
    let dots: [AlertsViewModel.Dot]
    let words: String?
    let greys: Bool

    /// Room kept free at the right for the pill over it.
    private static let pillRoom: CGFloat = 132

    var body: some View {
        HStack(spacing: TTSpace.s2) {
            HStack(spacing: 4) {
                ForEach(Array(dots.enumerated()), id: \.offset) { index, dot in
                    dotView(dot)
                        .padding(.leading, index == 5 ? 4 : 0)
                }
            }
            if let words {
                Text(verbatim: words)
                    .font(TTFont.subhead)
                    .tracking(-0.2)
                    .foregroundStyle(greys ? TTColor.inkSecondary : TTColor.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.trailing, Self.pillRoom)
        .animation(TTMotion.fade, value: greys)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: words ?? ""))
    }

    @ViewBuilder private func dotView(_ dot: AlertsViewModel.Dot) -> some View {
        let lit = greys ? TTColor.inkTertiary : TTColor.accent
        switch dot {
        case .off: Circle().fill(TTColor.inkTertiary.opacity(0.3)).frame(width: 8, height: 8)
        case .on: Circle().fill(lit).frame(width: 8, height: 8)
        case .ring: Circle().strokeBorder(lit, lineWidth: 1.5).frame(width: 8, height: 8)
        }
    }
}

/// The fourth row's 32 pt pill (44 pt target): "See trains" with the Schedule tab's glyph, accent on the neutral fill; or
/// filled, "Pick a new train".
struct AlertCardPill: View {
    let title: LocalizedStringKey
    let systemImage: String?
    let isFilled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(TTFont.subhead.weight(.semibold))
                    .tracking(-0.2)
                    .lineLimit(1)
            }
            .foregroundStyle(isFilled ? TTColor.onAccent : TTColor.accent)
            .padding(.leading, isFilled ? 14 : 10)
            .padding(.trailing, isFilled ? 14 : 12)
            .frame(height: 32)
            .background(isFilled ? TTColor.accent : TTColor.surfaceRaised, in: Capsule())
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        // The 44 pt target overhangs the 32 pt row by 6 pt each way.
        .padding(.vertical, -6)
    }
}

/// A card from the alert alone, Schedule's paddings and rows: the alert's time and bell, then rows 2 and 3 as skeleton
/// bars while there is no timetable, "No train today" with no train on its days this week, or, for a usual train that
/// changed, the time struck in grey, no bell and amber "Time changed" in row 2; then the days row.
private struct AlertPlainCard: View {
    let item: AlertsViewModel.Item
    let bell: BellFace?
    let shakes: Int
    let onBell: () -> Void
    let onOpen: () -> Void
    let accessory: AnyView

    private var changed: Bool {
        if case .changed = item.body { true } else { false }
    }

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text(verbatim: item.time)
                        .font(TTFont.timeRow)
                        .monospacedDigit()
                        .strikethrough(changed)
                        .foregroundStyle(changed || !item.isOn ? TTColor.inkTertiary : TTColor.ink)
                        .lineLimit(1)
                    Spacer(minLength: 46)
                }
                .frame(height: 38)
                switch item.body {
                case .changed:
                    status(dot: TTColor.delayInk, ring: false, words: "alerts.time_changed", ink: TTColor.delayInk)
                        .frame(height: 24)
                case .noTrain:
                    status(dot: TTColor.inkSecondary, ring: true, words: "alerts.no_train", ink: TTColor.inkSecondary)
                        .frame(height: 20)
                    Color.clear.frame(height: 24)
                default:
                    bar(width: 150).frame(height: 20, alignment: .leading)
                    bar(width: 110).frame(height: 24, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: TTSpace.s2) {
                    Rectangle().fill(TTColor.hairline).frame(height: 1)
                    AlertDaysRow(dots: item.dots, words: item.words, greys: item.greysDays)
                        .frame(height: 32)
                }
                .padding(.top, 6)
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 10, trailing: 10))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .overlay(alignment: .topTrailing) {
            if let bell {
                AlertBellButton(
                    face: bell,
                    shakes: shakes,
                    label: Text(verbatim: String(
                        format: bell == .on ? String(localized: "alert.bell.label_on") : String(localized: "alert.bell.label"),
                        item.time
                    )),
                    glyph: 26,
                    target: 48,
                    action: onBell
                )
                .padding(.top, 14 + 19 - 24)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            accessory
                .padding(.trailing, 10)
                .padding(.bottom, 10)
        }
    }

    private func status(dot: Color, ring: Bool, words: LocalizedStringKey, ink: Color) -> some View {
        HStack(spacing: TTSpace.s2) {
            Group {
                if ring {
                    Circle().strokeBorder(dot, lineWidth: 2)
                } else {
                    Circle().fill(dot)
                }
            }
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
            Text(words)
                .lineLimit(1)
        }
        .font(TTFont.badgeLarge)
        .foregroundStyle(ink)
    }

    private func bar(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: TTRadius.sm).fill(TTColor.surfaceRaised).frame(width: width, height: 12)
    }
}

/// What the tab's capsule stage shows: its own capsule or the bell model's.
private enum TabCapsule: Identifiable, Equatable {
    case own(AlertsViewModel.Capsule)
    case bell(AlertBellModel.Capsule)

    var id: String {
        switch self {
        case .own(let capsule): "own.\(capsule.id)"
        case .bell(let capsule): "bell.\(capsule.id)"
        }
    }
}

private extension AlertsViewModel.Capsule {
    var glyph: CapsuleGlyph {
        switch kind {
        case .removed: .bellOff
        case .failed: .failed
        case .notificationsOn: .confirmed
        }
    }

    /// "Alert removed", "Couldn’t turn alert on" (off, change days), "Notifications are on".
    var words: String {
        switch kind {
        case .removed: String(localized: "capsule.removed")
        case .failed(.turnOn): String(localized: "capsule.failed_on")
        case .failed(.changeDays): String(localized: "capsule.failed_days")
        case .failed(.turnOff): String(localized: "capsule.failed_off")
        case .notificationsOn: String(localized: "alerts.notifications_on")
        }
    }
}
