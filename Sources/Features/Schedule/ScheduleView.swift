import SwiftUI

/// Schedule tab (TT-112): inline "Train Times" header with the Settings gear, route header, 7-day strip and freshness
/// row with the Now button, then the to-scale timeline space that TT-113 draws the rail and cards into.
struct ScheduleView: View {
    let viewModel: ScheduleViewModel
    let onSettings: () -> Void
    let onEditRoute: () -> Void

    /// The one formatter (D17).
    private let formatter: any TimeFormatting = TimeFormatter(format: .device)

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
                                .fill(line.colorHex.flatMap(Color.init(lineHex:)) ?? TTColor.inkSecondary)
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
                    viewModel.toggleFavourite()
                }
                .accessibilityIdentifier("schedule.favourite")
            }
        }
    }

    /// The canvas's line dot (`.rh .dot`).
    private static let lineDot: CGFloat = 10

    // MARK: Day strip

    /// Seven cells fill the width, Today first; the strip scrolls sideways for later dates.
    private var dayStrip: some View {
        GeometryReader { geometry in
            let visible = CGFloat(7)
            let width = (geometry.size.width - 2 * TTSpace.s5 - (visible - 1) * TTSpace.s1) / visible
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
                        .accessibilityIdentifier("schedule.day.\(index)")
                    }
                }
                .padding(.horizontal, TTSpace.s5)
            }
            .scrollClipDisabled()
        }
        .frame(height: TTSize.targetMin + 2)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }

    // MARK: Freshness row

    private var freshnessRow: some View {
        HStack(spacing: TTSpace.s2) {
            if let mode = viewModel.freshnessMode(formatter) {
                FreshnessLine(mode: mode)
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

    // MARK: Timeline

    private enum TimelineAnchor: Hashable {
        case top, now
    }

    /// The to-scale timeline space (TT-111 layout). TT-113 draws the rail, markers and cards in it.
    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .top) {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: viewModel.layout.height)
                    Color.clear
                        .frame(height: 1)
                        .id(TimelineAnchor.top)
                    Color.clear
                        .frame(height: 1)
                        .id(TimelineAnchor.now)
                        .padding(.top, viewModel.layout.initialScrollOffset)
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
}

#Preview {
    NavigationStack {
        ScheduleView(viewModel: .fixtures(), onSettings: {}, onEditRoute: {})
    }
}
