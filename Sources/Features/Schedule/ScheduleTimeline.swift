import SwiftUI

/// The to-scale timeline (TT-113): rail, gridlines, Now line, markers, time pills and cards, placed by the TT-111 layout.
/// Across, it follows the canvas `.tl` geometry: labels end at 52 pt, pills sit at 12 pt, the rail is centred on 62 pt and
/// cards start at 82 pt. Everything but the cards is decoration and hidden from assistive tech.
struct ScheduleTimeline: View {
    let viewModel: ScheduleViewModel
    let formatter: any TimeFormatting
    let onOpen: (TripKey) -> Void

    /// The right edge of the label column: the pill slot after its 12 pt inset.
    private static let labelColumn = TTTimeline.leftInset + TimePill.railSize.width
    private static let railX = labelColumn + 10
    private static let railWidth: CGFloat = 2
    private static let markerSize: CGFloat = 12
    private static let leadMarkerSize: CGFloat = 16
    private static let nowDot: CGFloat = 10
    /// The canvas ring that lifts the next train's dot off the rail.
    private static let leadRing: CGFloat = 3
    /// The card column starts where the 14 pt connector from the 12 pt marker ends.
    private static let cardX = railX + markerSize / 2 + TTTimeline.connectorLength

    var body: some View {
        let layout = viewModel.layout
        let cards = viewModel.cards(formatter)
        let places = Dictionary(layout.cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        ZStack(alignment: .topLeading) {
            Group {
                gridlines(layout)
                rail(layout)
                connectors(cards, places)
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            cardViews(cards, places)
            Group {
                markers(cards, places)
                if let nowY = layout.nowY { nowLine(at: nowY) }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: layout.height, alignment: .top)
    }

    // MARK: Cards

    private func cardViews(_ cards: [DepartureCard], _ places: [TripKey: TimelineLayout.Card]) -> some View {
        ForEach(cards) { card in
            if let place = places[card.id] {
                DepartureCardView(card: card, onOpen: { onOpen(card.id) }) { size in
                    viewModel.setCardSize(size, for: card.id)
                }
                .padding(.leading, Self.cardX)
                .padding(.trailing, TTSpace.s5)
                .offset(y: place.top)
            }
        }
    }

    // MARK: Rail

    /// A hairline every 15 min, under the cards, with its time in the label column unless a pill or Now sits close.
    @ViewBuilder private func gridlines(_ layout: TimelineLayout) -> some View {
        ForEach(layout.gridlines, id: \.time) { gridline in
            Rectangle()
                .fill(TTColor.hairline)
                .frame(height: 1)
                .padding(.leading, Self.railX)
                .padding(.trailing, TTSpace.s5)
                .centred(y: gridline.y)
            if viewModel.showsLabel(gridline) {
                label(Text(formatter.railTime(gridline.time)), at: gridline.y)
                    .foregroundStyle(TTColor.inkSecondary)
            }
        }
    }

    /// Solid to the end of the content, dashed where a long gap folds, with the fold's pill in the card column.
    @ViewBuilder private func rail(_ layout: TimelineLayout) -> some View {
        ForEach(Self.solidSegments(height: layout.height, folds: layout.folds), id: \.lowerBound) { segment in
            Rectangle()
                .fill(TTColor.hairline)
                .frame(width: Self.railWidth, height: segment.upperBound - segment.lowerBound)
                .offset(x: Self.railX - Self.railWidth / 2, y: segment.lowerBound)
        }
        ForEach(layout.folds, id: \.pillY) { fold in
            VerticalLine()
                .stroke(TTColor.controlBorder, style: StrokeStyle(lineWidth: Self.railWidth, dash: [TTSpace.s1, TTSpace.s1]))
                .frame(width: Self.railWidth, height: fold.dashed.upperBound - fold.dashed.lowerBound)
                .offset(x: Self.railX - Self.railWidth / 2, y: fold.dashed.lowerBound)
            Text(fold.label(formatter))
                .font(TTFont.footnote)
                .monospacedDigit()
                .foregroundStyle(TTColor.inkSecondary)
                .padding(.horizontal, TTSpace.s3)
                .padding(.vertical, TTSpace.s1 - 1)
                .background(TTColor.surfaceRaised, in: Capsule())
                .frame(maxWidth: .infinity)
                .padding(.leading, Self.cardX)
                .padding(.trailing, TTSpace.s5)
                .centred(y: fold.pillY)
        }
    }

    private static func solidSegments(height: CGFloat, folds: [TimelineLayout.Fold]) -> [ClosedRange<CGFloat>] {
        var segments: [ClosedRange<CGFloat>] = []
        var start: CGFloat = 0
        for fold in folds.sorted(by: { $0.dashed.lowerBound < $1.dashed.lowerBound }) {
            if fold.dashed.lowerBound > start { segments.append(start...fold.dashed.lowerBound) }
            start = max(start, fold.dashed.upperBound)
        }
        if height > start { segments.append(start...height) }
        return segments
    }

    // MARK: Markers

    /// 2 pt line from each marker to its card, in the marker's colour.
    private func connectors(_ cards: [DepartureCard], _ places: [TripKey: TimelineLayout.Card]) -> some View {
        ForEach(cards) { card in
            if let place = places[card.id] {
                Rectangle()
                    .fill(TTColor.accent)
                    .frame(width: TTTimeline.connectorLength, height: Self.railWidth)
                    .offset(x: Self.railX + Self.markerSize / 2, y: place.markerY - Self.railWidth / 2)
            }
        }
    }

    /// Each train's time pill in the label column and its marker on the rail.
    private func markers(_ cards: [DepartureCard], _ places: [TripKey: TimelineLayout.Card]) -> some View {
        ForEach(cards) { card in
            if let place = places[card.id] {
                TimePill(time: card.pillTime, style: card.isNext ? .next : .later, isOnRail: true)
                    .centred(x: TTTimeline.leftInset + TimePill.railSize.width / 2, y: place.markerY)
                marker(isNext: card.isNext)
                    .centred(x: Self.railX, y: place.markerY)
            }
        }
    }

    /// 16 pt solid accent dot for the next usable train, with a canvas ring; a 12 pt ring for the others.
    @ViewBuilder private func marker(isNext: Bool) -> some View {
        if isNext {
            Circle()
                .fill(TTColor.accent)
                .frame(width: Self.leadMarkerSize, height: Self.leadMarkerSize)
                .padding(Self.leadRing)
                .background(TTColor.canvas, in: Circle())
        } else {
            Circle()
                .fill(TTColor.surface)
                .overlay(Circle().strokeBorder(TTColor.accent, lineWidth: Self.railWidth))
                .frame(width: Self.markerSize, height: Self.markerSize)
        }
    }

    /// 2 pt accent line across the timeline with a dot on the rail and "Now" in the label column.
    @ViewBuilder private func nowLine(at y: CGFloat) -> some View {
        Rectangle()
            .fill(TTColor.accent)
            .frame(height: Self.railWidth)
            .padding(.leading, Self.railX)
            .padding(.trailing, TTSpace.s5)
            .centred(y: y)
        Circle()
            .fill(TTColor.accent)
            .frame(width: Self.nowDot, height: Self.nowDot)
            .centred(x: Self.railX, y: y)
        if viewModel.showsNowLabel {
            label(Text("button.now"), at: y, weight: .semibold)
                .foregroundStyle(TTColor.accent)
        }
    }

    /// Footnote text, right-aligned in the label column and centred on `y`.
    private func label(_ text: Text, at y: CGFloat, weight: Font.Weight = .regular) -> some View {
        text
            .font(TTFont.footnote.weight(weight))
            .monospacedDigit()
            .lineLimit(1)
            .frame(width: Self.labelColumn, alignment: .trailing)
            .centred(y: y)
    }
}

/// One departure (TT-113): time, labelled arrival, status badge, platform or "in N min", tags and the bell.
/// Reports its measured height and anchor so the layout can centre its time line on the marker and keep cards apart.
struct DepartureCardView: View {
    let card: DepartureCard
    let onOpen: () -> Void
    let onSize: (TimelineCardSize) -> Void

    @State private var height: CGFloat = 0
    @State private var anchor: CGFloat = 0

    /// The canvas card pads 14 pt, and 10 pt on the bell side; `Card` pads 16 pt.
    private static let inset = EdgeInsets(top: -2, leading: -2, bottom: -2, trailing: -6)
    /// The bell's 44 pt target bleeds into the card padding, so the badge row stays one badge tall.
    private static let bellBleed: CGFloat = 10
    /// Between the badge row and the wrapped tags.
    private static let tagRowGap: CGFloat = 6
    private static let timeMinimumScale: CGFloat = 0.85

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: TTSpace.s1) {
                HStack(alignment: .top, spacing: TTSpace.s2) {
                    Text(card.time)
                        .font(card.isNext ? TTFont.timeLead : TTFont.timeRow)
                        .monospacedDigit()
                        .foregroundStyle(TTColor.ink)
                        .lineLimit(1)
                        // "12:47 PM" beside a long arrival label shrinks a little rather than truncating.
                        .minimumScaleFactor(Self.timeMinimumScale)
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(cardSpace)).midY } action: {
                            anchor = $0
                            report()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    arrival
                }
                badgeRow
            }
            .padding(Self.inset)
        }
        .coordinateSpace(.named(cardSpace))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
            height = $0
            report()
        }
        .contentShape(RoundedRectangle(cornerRadius: TTRadius.lg))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("schedule.card.\(card.id.tripId)")
    }

    /// "Scheduled arrival" over the 17 pt time; the next train's platform goes under it.
    private var arrival: some View {
        VStack(alignment: .trailing, spacing: TTSpace.s1 / 2) {
            Text(card.arrivalLabel)
                .font(TTFont.footnote)
                .foregroundStyle(TTColor.inkSecondary)
            Text(card.arrivalTime)
                .font(TTFont.timeArrival)
                .monospacedDigit()
                .foregroundStyle(TTColor.ink)
            if card.isNext {
                platform
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// Badge, platform or "in N min", tags and the bell on one line; tags wrap under them when they do not fit.
    private var badgeRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: TTSpace.s2) {
                StatusBadge(status: card.status)
                detail
                tags
                Spacer(minLength: 0)
                bell
            }
            VStack(alignment: .leading, spacing: Self.tagRowGap) {
                HStack(spacing: TTSpace.s2) {
                    StatusBadge(status: card.status)
                    detail
                    Spacer(minLength: 0)
                    bell
                }
                tags
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let relative = card.relativeTime {
            Text(relative)
                .font(TTFont.badge)
                .monospacedDigit()
                .foregroundStyle(TTColor.accent)
                .lineLimit(1)
                .fixedSize()
        } else {
            platform
        }
    }

    private var platform: some View {
        Text(card.platform)
            .font(TTFont.footnote)
            .monospacedDigit()
            .foregroundStyle(TTColor.inkSecondary)
            .lineLimit(1)
            .fixedSize()
    }

    /// Express shows its word unless the row carries more than one tag.
    @ViewBuilder private var tags: some View {
        if !card.tags.isEmpty {
            HStack(spacing: TTSpace.s2) {
                ForEach(card.tags, id: \.self) { tag in
                    switch tag {
                    case .express: ExpressTag(iconOnly: card.tags.count > 1)
                    }
                }
            }
        }
    }

    /// Armed in TT-141.
    private var bell: some View {
        IconButton(systemName: "bell", label: "button.add_alert") {}
            .padding(.vertical, -Self.bellBleed)
            .padding(.trailing, -Self.bellBleed)
    }

    private func report() {
        guard height > 0, anchor > 0 else { return }
        onSize(TimelineCardSize(height: height, anchor: anchor))
    }
}

/// The card's own coordinate space, where its time line's centre is the layout anchor.
private let cardSpace = "departureCard"

/// The rail's dashed part across a fold.
private struct VerticalLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
    }
}

private extension View {
    /// Centres the view on a point of the timeline whatever its size: on `y`, and on `x` when given.
    func centred(x: CGFloat? = nil, y: CGFloat) -> some View {
        frame(width: x == nil ? nil : 0, height: 0)
            .offset(x: x ?? 0, y: y)
    }
}
