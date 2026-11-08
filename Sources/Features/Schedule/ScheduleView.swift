import SwiftUI

/// Schedule tab (TT-112): the route card with the line under it (D48), 7-day strip and freshness row with the Now button,
/// the watched-trip strip once a watched train has left (TT-144), then the to-scale timeline with its rail and cards
/// (TT-113).
struct ScheduleView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    let viewModel: ScheduleViewModel
    /// Tap the route card: the route sheet with Recent (D48).
    let onEditRoute: () -> Void
    /// Tap a card: Trip details (TT-118).
    var onOpenTrip: (TripKey) -> Void = { _ in }
    /// "Line notice" in the freshness row: the notice sheet (TT-132).
    var onOpenLineNotice: () -> Void = {}
    /// The one-tap bells and their toast (TT-141); nil shows outlined bells that do nothing.
    var bells: AlertBellModel?
    /// The alert setup sheet (TT-142): a bell tapped before notifications are allowed, or the toast's Repeat.
    var onAlertSetup: (AlertSetupRequest) -> Void = { _ in }

    /// The one formatter (D17), following the Time format setting (TT-105).
    @Environment(\.timeFormatter) private var formatter
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                routeHeader
                    .padding(.horizontal, TTSpace.s5)
                    .padding(.bottom, TTSpace.s3)
                dayStrip
                    .padding(.bottom, TTSpace.s2)
                freshnessRow
                    .padding(.horizontal, TTSpace.s5)
                if let strip = viewModel.watchedStrip(formatter) {
                    WatchedTripStripView(strip: strip, onOpen: { onOpenTrip(strip.id) }) {
                        withAnimation(.easeOut(duration: 0.2)) { viewModel.dismissWatchedStrip(strip.id) }
                    }
                    .id(strip.id)
                    .transition(.opacity)
                    .padding(.horizontal, TTSpace.s5)
                    .padding(.top, TTSpace.s3 - TTSpace.s1 / 2)
                }
            }
            .padding(.top, TTSpace.s3)
            timeline
                .padding(.top, TTSpace.s3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TTColor.canvas)
        .overlay(alignment: .bottom) { alertToast }
        .animation(.easeOut(duration: 0.25), value: bells?.toast)
        .animation(.easeOut(duration: 0.25), value: bells?.showsHint)
        // A light haptic when an alert turns on (TT-141).
        .sensoryFeedback(.impact(weight: .light), trigger: bells?.enabledCount ?? 0)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.loadIfNeeded() }
        .task { await viewModel.runClock() }
        // Live status every 30 s, and at once on coming back to the foreground (TT-131).
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await viewModel.pollLiveStatus()
        }
    }

    // MARK: Route header

    /// The route card, origin over destination (D48); tapping it opens the route sheet. The line sits under it.
    private var routeHeader: some View {
        VStack(alignment: .leading, spacing: Self.lineRowGap) {
            RouteCard(
                from: viewModel.route?.from.name,
                to: viewModel.route?.to.name,
                tap: .card(label: viewModel.routeTitle ?? "", id: "schedule.route", action: onEditRoute),
                swapID: "schedule.swap"
            ) {
                Task { await viewModel.swap() }
            }
            if let line = viewModel.route?.line {
                HStack(spacing: TTSpace.s2) {
                    Circle()
                        .fill(line.colorHex.flatMap { Color(lineHex: $0, on: colorScheme) } ?? TTColor.inkSecondary)
                        .frame(width: Self.lineDot, height: Self.lineDot)
                    Text(line.name)
                        .font(TTFont.subhead)
                        .foregroundStyle(TTColor.inkSecondary)
                }
                .frame(height: Self.lineRowHeight)
                .padding(.leading, TTSpace.s1)
            }
        }
    }

    /// The canvas's line dot.
    private static let lineDot: CGFloat = 10
    /// The canvas's line row under the card: 6 pt below it, 24 pt tall.
    private static let lineRowGap: CGFloat = 6
    private static let lineRowHeight: CGFloat = 24

    // MARK: Day strip

    /// Seven cells fill the width between the margins, Today first; the strip scrolls sideways for later dates.
    private var dayStrip: some View {
        GeometryReader { geometry in
            let visible = CGFloat(7)
            let width = (geometry.size.width - 2 * TTSpace.s5 - (visible - 1) * TTSpace.s1) / visible
            ScrollViewReader { strip in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TTSpace.s1) {
                        ForEach(Array(viewModel.days.enumerated()), id: \.offset) { index, day in
                            DayCell(
                                weekday: index == 0 ? String(localized: "button.today") : day.weekdayShort,
                                day: "\(day.day)",
                                isSelected: day == viewModel.selectedDay
                            ) {
                                Task { await viewModel.select(day) }
                            }
                            .frame(width: width)
                            .id(index)
                            .accessibilityIdentifier("schedule.day.\(index)")
                        }
                    }
                    // Room for the cell shadow inside the clipped strip.
                    .padding(.vertical, Self.shadowRoom)
                }
                .padding(.horizontal, TTSpace.s5)
                // Now/Today resets the strip to Today too, even when it was scrolled to a later date; "Show Monday"
                // brings its day into view.
                .onChange(of: viewModel.selectedDay) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        if viewModel.isToday {
                            strip.scrollTo(0, anchor: .leading)
                        } else if let index = viewModel.days.firstIndex(of: viewModel.selectedDay) {
                            strip.scrollTo(index)
                        }
                    }
                }
            }
        }
        .frame(height: TTSize.targetMin + 2 + 2 * Self.shadowRoom)
        .padding(.vertical, -Self.shadowRoom)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }

    private static let shadowRoom: CGFloat = 2

    // MARK: Freshness row

    private var freshnessRow: some View {
        HStack(spacing: TTSpace.s2) {
            if let mode = viewModel.freshnessMode(formatter) {
                FreshnessLine(mode: mode)
            }
            if !viewModel.lineNotices.isEmpty {
                lineNoticeLink
            }
            Spacer(minLength: 0)
            Button {
                Task { await viewModel.backToNow() }
            } label: {
                HStack(spacing: TTSpace.s1) {
                    Image(systemName: viewModel.isToday ? "clock" : "calendar")
                        .font(.system(size: TTSize.iconSM, weight: .semibold))
                    Text(viewModel.nowButtonTitle)
                        .font(TTFont.headline)
                }
                .foregroundStyle(viewModel.isAtNow ? TTColor.inkTertiary : TTColor.accent)
                .padding(.leading, TTSpace.s2)
                .frame(minHeight: TTSize.targetMin)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            // A 44 pt target that takes only the text's height in the row, as on the canvas.
            .padding(.vertical, -TTSpace.s3)
            .accessibilityLabel(Text(viewModel.nowButtonAccessibilityLabel))
            .accessibilityIdentifier("schedule.now")
        }
    }

    /// "· Line notice" in amber after the freshness text, as in `schedule-delayed.png` (canvas `.notice-link`).
    @ViewBuilder
    private var lineNoticeLink: some View {
        // A separator glyph, not copy.
        Text(verbatim: "·")
            .font(TTFont.footnote)
            .foregroundStyle(TTColor.inkSecondary)
            .accessibilityHidden(true)
        Button(action: onOpenLineNotice) {
            HStack(spacing: TTSpace.s1) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: TTSize.iconSM, weight: .semibold))
                Text("schedule.line_notice")
                    .font(TTFont.footnote.weight(.semibold))
            }
            .foregroundStyle(TTColor.delayInk)
            .frame(minHeight: TTSize.targetMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        // A 44 pt target that takes only the text's height in the row, as the Now button does.
        .padding(.vertical, -TTSpace.s3)
        .fixedSize()
        .accessibilityIdentifier("schedule.lineNotice")
    }

    // MARK: Timeline

    private enum TimelineAnchor: Hashable {
        case top, now
    }

    /// The to-scale timeline (TT-111 layout, TT-113 drawing), its loading skeleton, or an empty state card (TT-115).
    /// One scroll view holds them all, so a scroll request still lands when the content changes with it.
    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    switch viewModel.content {
                    case .loading:
                        ScheduleLoadingTimeline(now: viewModel.now, formatter: formatter)
                    case .timeline:
                        ZStack(alignment: .top) {
                            ScheduleTimeline(
                                viewModel: viewModel, formatter: formatter, onOpen: onOpenTrip, bell: bell(for:), onBell: tapBell(_:)
                            )
                            Color.clear
                                .frame(height: 1)
                                .id(TimelineAnchor.top)
                            Color.clear
                                .frame(height: 1)
                                .id(TimelineAnchor.now)
                                .padding(.top, viewModel.layout.initialScrollOffset)
                        }
                    case .noTrains(let title, let message, let showDay):
                        noTrains(title: title, message: message, showDay: showDay)
                    case .noConnection:
                        noConnection
                    }
                }
                .onGeometryChange(for: CGFloat.self) { geometry in
                    -geometry.frame(in: .scrollView).minY
                } action: { offset in
                    viewModel.scrollOffset = offset
                }
            }
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height
            } action: { height in
                viewModel.viewportHeight = height
            }
            .refreshable { await viewModel.refresh() }
            .onChange(of: viewModel.scrollRequest) { previous, _ in
                let anchor: TimelineAnchor = viewModel.isToday ? .now : .top
                if previous == 0 {
                    proxy.scrollTo(anchor, anchor: .top)
                } else {
                    withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(anchor, anchor: .top) }
                }
            }
            .accessibilityIdentifier("schedule.timeline")
        }
    }

    // MARK: Alerts

    private func train(_ id: TripKey) -> (trip: Trip, route: Route)? {
        guard let route = viewModel.route, let departure = viewModel.departures.first(where: { $0.id == id }) else { return nil }
        return (departure.trip, route)
    }

    private func bell(for id: TripKey) -> AlertBellModel.Bell {
        guard let bells, let train = train(id) else { return .off }
        return bells.bell(for: train.trip, on: train.route)
    }

    private func tapBell(_ id: TripKey) {
        guard let train = train(id) else { return }
        tapBell(train.trip, on: train.route)
    }

    private func tapBell(_ trip: Trip, on route: Route) {
        guard let bells else { return }
        Task {
            if let request = await bells.tap(trip, on: route) { onAlertSetup(request) }
        }
    }

    /// The toast above the tab bar (`schedule-delayed.png`): Setting up, then "Alert on for the 7:32 AM train" with Repeat,
    /// "Alert off", or "Could not save" with Try again; else "Tap the bell on a train" after the Alerts tab's "Add alert".
    @ViewBuilder private var alertToast: some View {
        if let bells, bells.toast == nil, bells.showsHint {
            Toast(message: String(localized: "alerts.add_hint"), systemImage: "bell")
                .padding(.horizontal, TTSpace.s5)
                .padding(.bottom, TTSpace.s2)
        } else if let bells, let toast = bells.toast {
            Group {
                switch toast.kind {
                case .settingUp:
                    Toast(message: String(localized: "alert.state.setting_up"), systemImage: "clock", tint: TTColor.inkSecondary)
                case .on:
                    Toast(
                        message: String(format: String(localized: "alert.toast_on"), formatter.time(toast.trip.scheduledDeparture)),
                        systemImage: "bell.fill",
                        actionTitle: "alert.repeat"
                    ) {
                        if let request = bells.repeatRequest() { onAlertSetup(request) }
                    }
                case .off:
                    Toast(message: String(localized: "alert.toast_off"), systemImage: "bell.slash", tint: TTColor.inkSecondary)
                case .couldNotSave:
                    Toast(
                        message: String(localized: "alert.could_not_save"),
                        systemImage: "xmark.circle.fill",
                        tint: TTColor.cancelInk,
                        actionTitle: "button.try_again"
                    ) {
                        tapBell(toast.trip, on: toast.route)
                    }
                }
            }
            .id(toast.id)
            .padding(.horizontal, TTSpace.s5)
            .padding(.bottom, TTSpace.s2)
        }
    }

    // MARK: Empty states

    /// "No direct trains on Sunday" with "Show Monday", and the trip planner footnote (`schedule-no-trains.png`).
    private func noTrains(title: String, message: String, showDay: String?) -> some View {
        VStack(spacing: TTSpace.s3) {
            EmptyStateCard(
                systemImage: "calendar",
                title: Text(verbatim: title),
                message: Text(verbatim: message),
                actionTitle: showDay.map { Text(verbatim: $0) }
            ) {
                Task { await viewModel.showNextDayWithTrains() }
            }
            Text("schedule.no_trains.footnote")
                .font(TTFont.footnote)
                .foregroundStyle(TTColor.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TTSpace.s3)
        }
        .padding(.horizontal, TTSpace.s5)
        .padding(.top, TTSpace.s3)
    }

    /// "No direct connection" with "Open GO trip planner" (`components.png`).
    private var noConnection: some View {
        EmptyStateCard(
            systemImage: "exclamationmark.triangle",
            title: "schedule.no_connection.title",
            message: "schedule.no_connection.body",
            actionTitle: "schedule.no_connection.action"
        ) {
            openURL(ScheduleViewModel.tripPlannerURL)
        }
        .padding(.horizontal, TTSpace.s5)
        .padding(.top, TTSpace.s3)
    }
}

#Preview {
    NavigationStack {
        ScheduleView(viewModel: .fixtures(), onEditRoute: {})
    }
}
