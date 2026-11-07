import SwiftUI

/// Schedule tab (TT-112): inline "Train Times" header with the Settings gear, route header, 7-day strip and freshness
/// row with the Now button, then the to-scale timeline with its rail and cards (TT-113).
struct ScheduleView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    let viewModel: ScheduleViewModel
    let onSettings: () -> Void
    let onEditRoute: () -> Void
    /// The star at three favourites: the route sheet opens with the favourites to remove one (TT-122).
    var onManageFavourites: () -> Void = {}
    /// Tap a card: Trip details (TT-118).
    var onOpenTrip: (TripKey) -> Void = { _ in }
    /// "Line notice" in the freshness row: the notice sheet (TT-132).
    var onOpenLineNotice: () -> Void = {}

    /// The one formatter (D17), following the Time format setting (TT-105).
    @Environment(\.timeFormatter) private var formatter
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            navigationHeader
            VStack(alignment: .leading, spacing: 0) {
                routeHeader
                    .padding(.horizontal, TTSpace.s5)
                    .padding(.bottom, TTSpace.s3)
                dayStrip
                    .padding(.bottom, TTSpace.s2)
                freshnessRow
                    .padding(.horizontal, TTSpace.s5)
            }
            .padding(.top, TTSpace.s1)
            timeline
                .padding(.top, TTSpace.s3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TTColor.canvas)
        // Title stays set so Settings' back button reads "Train Times"; the header above replaces the bar.
        .navigationTitle(Text("app.name"))
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.loadIfNeeded() }
        .task { await viewModel.runClock() }
        // Live status every 30 s, and at once on coming back to the foreground (TT-131).
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await viewModel.pollLiveStatus()
        }
    }

    private var navigationHeader: some View {
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
    }

    // MARK: Route header

    /// Origin and destination wrap to two lines before truncating; tapping them opens the route sheet.
    private var routeHeader: some View {
        HStack(spacing: TTSpace.s2) {
            Button(action: onEditRoute) {
                VStack(alignment: .leading, spacing: TTSpace.s1 / 2) {
                    if let title = viewModel.routeTitle {
                        Text(title)
                            .font(TTFont.route)
                            .foregroundStyle(TTColor.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
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
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("schedule.route")

            HStack(spacing: 0) {
                IconButton(systemName: "arrow.up.arrow.down", label: "route.swap") {
                    Task { await viewModel.swap() }
                }
                .accessibilityIdentifier("schedule.swap")
                IconButton(
                    systemName: viewModel.isFavourite ? "star.fill" : "star",
                    label: viewModel.isFavourite ? "route.favourite_remove" : "route.favourite_add"
                ) {
                    if viewModel.toggleFavourite() == .full { onManageFavourites() }
                }
                .accessibilityIdentifier("schedule.favourite")
            }
        }
    }

    /// The canvas's line dot (`.rh .dot`).
    private static let lineDot: CGFloat = 10

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
                            ScheduleTimeline(viewModel: viewModel, formatter: formatter, onOpen: onOpenTrip)
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
        ScheduleView(viewModel: .fixtures(), onSettings: {}, onEditRoute: {})
    }
}
