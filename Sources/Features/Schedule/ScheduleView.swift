import SwiftUI

/// Schedule tab (TT-112, D49): the line (code tile, name and a Notice chip) above the route card (D48), the day strip
/// carousel, a status row only while loading, offline or stale, the watched-trip strip once a watched train has left
/// (TT-144), then the to-scale timeline with its rail and cards (TT-113). The header is a top inset over one full-height
/// scroll view, so the timeline scrolls under the glass tab bar at the bottom (D49). There is no Now button: tapping the
/// Schedule tab again scrolls back to Now.
struct ScheduleView: View {
    @Environment(\.scenePhase) private var scenePhase
    let viewModel: ScheduleViewModel
    /// Tap the route card: the route sheet with Recent (D48).
    let onEditRoute: () -> Void
    /// Tap a card: Trip details (TT-118).
    var onOpenTrip: (TripKey) -> Void = { _ in }
    /// The Notice chip: the notice sheet (TT-132).
    var onOpenLineNotice: () -> Void = {}
    /// The one-tap bells and their toast (TT-141); nil shows outlined bells that do nothing.
    var bells: AlertBellModel?
    /// The alert setup sheet (TT-142): a bell tapped before notifications are allowed, or the toast's Repeat.
    var onAlertSetup: (AlertSetupRequest) -> Void = { _ in }

    /// The one formatter (D17), following the Time format setting (TT-105).
    @Environment(\.timeFormatter) private var formatter
    @Environment(\.openURL) private var openURL
    /// The strip's leftmost tile, as its id (0 is Today), for scrolling it to a tile that is out of view. The strip opens at
    /// Today, after the past week.
    @State private var stripPosition: Int? = 0
    /// The rider has dragged the timeline since the last scroll request, so the later scrolls to Now stay out of the way.
    @State private var riderScrolled = false
    /// The latest ask to scroll the timeline, carried out by `ScrollOffsetSetter`.
    @State private var scrollOrder = ScrollOrder()

    var body: some View {
        timeline
            .safeAreaInset(edge: .top, spacing: 0) { header }
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

    // MARK: Header

    /// Everything above the timeline, on a canvas background that also covers the status bar, with a 16 pt fade under it.
    private var header: some View {
        VStack(alignment: .leading, spacing: TTSpace.s3) {
            routeHeader
                .padding(.horizontal, TTSpace.s5)
            dayStrip
            if let mode = viewModel.statusRowMode(formatter) {
                FreshnessLine(mode: mode)
                    .padding(.horizontal, TTSpace.s5)
                    .padding(.top, -TTSpace.s1)
            }
            if let strip = viewModel.watchedStrip(formatter) {
                WatchedTripStripView(strip: strip, onOpen: { onOpenTrip(strip.id) }) {
                    withAnimation(.easeOut(duration: 0.2)) { viewModel.dismissWatchedStrip(strip.id) }
                }
                .id(strip.id)
                .transition(.opacity)
                .padding(.horizontal, TTSpace.s5)
            }
        }
        .padding(.top, TTSpace.s3)
        .padding(.bottom, TTSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TTColor.canvas.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [TTColor.canvas, TTColor.canvas.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.edgeFade)
                .offset(y: Self.edgeFade)
                .allowsHitTesting(false)
        }
    }

    /// The canvas's `.edge-top`.
    private static let edgeFade: CGFloat = 16

    /// The line first, then the route card (D49, D48); tapping the card opens the route sheet.
    private var routeHeader: some View {
        VStack(alignment: .leading, spacing: Self.lineRowGap) {
            lineRow
            RouteCard(
                from: viewModel.route?.from.name,
                to: viewModel.route?.to.name,
                tap: .card(label: viewModel.routeTitle ?? "", id: "schedule.route", action: onEditRoute),
                swapID: "schedule.swap"
            ) {
                Task { await viewModel.swap() }
            }
        }
    }

    /// The GO line code tile and the line's name in 26 pt bold, with the amber Notice chip at the end of the row.
    @ViewBuilder private var lineRow: some View {
        if let line = viewModel.route?.line {
            HStack(spacing: Self.lineRowGap) {
                LineTile(line: line)
                Text(verbatim: line.name)
                    .font(TTFont.lineName)
                    .tracking(-0.6)
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("schedule.line")
                Spacer(minLength: 0)
                if !viewModel.lineNotices.isEmpty {
                    noticeChip
                }
            }
            .frame(height: LineTile.size)
            .padding(.leading, 2)
        }
    }

    /// The canvas's 10 pt between the line row and the card, and between the tile and the name.
    private static let lineRowGap: CGFloat = 10

    /// "Notice" in amber: 30 pt tall, with a 44 pt target that takes only the chip's height in the row.
    private var noticeChip: some View {
        Button(action: onOpenLineNotice) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: TTSize.iconSM + 1, weight: .semibold))
                Text("schedule.notice_chip")
                    .font(TTFont.badgeLarge)
                    .tracking(-0.2)
            }
            .foregroundStyle(TTColor.delayInk)
            .padding(.leading, 10)
            .padding(.trailing, TTSpace.s3)
            .frame(height: 30)
            .background(TTColor.delayFill, in: Capsule())
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .padding(.vertical, -7)
        .fixedSize()
        .accessibilityLabel(Text("schedule.line_notice"))
        .accessibilityIdentifier("schedule.lineNotice")
    }

    // MARK: Day strip

    /// A swipeable row of 60 × 48 pt tiles: the previous 7 days, Today and every day of the schedule after it (D49, D53). It
    /// opens with Today first, so the past week is a swipe to the right. It bleeds to both screen edges under a 16 pt fade,
    /// so half of the sixth tile peeks, and snaps tile by tile. A tile's id is its place counted from Today: 0 is Today, -1
    /// yesterday.
    private var dayStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: TTSpace.s2) {
                ForEach(Array(viewModel.stripDays.enumerated()), id: \.offset) { position, day in
                    let index = position - ScheduleViewModel.pastDayCount
                    DayCell(
                        weekday: index == 0 ? String(localized: "button.today") : day.weekdayShort,
                        day: "\(day.day)",
                        isSelected: day == viewModel.selectedDay,
                        isToday: index == 0
                    ) {
                        Task { await viewModel.select(day) }
                    }
                    .id(index)
                    .accessibilityIdentifier("schedule.day.\(index)")
                }
            }
            .scrollTargetLayout()
            // Room for the tile shadow inside the clipped strip.
            .padding(.vertical, Self.shadowRoom)
        }
        .contentMargins(.horizontal, TTSpace.s5, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $stripPosition)
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Self.edgeFade)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Self.edgeFade)
            }
        }
        // "Show Monday" and picking another day bring an out-of-view tile to the start; Today brings the strip back.
        .onChange(of: viewModel.selectedDay) { showSelectedDay(animated: true) }
        .onAppear { showSelectedDay(animated: false) }
        // Tapping the Schedule tab again returns to Today and Now: the strip comes back to Today too, though Today was selected.
        .onChange(of: viewModel.scrollRequest) {
            guard viewModel.isToday, stripPosition != 0 else { return }
            withAnimation(.easeOut(duration: 0.3)) { stripPosition = 0 }
        }
        .frame(height: DayCell.size.height + 2 * Self.shadowRoom)
        .padding(.vertical, -Self.shadowRoom)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }

    /// Brings the selected day's tile into the strip's five whole tiles when it is not in them.
    private func showSelectedDay(animated: Bool) {
        let index = viewModel.stripIndex(of: viewModel.selectedDay) ?? 0
        let first = stripPosition ?? 0
        guard index < first || index >= first + Self.fullTiles else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.3)) { stripPosition = index }
        } else {
            stripPosition = index
        }
    }

    private static let shadowRoom: CGFloat = 2
    /// Tiles that show whole at the start of the strip.
    private static let fullTiles = 5

    // MARK: Timeline

    /// The to-scale timeline (TT-111 layout, TT-113 drawing), its loading skeleton, or an empty state card (TT-115).
    /// One scroll view holds them all, so a scroll request still lands when the content changes with it. It scrolls under
    /// the tab bar, with the bottom edge softened by the system on iOS 26 and later.
    private var timeline: some View {
        ScrollView {
            Group {
                switch viewModel.content {
                case .loading:
                    ScheduleLoadingTimeline(now: viewModel.now, formatter: formatter)
                case .timeline:
                    ScheduleTimeline(
                        viewModel: viewModel, formatter: formatter, onOpen: onOpenTrip, bell: bell(for:), onBell: tapBell(_:)
                    )
                    .background(
                        ScrollOffsetSetter(offset: viewModel.isToday ? viewModel.layout.initialScrollOffset : 0, order: scrollOrder)
                    )
                case .noTrains(let title, let message, let showDay):
                    noTrains(title: title, message: message, showDay: showDay)
                case .noConnection:
                    noConnection
                }
            }
        }
        .softBottomEdge()
        .refreshable { await viewModel.refresh() }
        .onChange(of: viewModel.scrollRequest) { previous, _ in
            riderScrolled = false
            scroll(animated: previous != 0)
        }
        // The cards are measured after the first scroll, which moves Now: scroll again (D49).
        .onChange(of: viewModel.settleRequest) {
            settle()
        }
        // And again a moment after the request, when the content was not laid out yet at the first scroll (D52).
        .onChange(of: viewModel.rescrollRequest) {
            settle()
        }
        .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in
            if !riderScrolled { riderScrolled = true }
        })
        .accessibilityIdentifier("schedule.timeline")
    }

    /// Today shows Now near the top, another day its first train: `ScrollOffsetSetter` moves the scroll view there.
    private func scroll(animated: Bool) {
        scrollOrder = ScrollOrder(token: scrollOrder.token + 1, animated: animated)
    }

    /// A scroll to the present again, unless the rider has taken over the scrolling. Without animation on the first request
    /// (the launch); later ones animate, as the request did, so the second scroll only steers the first.
    private func settle() {
        guard !riderScrolled else { return }
        scroll(animated: viewModel.scrollRequest > 1)
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
        .padding(.top, TTSpace.s6)
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

extension View {
    /// The system's soft fade where content scrolls under the floating tab bar (iOS 26 and later, D49).
    @ViewBuilder fileprivate func softBottomEdge() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            self
        }
    }
}
