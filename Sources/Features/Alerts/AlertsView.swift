import SwiftUI

/// The Alerts tab as one list (TT-193, D78; frames *Alerts-Tab*, *-Open*, *-States*, *-Muted*, *-Empty* on the canvas): the
/// title and one card of rows, each the time, one line and a switch, in time order, with "Alerts start 1 hour before each
/// train leaves." under it. A tap opens a row in place to its day tiles and "Remove alert" (one row at a time); a Time
/// changed row offers "Pick a new train". Recent lists up to three notifications. With no alert, "Next trains" offers the
/// route's next three trains with their real bells. With notifications off the D58 card tops the list, the switches are
/// disabled (a tap nudges the card's button) and the line under the list is hidden. "Alert removed · Undo", "Couldn't … ·
/// Try again" and "Notifications are on" show as the glass capsule above the tab bar (D71).
struct AlertsView: View {
    let viewModel: AlertsViewModel
    /// The bells of the empty tab's next trains and their capsule (TT-191); nil shows none.
    var bells: AlertBellModel?
    /// "See trains", with no route or no more trains today: the Schedule tab.
    var onSeeTrains: () -> Void = {}
    /// "Pick a new train" on a Time changed row: Schedule on that route, with "Tap the bell of your new train".
    var onPickNewTrain: (AlertRule) -> Void = { _ in }
    /// A recent notification: Trip details for that trip and service date.
    var onOpenUpdate: (NotificationLink) -> Void = { _ in }

    @Environment(\.timeFormatter) private var formatter
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counts the times the card's bell should shake: once as the card appears.
    @State private var shakes = 0

    /// The Motion board's Alerts row opens: spring(0.42, 1.0) open, spring(0.28, 1.0) close; a row removed shuts on the
    /// close spring.
    private static let open = Animation.spring(response: 0.42, dampingFraction: 1)
    private static let shut = Animation.spring(response: 0.28, dampingFraction: 1)

    var body: some View {
        let rows = viewModel.rows(formatter)
        let recent = viewModel.recentRows(formatter)
        let muted = viewModel.warnsNotificationsOff
        ScrollView {
            VStack(alignment: .leading, spacing: TTSpace.s2) {
                Text("tab.alerts")
                    .font(TTFont.largeTitle)
                    .foregroundStyle(TTColor.ink)
                    .accessibilityAddTraits(.isHeader)
                    .frame(height: 48, alignment: .bottomLeading)
                    .padding(.bottom, TTSpace.s2)
                if muted {
                    notificationsOffCard
                }
                if rows.isEmpty {
                    emptyState
                        .transition(.opacity)
                } else {
                    list(rows, muted: muted)
                        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.scale(scale: 0.96).combined(with: .opacity))
                    if !muted {
                        note("alerts.start_note")
                    }
                }
                if !recent.isEmpty {
                    label("alerts.recent")
                    recentCard(recent)
                }
            }
            .padding(.horizontal, TTSpace.s5)
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, alignment: .leading)
            // A tap outside a row closes the open one.
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(Self.shut) { viewModel.closeRow() } }
        }
        .background(TTColor.canvas)
        .overlay(alignment: .bottom) { capsuleLayer }
        // The first alert set from the empty tab: its bell pops, and 300 ms later the list takes the suggestions' place.
        .animation(reduceMotion ? TTMotion.fade : TTMotion.cascade.delay(0.3), value: rows.isEmpty)
        // The card folds away on a spring when notifications are allowed again.
        .animation(.spring(response: 0.46, dampingFraction: 0.82), value: muted)
        .sensoryFeedback(.selection, trigger: viewModel.dayOnCount)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alerts.root")
    }

    // MARK: Notifications off (TT-169, D58)

    /// The Notifications page's off card, saying it once: "3 alerts can’t reach you." Its button nudges when a disabled
    /// switch is tapped.
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

    // MARK: The list

    private func list(_ rows: [AlertsViewModel.Row], muted: Bool) -> some View {
        SettingsCard {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                AlertRowView(
                    row: row,
                    isOpen: viewModel.openID == row.id,
                    muted: muted,
                    lastDayTaps: viewModel.lastDayTaps[row.id] ?? 0,
                    onOpen: {
                        let opening = viewModel.openID != row.id
                        withAnimation(opening ? Self.open : Self.shut) { viewModel.toggleOpen(row.id) }
                    },
                    onSwitch: { _ = viewModel.setOn($0, for: row.id) },
                    onNudge: { viewModel.nudge() },
                    onDay: { _ = viewModel.toggleDay($0, for: row.id) },
                    onRemove: { withAnimation(Self.shut) { _ = viewModel.remove(row.id) } },
                    onPickNewTrain: {
                        guard let rule = viewModel.rule(row.id) else { return }
                        withAnimation(Self.shut) { viewModel.closeRow() }
                        onPickNewTrain(rule)
                    }
                )
                .overlay(alignment: .top) {
                    if index > 0 { hairline }
                }
                .transition(.opacity)
            }
        }
        .animation(Self.shut, value: rows.map(\.id))
    }

    /// The line under the list and the lead of the empty tab, in footnote.
    private func note(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(TTFont.footnote)
            .foregroundStyle(TTColor.inkSecondary)
            .padding(.horizontal, TTSpace.s4)
            .padding(.top, 2)
    }

    private func label(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(TTFont.footnote)
            .foregroundStyle(TTColor.inkSecondary)
            .accessibilityAddTraits(.isHeader)
            .padding(.leading, TTSpace.s4)
            .padding(.top, TTSpace.s2 + 2)
    }

    private var hairline: some View {
        Rectangle().fill(TTColor.hairline).frame(height: 1).padding(.horizontal, TTSpace.s4)
    }

    // MARK: Empty

    /// "Tap a bell to hear if a train is delayed or cancelled.", then the route's next three trains, each with its bell;
    /// with no route or no more trains today, one row "See trains".
    private var emptyState: some View {
        let trains = viewModel.nextTrainRows(formatter)
        return VStack(alignment: .leading, spacing: TTSpace.s2) {
            Text("alerts.empty.lead")
                .font(TTFont.subhead)
                .foregroundStyle(TTColor.inkSecondary)
                .frame(maxWidth: 300, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, TTSpace.s4)
                .padding(.top, TTSpace.s1)
            label("alerts.next_trains")
            SettingsCard {
                if trains.isEmpty {
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
                } else {
                    ForEach(Array(trains.enumerated()), id: \.element.id) { index, train in
                        nextTrainRow(train)
                            .overlay(alignment: .top) {
                                if index > 0 { hairline }
                            }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alerts.empty")
    }

    /// The canvas's `.arow.sug`: a size smaller than an alert, with the card's real bell.
    private func nextTrainRow(_ train: AlertsViewModel.NextTrain) -> some View {
        let face = bells?.bell(for: train.trip, on: train.route) ?? .off
        let label = face == .on ? String(localized: "alert.bell.label_on") : String(localized: "alert.bell.label")
        return HStack(spacing: TTSpace.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: train.time)
                    .font(TTFont.headline)
                    .tracking(-0.4)
                    .monospacedDigit()
                    .foregroundStyle(TTColor.ink)
                Text(verbatim: train.line)
                    .font(TTFont.footnote)
                    .monospacedDigit()
                    .foregroundStyle(TTColor.inkSecondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, alignment: .leading)
            AlertBellButton(
                face: face,
                shakes: bells?.shakes(for: train.trip) ?? 0,
                label: Text(verbatim: String(format: label, train.time)),
                glyph: 26,
                target: 48
            ) {
                guard let bells else { return }
                Task { await bells.tap(train.trip, on: train.route) }
            }
            .padding(.trailing, -10)
            .accessibilityIdentifier("alerts.next.bell.\(train.trip.key.tripId)")
        }
        .padding(.horizontal, TTSpace.s4)
        .padding(.vertical, 11)
        .frame(minHeight: 64)
    }

    // MARK: Recent

    /// Up to three one-line rows: a dot, "7:32 AM train delayed 9 min", when it came; a tap opens Trip details.
    private func recentCard(_ rows: [AlertsViewModel.RecentRow]) -> some View {
        SettingsCard {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                Button { if let link = row.link { onOpenUpdate(link) } } label: {
                    HStack(spacing: 10) {
                        Circle().fill(row.kind.dot).frame(width: 8, height: 8)
                        Text(verbatim: row.title)
                            .font(TTFont.subhead.weight(.semibold))
                            .tracking(-0.2)
                            .monospacedDigit()
                            .foregroundStyle(TTColor.ink)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: row.when)
                            .font(TTFont.footnote)
                            .monospacedDigit()
                            .foregroundStyle(TTColor.inkSecondary)
                    }
                    .padding(.horizontal, TTSpace.s4)
                    .frame(height: TTSize.targetMin)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(row.link == nil)
                .accessibilityIdentifier("alerts.update.\(row.id)")
                .overlay(alignment: .top) {
                    if index > 0 { hairline }
                }
            }
        }
    }

    // MARK: Capsule (D71)

    /// The tab's own capsule, or the one a next train's bell raised.
    private var shownCapsule: TabCapsule? {
        if let own = viewModel.capsule { return .own(own) }
        guard let bell = bells?.capsule, !bell.isPanelOpen else { return nil }
        switch bell.kind {
        case .on, .failed, .notificationsOff, .notificationsOn: return .bell(bell)
        case .off, .newTrain: return nil
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
            // On the Alerts tab the new alert is already a row to open: no Repeat.
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

/// One alert row (the canvas's `.arow`): the time in 22 pt, one line and the switch; open, the day tiles and "Remove
/// alert", or for a Time changed row "Pick a new train" and "Remove alert".
private struct AlertRowView: View {
    let row: AlertsViewModel.Row
    let isOpen: Bool
    let muted: Bool
    let lastDayTaps: Int
    let onOpen: () -> Void
    let onSwitch: (Bool) -> Void
    let onNudge: () -> Void
    let onDay: (Int) -> Void
    let onRemove: () -> Void
    let onPickNewTrain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: TTSpace.s3) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.time)
                            .font(TTFont.route)
                            .tracking(-0.3)
                            .monospacedDigit()
                            .foregroundStyle(row.isOn || row.note == .timeChanged ? TTColor.ink : TTColor.inkTertiary)
                        line
                    }
                    .padding(.top, 13)
                    .padding(.bottom, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .animation(TTMotion.fade, value: row.isOn)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("alerts.rule.open")
                toggle
            }
            .padding(.horizontal, TTSpace.s4)
            .frame(minHeight: 72)
            if isOpen {
                OpenRowParts(row: row, lastDayTaps: lastDayTaps, onDay: onDay, onRemove: onRemove, onPickNewTrain: onPickNewTrain)
                    .transition(.opacity)
            }
        }
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(row.testID)
    }

    /// "Oakville to Union · Mon to Fri"; a Time changed row's words after the route in amber with a dot.
    @ViewBuilder private var line: some View {
        let ink = row.isOn ? TTColor.inkSecondary : TTColor.inkTertiary
        Group {
            if row.note == .timeChanged, let split = row.line.range(of: " · ", options: .backwards) {
                HStack(spacing: 6) {
                    Text(verbatim: String(row.line[..<split.lowerBound]) + " ·").foregroundStyle(TTColor.inkSecondary)
                    Circle().fill(TTColor.delayInk).frame(width: 8, height: 8)
                    Text(verbatim: String(row.line[split.upperBound...]))
                        .fontWeight(.semibold)
                        .foregroundStyle(TTColor.delayInk)
                }
            } else {
                Text(verbatim: row.line).foregroundStyle(ink)
            }
        }
        .font(TTFont.footnote)
        .tracking(-0.1)
        .lineLimit(1)
    }

    /// The system switch. A Time changed row's stays off and takes no tap; while notifications are off it is disabled at
    /// 40 % and a tap nudges the card's button.
    private var toggle: some View {
        Toggle(isOn: Binding(get: { row.isOn }, set: { onSwitch($0) })) {
            Text(verbatim: row.time)
        }
        .labelsHidden()
        .tint(muted ? TTColor.inkSecondary : TTColor.accent)
        .disabled(muted)
        .opacity(muted ? 0.4 : 1)
        .allowsHitTesting(!muted && !row.isSaving && row.note != .timeChanged)
        .overlay {
            if muted {
                Color.clear.contentShape(Rectangle()).onTapGesture(perform: onNudge)
            }
        }
        .accessibilityIdentifier("alerts.rule.switch")
    }
}

/// What an opened row shows: "Repeat on" (a one-day alert), the seven day tiles and "Remove alert"; for a Time changed row,
/// "Pick a new train" and "Remove alert". The tiles arrive as in the day panel and Remove alert rises 8 pt 140 ms later.
private struct OpenRowParts: View {
    let row: AlertsViewModel.Row
    let lastDayTaps: Int
    let onDay: (Int) -> Void
    let onRemove: () -> Void
    let onPickNewTrain: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// At rest in the unit test host, so snapshots draw the tiles settled.
    @State private var arrived = UnitTestHost.isRunning

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if row.note == .timeChanged {
                action("alerts.pick_new_train", ink: TTColor.ink, chevron: true, action: onPickNewTrain)
                    .accessibilityIdentifier("alerts.pickNewTrain")
            } else {
                if row.isOneDay {
                    Text("alert.repeat_on")
                        .font(TTFont.footnote)
                        .tracking(-0.1)
                        .foregroundStyle(TTColor.inkSecondary)
                        .padding(.horizontal, TTSpace.s4)
                        .padding(.bottom, TTSpace.s2)
                }
                HStack(spacing: TTSpace.s1) {
                    ForEach(Array(AlertDays.week.enumerated()), id: \.element) { index, day in
                        DayTile(day: day, isOn: row.days.contains(day), action: { onDay(day) }, offFill: TTColor.surfaceRaised)
                            .keyframeAnimator(initialValue: 1.0, trigger: row.days == [day] ? lastDayTaps : 0) { content, scale in
                                content.scaleEffect(scale)
                            } keyframes: { _ in
                                MoveKeyframe(0.92)
                                SpringKeyframe(1.0, duration: 0.35, spring: TTMotion.tilePressCurve.spring)
                            }
                            .modifier(TileArrival(isOpen: arrived, order: index, reduceMotion: reduceMotion))
                    }
                }
                .padding(.horizontal, TTSpace.s4)
            }
            action("alerts.remove", ink: TTColor.cancelInk, chevron: false, action: onRemove)
                .padding(.bottom, TTSpace.s1)
                .accessibilityIdentifier("alerts.remove")
                .animation(reduceMotion ? TTMotion.fade : TTMotion.settleCurve.animation.delay(0.14)) {
                    $0.offset(y: arrived || reduceMotion ? 0 : 8).opacity(arrived ? 1 : 0)
                }
        }
        .onAppear { arrived = true }
    }

    /// The canvas's `.act`: 44 pt, 15 pt semibold, the words leading.
    private func action(_ key: LocalizedStringKey, ink: Color, chevron: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(key).font(TTFont.subhead.weight(.semibold)).tracking(-0.2).foregroundStyle(ink)
                Spacer(minLength: TTSpace.s3)
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(TTFont.footnote.weight(.semibold))
                        .foregroundStyle(TTColor.inkTertiary)
                }
            }
            .padding(.horizontal, TTSpace.s4)
            .frame(height: TTSize.targetMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, TTSpace.s1)
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

private extension AlertUpdate.Kind {
    /// Recent's dot: amber for a delay, red for a cancellation or skipped stop, green back on time.
    var dot: Color {
        switch self {
        case .delay: TTColor.delayInk
        case .recovery: TTColor.ontimeInk
        case .cancelled, .skipped: TTColor.cancelInk
        }
    }
}
