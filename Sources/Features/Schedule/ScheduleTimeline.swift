import SwiftUI

/// The to-scale timeline (TT-113): rail, gridlines, Now line, markers and cards, placed by the TT-111 layout. The left column
/// holds the gridline times only, never a train's own time, which its card shows (D49). Across, it follows the canvas `.tl`
/// geometry: labels end at 52 pt, the rail is centred on 62 pt and cards start at 82 pt. Everything but the cards is
/// decoration and hidden from assistive tech. A new set of trains cascades in, each card with its rail marks, and the Now dot
/// pulses on the way back to Now (TT-164, D61).
struct ScheduleTimeline: View {
    let viewModel: ScheduleViewModel
    let formatter: any TimeFormatting
    let onOpen: (TripKey) -> Void
    /// Each card's bell (TT-141).
    var bell: (TripKey) -> AlertBellModel.Bell = { _ in .off }
    /// How many times each card's bell has shaken on a refusal (TT-190).
    var shakes: (TripKey) -> Int = { _ in 0 }
    var onBell: (TripKey) -> Void = { _ in }
    /// The cards' cascade, at rest unless a new set of trains has just been shown.
    var cascade: CascadeCue = .rest
    /// When the Now dot's pulse started, read by the dot alone; nil draws it at rest.
    var motion: ScheduleMotionClock?

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
        // The cascade starts with the first card where the timeline opens (Now on today, the first train on another day).
        let orders = layout.cascadeOrder(scrolledTo: viewModel.isToday ? layout.initialScrollOffset : 0)
        ZStack(alignment: .topLeading) {
            Group {
                gridlines(layout)
                rail(layout)
                delayBars(cards, places, orders)
                connectors(cards, places, orders)
                // The Now line runs behind the cards; its dot and label stay on the rail, above the markers.
                if let nowY = layout.nowY { nowRule(at: nowY) }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            cardViews(cards, places, orders)
            Group {
                markers(cards, places, orders)
                if let nowY = layout.nowY { nowMarker(at: nowY) }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: layout.height, alignment: .top)
    }

    // MARK: Cards

    private func cardViews(
        _ cards: [DepartureCard], _ places: [TripKey: TimelineLayout.Card], _ orders: [TripKey: Int]
    ) -> some View {
        ForEach(cards) { card in
            if let place = places[card.id] {
                DepartureCardView(
                    card: card, bell: bell(card.id), shakes: shakes(card.id), onOpen: { onOpen(card.id) }, onBell: { onBell(card.id) }
                ) { size in
                    viewModel.setCardSize(size, for: card.id)
                }
                .cascadeEntrance(cascade, order: orders[card.id] ?? 0, moves: !viewModel.isPastDay)
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
    private func delayBars(
        _ cards: [DepartureCard], _ places: [TripKey: TimelineLayout.Card], _ orders: [TripKey: Int]
    ) -> some View {
        ForEach(cards) { card in
            if let bar = places[card.id]?.delayBar {
                Capsule()
                    .fill(TTColor.delayInk)
                    .frame(width: Self.delayBarWidth, height: bar.upperBound - bar.lowerBound)
                    .cascadeEntrance(cascade, order: orders[card.id] ?? 0, moves: false)
                    .offset(x: Self.railX - Self.delayBarWidth / 2, y: bar.lowerBound)
            }
        }
    }

    /// 2 pt line from each marker to its card, in the marker's colour.
    private func connectors(
        _ cards: [DepartureCard], _ places: [TripKey: TimelineLayout.Card], _ orders: [TripKey: Int]
    ) -> some View {
        ForEach(cards) { card in
            if let place = places[card.id] {
                Rectangle()
                    .fill(card.isCancelled ? TTColor.cancelInk : TTColor.accent)
                    .frame(width: TTTimeline.connectorLength, height: Self.railWidth)
                    .cascadeEntrance(cascade, order: orders[card.id] ?? 0, moves: false)
                    .offset(x: Self.railX + Self.markerSize / 2, y: place.markerY - Self.railWidth / 2)
            }
        }
    }

    /// Each train's marker on the rail; a delayed train also keeps a hollow amber marker at its scheduled time. They fade in
    /// with their card's cascade.
    private func markers(
        _ cards: [DepartureCard], _ places: [TripKey: TimelineLayout.Card], _ orders: [TripKey: Int]
    ) -> some View {
        ForEach(cards) { card in
            if let place = places[card.id] {
                if let scheduledY = place.scheduledMarkerY {
                    ring(TTColor.delayInk)
                        .cascadeEntrance(cascade, order: orders[card.id] ?? 0, moves: false)
                        .centred(x: Self.railX, y: scheduledY)
                }
                marker(for: card)
                    .cascadeEntrance(cascade, order: orders[card.id] ?? 0, moves: false)
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

    /// The 2 pt accent line across the timeline, under the cards (a dot on the rail and "Now" in the label column mark it).
    private func nowRule(at y: CGFloat) -> some View {
        Rectangle()
            .fill(TTColor.accent)
            .frame(height: Self.railWidth)
            .padding(.leading, Self.railX)
            .padding(.trailing, TTSpace.s5)
            .centred(y: y)
    }

    /// The Now dot on the rail and the "Now" label. On the way back to Now the dot pulses once (`NowPulse`): it swells and a
    /// 2 pt ring spreads from it and fades. At rest there is no ring.
    @ViewBuilder private func nowMarker(at y: CGFloat) -> some View {
        NowDot(motion: motion, size: Self.nowDot, ring: Self.railWidth)
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
    /// Each increase shakes the bell (TT-190).
    var shakes = 0
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
                // "12:47 PM" may shrink a little across, never to fit the 38 pt row: a 34 pt line is taller than the row.
                .minimumScaleFactor(Self.timeMinimumScale)
                .fixedSize(horizontal: false, vertical: true)
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

    /// "in 11 min · Platform [2]" on the next train, "Platform [2]" (or the dash pill, pulsing within 15 min of leaving when
    /// the feed posts platforms, TT-162) on the others, "Next usable below" when cancelled.
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
                // "Platform" and the pill (TT-199): the number, or the dash, which pulses within 15 min of leaving when
                // the feed posts platforms (TT-162). The 22 pt pill overhangs the 20 pt row into the gaps.
                PlatformTag(number: card.hasPlatform ? card.platformValue : nil, size: 15, pillSize: 14, pulses: card.awaitsPlatform)
                    .animation(.easeInOut(duration: 0.2), value: card.platformValue)
            }
            .lineLimit(1)
            .fixedSize()
        }
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

    /// One tap arms a This-trip alert and fills the bell; another turns it off (TT-141), with the pop (TT-166). The bell's
    /// faces and its shake on a refusal (TT-190); taps while it waits do nothing (`AlertBellModel`).
    private var bellButton: some View {
        let label = bell == .on ? String(localized: "alert.bell.label_on") : String(localized: "alert.bell.label")
        return AlertBellButton(
            face: bell,
            shakes: shakes,
            label: Text(verbatim: String(format: label, card.trainName)),
            glyph: Self.bellGlyph,
            target: Self.bellTarget,
            action: onBell
        )
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

/// The Now dot, pulsing from the clock's `pulseStart`. A view of its own, so a pulse redraws the dot alone.
private struct NowDot: View {
    let motion: ScheduleMotionClock?
    let size: CGFloat
    let ring: CGFloat

    var body: some View {
        let start = motion?.pulseStart
        TimelineView(.animation(paused: start == nil)) { context in
            let pose = start.map { NowPulse.pose(at: context.date.timeIntervalSince($0)) } ?? NowPulse.rest
            ZStack {
                if pose.ringOpacity > 0 {
                    Circle()
                        .strokeBorder(TTColor.accent, lineWidth: ring)
                        .frame(width: size + 2 * ring, height: size + 2 * ring)
                        .scaleEffect(pose.ringScale)
                        .opacity(pose.ringOpacity)
                }
                Circle()
                    .fill(TTColor.accent)
                    .frame(width: size, height: size)
                    .scaleEffect(pose.dotScale)
            }
        }
    }
}
