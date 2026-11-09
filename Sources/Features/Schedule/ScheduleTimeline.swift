import SwiftUI

/// The to-scale timeline (TT-113): rail, gridlines, Now line, markers and cards, placed by the TT-111 layout. The left column
/// holds the gridline times only, never a train's own time, which its card shows (D49). Across, it follows the canvas `.tl`
/// geometry: labels end at 52 pt, the rail is centred on 62 pt and cards start at 82 pt. Everything but the cards is
/// decoration and hidden from assistive tech.
struct ScheduleTimeline: View {
    let viewModel: ScheduleViewModel
    let formatter: any TimeFormatting
    let onOpen: (TripKey) -> Void
    /// Each card's bell (TT-141).
    var bell: (TripKey) -> AlertBellModel.Bell = { _ in .off }
    var onBell: (TripKey) -> Void = { _ in }

    /// The right edge of the label column.
    private static let labelColumn = TTTimeline.leftInset + TTTimeline.labelWidth
    private static let railX = labelColumn + 10
    private static let railWidth: CGFloat = 2
    private static let markerSize: CGFloat = 12
    private static let leadMarkerSize: CGFloat = 16
    /// The amber bar from a delayed train's scheduled marker down to its expected one (TT-114).
    private static let delayBarWidth: CGFloat = 4
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
                delayBars(cards, places)
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
                DepartureCardView(card: card, bell: bell(card.id), onOpen: { onOpen(card.id) }, onBell: { onBell(card.id) }) { size in
                    viewModel.setCardSize(size, for: card.id)
                }
                .padding(.leading, Self.cardX)
                .padding(.trailing, TTSpace.s5)
                .offset(y: place.top)
            }
        }
    }

    // MARK: Rail

    /// A hairline every 15 min, under the cards, with its time in the label column unless Now sits close.
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
            if let label = fold.label(formatter) {
                Text(label)
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

    /// 4 pt amber bar down the rail from a delayed train's scheduled marker to its expected one: its length is the delay.
    private func delayBars(_ cards: [DepartureCard], _ places: [TripKey: TimelineLayout.Card]) -> some View {
        ForEach(cards) { card in
            if let bar = places[card.id]?.delayBar {
                Capsule()
                    .fill(TTColor.delayInk)
                    .frame(width: Self.delayBarWidth, height: bar.upperBound - bar.lowerBound)
                    .offset(x: Self.railX - Self.delayBarWidth / 2, y: bar.lowerBound)
            }
        }
    }

    /// 2 pt line from each marker to its card, in the marker's colour.
    private func connectors(_ cards: [DepartureCard], _ places: [TripKey: TimelineLayout.Card]) -> some View {
        ForEach(cards) { card in
            if let place = places[card.id] {
                Rectangle()
                    .fill(card.isCancelled ? TTColor.cancelInk : TTColor.accent)
                    .frame(width: TTTimeline.connectorLength, height: Self.railWidth)
                    .offset(x: Self.railX + Self.markerSize / 2, y: place.markerY - Self.railWidth / 2)
            }
        }
    }

    /// Each train's marker on the rail; a delayed train also keeps a hollow amber marker at its scheduled time.
    private func markers(_ cards: [DepartureCard], _ places: [TripKey: TimelineLayout.Card]) -> some View {
        ForEach(cards) { card in
            if let place = places[card.id] {
                if let scheduledY = place.scheduledMarkerY {
                    ring(TTColor.delayInk)
                        .centred(x: Self.railX, y: scheduledY)
                }
                marker(for: card)
                    .centred(x: Self.railX, y: place.markerY)
            }
        }
    }

    /// 16 pt solid accent dot for the next usable train, with a canvas ring; a 16 pt red x for a cancelled train or skipped
    /// stop; a 12 pt ring for the others.
    @ViewBuilder private func marker(for card: DepartureCard) -> some View {
        if card.isCancelled {
            Image(systemName: card.status.symbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(TTColor.cancelInk)
                .frame(width: Self.leadMarkerSize, height: Self.leadMarkerSize)
                .background(TTColor.canvas, in: Circle())
        } else if card.isNext {
            Circle()
                .fill(TTColor.accent)
                .frame(width: Self.leadMarkerSize, height: Self.leadMarkerSize)
                .padding(Self.leadRing)
                .background(TTColor.canvas, in: Circle())
        } else {
            ring(TTColor.accent)
        }
    }

    /// A 12 pt hollow marker: accent for a train, amber at a delayed train's scheduled time.
    private func ring(_ colour: Color) -> some View {
        Circle()
            .fill(TTColor.surface)
            .overlay(Circle().strokeBorder(colour, lineWidth: Self.railWidth))
            .frame(width: Self.markerSize, height: Self.markerSize)
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
        label(Text("button.now"), at: y, weight: .semibold)
            .foregroundStyle(TTColor.accent)
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

/// One departure (TT-113, TT-157): three fixed rows, 118 pt in every state, so nothing moves between states (D50).
/// Row 1: departure time, the Express bolt, the bell. Row 2: countdown and platform, trip length. Row 3: status line,
/// "Arrival" and the arrival time. Delayed: amber times. Cancelled or stop skipped: struck grey times, no bolt, no bell.
/// Reports its measured height and anchor so the layout can centre its time line on the marker and keep cards apart.
struct DepartureCardView: View {
    let card: DepartureCard
    var bell: AlertBellModel.Bell = .off
    let onOpen: () -> Void
    var onBell: () -> Void = {}
    let onSize: (TimelineCardSize) -> Void

    @State private var height: CGFloat = 0
    @State private var anchor: CGFloat = 0
    @Environment(\.displayScale) private var displayScale

    /// Top, trailing (the bell side), bottom and leading padding from the canvas.
    private static let padding = EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 10)
    private static let rowGap: CGFloat = 4
    private static let timeRowHeight: CGFloat = 38
    private static let detailRowHeight: CGFloat = 20
    private static let statusRowHeight: CGFloat = 24
    /// The bell's 48 pt target is flush with the card's trailing edge and centred on the time row.
    private static let bellTarget: CGFloat = 48
    private static let bellGlyph: CGFloat = 26
    private static let bellTop = padding.top + timeRowHeight / 2 - bellTarget / 2
    /// The time row keeps the bell's width (less the trailing padding it bleeds into) plus the 8 pt gap free.
    private static let bellRoom = bellTarget - padding.trailing + TTSpace.s2
    private static let timeMinimumScale: CGFloat = 0.85

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: Self.rowGap) {
                timeRow
                HStack(spacing: TTSpace.s2) {
                    detail
                    Spacer(minLength: 0)
                    Text(card.tripLength)
                        .font(TTFont.footnote)
                        .monospacedDigit()
                        .foregroundStyle(TTColor.inkSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(height: Self.detailRowHeight)
                HStack(spacing: TTSpace.s2) {
                    StatusLine(status: card.status)
                    Spacer(minLength: 0)
                    arrival
                }
                .frame(height: Self.statusRowHeight)
            }
            .padding(Self.padding)
            .frame(height: TimelineCardSize.standard.height, alignment: .top)
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
        // The bell sits over the time row, outside the card's one element, so it is a separate button.
        .overlay(alignment: .topTrailing) {
            if !card.isCancelled {
                bellButton
                    .padding(.top, Self.bellTop)
            }
        }
    }

    /// The departure time (34 pt on the next train, 32 pt otherwise) and the Express bolt 8 pt after it.
    private var timeRow: some View {
        HStack(spacing: TTSpace.s2) {
            Text(card.time)
                .font(card.isNext ? TTFont.timeLead : TTFont.timeRow)
                .monospacedDigit()
                .strikethrough(card.isCancelled)
                .foregroundStyle(timeInk)
                .lineLimit(1)
                .minimumScaleFactor(Self.timeMinimumScale)
            if !card.isCancelled {
                ExpressBolt(isExpress: card.isExpress)
            }
            Spacer(minLength: card.isCancelled ? 0 : Self.bellRoom)
        }
        .frame(height: Self.timeRowHeight)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(cardSpace)).midY } action: {
            anchor = $0
            report()
        }
    }

    /// "in 11 min · Plat 2" on the next train, "Plat 2" (or "Plat —") on the others, "Next usable below" when cancelled.
    @ViewBuilder private var detail: some View {
        if card.isCancelled {
            if let note = card.note {
                Text(note)
                    .font(TTFont.subhead)
                    .foregroundStyle(TTColor.inkSecondary)
                    .lineLimit(1)
            }
        } else {
            HStack(spacing: TTSpace.s1 + 2) {
                if let relative = card.relativeTime {
                    Text(relative)
                        .font(TTFont.subhead.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(TTColor.ink)
                    // A separator glyph, not copy.
                    Text(verbatim: "·")
                        .font(TTFont.subhead)
                        .foregroundStyle(TTColor.inkTertiary)
                }
                Text(platformText)
                    .font(TTFont.subhead)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .fixedSize()
        }
    }

    /// "Plat" in ink-secondary; the number semibold in ink, or the dash in ink-tertiary until GO publishes it.
    private var platformText: AttributedString {
        var text = AttributedString(card.platform)
        text.foregroundColor = TTColor.inkSecondary
        if let range = text.range(of: card.platformValue, options: .backwards) {
            if card.hasPlatform {
                text[range].foregroundColor = TTColor.ink
                text[range].font = TTFont.subhead.weight(.semibold)
            } else {
                text[range].foregroundColor = TTColor.inkTertiary
            }
        }
        return text
    }

    /// "Arrival" in 13 pt, then the arrival time in 17 pt semibold, on one line level with the status.
    private var arrival: some View {
        HStack(alignment: .firstTextBaseline, spacing: TTSpace.s1) {
            Text("schedule.arrival")
                .font(TTFont.footnote)
                .foregroundStyle(TTColor.inkSecondary)
            Text(card.arrivalTime)
                .font(TTFont.timeArrival)
                .monospacedDigit()
                .strikethrough(card.isCancelled)
                .foregroundStyle(timeInk)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private var timeInk: Color {
        if card.isCancelled { return TTColor.inkTertiary }
        return card.isDelayed ? TTColor.delayInk : TTColor.ink
    }

    /// One tap arms a This-trip alert and fills the bell; another turns it off (TT-141). Dimmed while Setting up.
    private var bellButton: some View {
        let label = bell == .on ? String(localized: "alert.bell.label_on") : String(localized: "alert.bell.label")
        return IconButton(
            systemName: bell == .on ? "bell.fill" : "bell",
            label: Text(verbatim: String(format: label, card.trainName)),
            action: onBell
        )
        .sized(glyph: Self.bellGlyph, target: Self.bellTarget)
        .disabled(bell == .settingUp)
        .accessibilityIdentifier("schedule.bell.\(card.id.tripId)")
    }

    private func report() {
        guard height > 0, anchor > 0 else { return }
        onSize(TimelineCardSize(height: wholePixels(height), anchor: wholePixels(anchor)))
    }

    /// A 32 pt time's centre falls on a half pixel, so a card can land on that half pixel too, and floating-point noise in
    /// the measurement then picks the pixel it draws on: one snapshot run drew a card 1 px off another. Snapped to whole
    /// pixels (a half pixel rounds down), every measurement of the same card is the same number.
    private func wholePixels(_ value: CGFloat) -> CGFloat {
        let scale = max(displayScale, 1)
        let halfPixels = (value * scale * 2).rounded()
        return (halfPixels / 2).rounded(.down) / scale
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
