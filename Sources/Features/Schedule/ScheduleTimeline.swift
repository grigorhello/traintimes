import SwiftUI

/// The to-scale timeline (TT-113): rail, gridlines, Now line, markers and cards, placed by the TT-111 layout. The left column
/// holds the gridline times only, never a train's own time, which its card shows (D49). Across, it follows the canvas `.tl`
/// geometry: labels end at 52 pt, the rail is centred on 62 pt and cards start at 82 pt. Everything but the cards is
/// decoration and hidden from assistive tech. A new set of trains cascades in, each card with its rail marks, and the Now line
/// plays when the timeline shows (TT-164, D61; TT-197, D80). The train marks are neutral, so the Now line is the only green
/// line on the rail (D80).
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
    /// A train leaving at the minute tick (TT-203, D86), at rest unless one has just left.
    var departure: DepartureCue = .rest
    /// When the Now line's play started, read by the Now line, dot and label alone; nil draws them at rest.
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
    /// The card column starts where the 14 pt connector from the 12 pt marker ends.
    private static let cardX = railX + markerSize / 2 + TTTimeline.connectorLength
    /// A departed train's small solid dot (TT-203, D86).
    private static let departedDot: CGFloat = 6
    /// A departed train's line starts under its dot and runs on under the pressed-back card, which is opaque.
    private static let departedConnector = markerSize / 2 + TTTimeline.connectorLength + TTSpace.s2

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
                DeparturePlaying(cue: departure, involved: departure.moves(card.id)) { elapsed, reduceMotion in
                    let pose = cardPose(card, at: elapsed, reduceMotion: reduceMotion)
                    DepartureCardView(
                        card: card, bell: bell(card.id), shakes: shakes(card.id), pose: pose, onOpen: { onOpen(card.id) },
                        onBell: { onBell(card.id) }
                    ) { size in
                        viewModel.setCardSize(size, for: card.id)
                    }
                    .scaleEffect(pose.scale)
                    .offset(y: pose.offsetY)
                    .opacity(pose.opacity)
                }
                .cascadeEntrance(cascade, order: orders[card.id] ?? 0, moves: !viewModel.isPastDay)
                .padding(.leading, Self.cardX)
                .padding(.trailing, TTSpace.s5)
                .offset(y: place.top)
            }
        }
    }

    /// A card's pose in a departure's play, or at rest.
    private func cardPose(_ card: DepartureCard, at elapsed: Double?, reduceMotion: Bool) -> DeparturePlay.Card {
        guard let elapsed else { return .rest(departed: card.isDeparted) }
        if departure.departing.contains(card.id) {
            return DeparturePlay.departing(at: elapsed, wasLead: departure.lead == card.id, reduceMotion: reduceMotion)
        }
        if departure.next == card.id { return DeparturePlay.next(at: elapsed, reduceMotion: reduceMotion) }
        return .rest(departed: card.isDeparted)
    }

    /// A departing train's ring in the play, or at rest.
    private func railPose(_ card: DepartureCard, at elapsed: Double?, reduceMotion: Bool) -> DeparturePlay.Rail {
        guard let elapsed, departure.departing.contains(card.id) else { return DeparturePlay.Rail() }
        return DeparturePlay.rail(at: elapsed, reduceMotion: reduceMotion)
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

    /// 2 pt line from each marker to its card, in the marker's colour: ink-tertiary, cancel-ink for a cancelled train. The next
    /// train's line carries a glint that runs from the rail into its card, over and over (D80).
    private func connectors(
        _ cards: [DepartureCard], _ places: [TripKey: TimelineLayout.Card], _ orders: [TripKey: Int]
    ) -> some View {
        ForEach(cards) { card in
            if let place = places[card.id] {
                DeparturePlaying(cue: departure, involved: departure.moves(card.id)) { elapsed, reduceMotion in
                    let rail = railPose(card, at: elapsed, reduceMotion: reduceMotion)
                    // The glint leaves the departing train at the tick and starts on the next one a moment later (D86).
                    let holdsGlint = elapsed.map { departure.next == card.id && $0 < DeparturePlay.glintDelay } ?? false
                    // The departing lead keeps its glint until its card starts to move.
                    let keepsGlint = elapsed.map { departure.lead == card.id && $0 <= DeparturePlay.delay } ?? false
                    NextGlintLine(
                        colour: card.isCancelled ? TTColor.cancelInk : TTColor.inkTertiary,
                        glints: (card.isNext || keepsGlint) && !card.isCancelled && !holdsGlint
                    )
                    .frame(width: card.isDeparted ? Self.departedConnector : TTTimeline.connectorLength, height: Self.railWidth)
                    .offset(y: rail.offsetY)
                    .opacity(rail.opacity)
                }
                .cascadeEntrance(cascade, order: orders[card.id] ?? 0, moves: false)
                .offset(x: card.isDeparted ? Self.railX : Self.railX + Self.markerSize / 2, y: place.railY - Self.railWidth / 2)
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
                DeparturePlaying(cue: departure, involved: departure.departing.contains(card.id)) { elapsed, reduceMotion in
                    let rail = railPose(card, at: elapsed, reduceMotion: reduceMotion)
                    marker(for: card, fill: rail.fill)
                        .offset(y: rail.offsetY)
                        .opacity(rail.opacity)
                }
                .cascadeEntrance(cascade, order: orders[card.id] ?? 0, moves: false)
                .centred(x: Self.railX, y: place.railY)
            }
        }
    }

    /// A 16 pt red x for a cancelled train or skipped stop; a 12 pt ink-tertiary ring for every other train, the next one too
    /// (its line's glint marks it). None is green, so nothing on the rail reads as the Now line (D80). A departed train's
    /// ring is a 6 pt solid dot; `fill` runs from the ring (0) to the dot (1) as it leaves (D86).
    @ViewBuilder private func marker(for card: DepartureCard, fill: CGFloat) -> some View {
        if card.isCancelled {
            Image(systemName: card.status.symbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(TTColor.cancelInk)
                .frame(width: Self.leadMarkerSize, height: Self.leadMarkerSize)
                .background(TTColor.canvas, in: Circle())
        } else if card.isDeparted {
            let size = Self.departedDot + (Self.markerSize - Self.departedDot) * (1 - fill)
            Circle()
                .fill(TTColor.surface)
                .overlay(Circle().fill(TTColor.inkTertiary).opacity(fill))
                .overlay(Circle().strokeBorder(TTColor.inkTertiary, lineWidth: Self.railWidth))
                .frame(width: size, height: size)
        } else {
            ring(TTColor.inkTertiary)
        }
    }

    /// A 12 pt hollow marker: ink-tertiary for a train, amber at a delayed train's scheduled time.
    private func ring(_ colour: Color) -> some View {
        Circle()
            .fill(TTColor.surface)
            .overlay(Circle().strokeBorder(colour, lineWidth: Self.railWidth))
            .frame(width: Self.markerSize, height: Self.markerSize)
    }

    /// The 2 pt accent line across the timeline, under the cards (a dot on the rail and "Now" in the label column mark it).
    /// When Now plays it draws across from the rail.
    private func nowRule(at y: CGFloat) -> some View {
        NowPulsing(motion: motion, departure: departure) { pose in
            Rectangle()
                .fill(TTColor.accent)
                .frame(height: Self.railWidth)
                .scaleEffect(x: pose.ruleReveal, y: 1, anchor: .leading)
                .opacity(pose.opacity)
                .offset(y: pose.offsetY)
        }
        .padding(.leading, Self.railX)
        .padding(.trailing, TTSpace.s5)
        .centred(y: y)
    }

    /// The Now dot on the rail and the "Now" label. When Now plays (`NowPulse`) the dot swells, two 2 pt rings spread from
    /// it and fade, and the label pops. At rest there is no ring.
    @ViewBuilder private func nowMarker(at y: CGFloat) -> some View {
        NowDot(motion: motion, departure: departure, size: Self.nowDot, ring: Self.railWidth)
            .centred(x: Self.railX, y: y)
        NowPulsing(motion: motion, departure: departure) { pose in
            Text("button.now")
                .font(TTFont.footnote.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(TTColor.accent)
                .scaleEffect(pose.labelScale, anchor: .trailing)
                .opacity(pose.opacity)
                .offset(y: pose.offsetY)
        }
        .frame(width: Self.labelColumn, alignment: .trailing)
        .centred(y: y)
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
    /// The card's look in a departure's play (TT-203, D86); nil draws it at rest. Scale and offset are the timeline's.
    var pose: DeparturePlay.Card?
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

    private var look: DeparturePlay.Card { pose ?? .rest(departed: card.isDeparted) }

    var body: some View {
        Card(padding: 0, flatness: look.look) {
            VStack(alignment: .leading, spacing: Self.rowGap) {
                timeRow
                    .departedLook(look.look)
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
                .departedLook(look.look)
                HStack(spacing: TTSpace.s2) {
                    status
                    Spacer(minLength: 0)
                    arrival
                        .departedLook(look.look)
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
                    .departedLook(look.look)
                    .padding(.top, Self.bellTop)
            }
        }
    }

    /// The status line; a departed train's cross-fades to the grey dot and "Departed", kept at full ink-secondary so it
    /// reads (D86). A cancelled train keeps "Cancelled".
    @ViewBuilder private var status: some View {
        if card.shownStatus != card.status {
            ZStack(alignment: .leading) {
                StatusLine(status: card.status).opacity(look.statusOut)
                StatusLine(status: card.shownStatus).opacity(look.statusIn)
            }
        } else {
            StatusLine(status: card.status)
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
        // The bolt grows with the time, so it keeps its place beside it while the time changes size (D86).
        .scaleEffect(look.timeScale, anchor: .leading)
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
                // "Platform" and the pill first (TT-199, Grigor: "Platform 2 · in 11 min"): the number, or the dash, which
                // pulses within 15 min of leaving when the feed posts platforms (TT-162). The 22 pt pill overhangs the
                // 20 pt row into the gaps.
                PlatformTag(number: card.hasPlatform ? card.platformValue : nil, size: 15, pillSize: 14, pulses: card.awaitsPlatform)
                    .animation(.easeInOut(duration: 0.2), value: card.platformValue)
                // A departing lead keeps its "Departing" until the play fades it (D86).
                if let relative = card.relativeTime ?? (look.leadOut > 0 ? String(localized: "schedule.departing") : nil) {
                    let opacity = card.relativeTime == nil ? look.leadOut : look.countdown
                    // A separator glyph, not copy.
                    Text(verbatim: "·")
                        .font(TTFont.subhead)
                        .foregroundStyle(TTColor.inkTertiary)
                        .opacity(opacity)
                    Text(relative)
                        .font(TTFont.subhead.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(TTColor.ink)
                        .opacity(opacity)
                }
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
    /// A departed card's content (D86): half opacity and no colour at `look` 1.
    func departedLook(_ look: CGFloat) -> some View {
        opacity(1 - 0.5 * look).saturation(1 - look)
    }

    /// Centres the view on a point of the timeline whatever its size: on `y`, and on `x` when given.
    func centred(x: CGFloat? = nil, y: CGFloat) -> some View {
        frame(width: x == nil ? nil : 0, height: 0)
            .offset(x: x ?? 0, y: y)
    }
}

/// Draws `content` in the Now line's pose, from the clock's `pulseStart`: a view of its own, so a play redraws the Now
/// line, dot and label alone, and paused (no frames) at rest.
private struct NowPulsing<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let motion: ScheduleMotionClock?
    /// A departure's play glides the line onto the departing ring and draws the rule out (TT-203); it wins over the pulse.
    var departure: DepartureCue = .rest
    @ViewBuilder let content: (NowPulse.Pose) -> Content

    var body: some View {
        let start = motion?.pulseStart
        let run = departure.run
        TimelineView(.animation(paused: start == nil && run.start == nil)) { context in
            if let elapsed = run.elapsed(at: context.date), elapsed < DeparturePlay.duration {
                content(DeparturePlay.now(at: elapsed, glide: departure.glide, reduceMotion: reduceMotion))
            } else {
                let elapsed = start.map { context.date.timeIntervalSince($0) }
                content(elapsed.map { NowPulse.pose(at: $0, reduceMotion: reduceMotion) } ?? NowPulse.rest)
            }
        }
    }
}

/// Draws `content` from a departure's play (TT-203, D86): the seconds since it started, or nil at rest. Only a view the play
/// moves (`involved`) reads the clock, so its start and end redraw those views alone.
private struct DeparturePlaying<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cue: DepartureCue
    let involved: Bool
    @ViewBuilder let content: (Double?, Bool) -> Content

    var body: some View {
        let run = involved ? cue.run : .rest
        TimelineView(.animation(paused: run.start == nil)) { context in
            content(run.elapsed(at: context.date), reduceMotion)
        }
    }
}

/// A train's 2 pt line to its card. On the next train a short ink glint runs along it from the rail into the card every
/// 1.6 s, for as long as it is the next train (D80); without Schedule motion (snapshots) or under Reduce Motion the line is
/// plain ink instead, so the next train still stands out.
private struct NextGlintLine: View {
    @Environment(\.playsScheduleMotion) private var playsMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let colour: Color
    let glints: Bool

    static let period = 1.6
    /// The glint crosses the line in the first part of each period, then the line rests.
    static let travel = 0.9
    static let glintLength: CGFloat = 8

    var body: some View {
        if glints, playsMotion, !reduceMotion {
            TimelineView(.animation) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.travel
                GeometryReader { proxy in
                    let width = proxy.size.width
                    Rectangle().fill(colour)
                        .overlay(alignment: .leading) {
                            if phase < 1 {
                                LinearGradient(colors: [TTColor.ink.opacity(0), TTColor.ink, TTColor.ink.opacity(0)], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: Self.glintLength)
                                    .offset(x: -Self.glintLength + (width + Self.glintLength) * UnitCurve.easeInOut.value(at: phase))
                            }
                        }
                        .clipped()
                }
            }
        } else {
            Rectangle().fill(glints ? TTColor.ink : colour)
        }
    }
}

/// The Now dot and its two rings.
private struct NowDot: View {
    let motion: ScheduleMotionClock?
    var departure: DepartureCue = .rest
    let size: CGFloat
    let ring: CGFloat

    var body: some View {
        NowPulsing(motion: motion, departure: departure) { pose in
            ZStack {
                ringView(scale: pose.ringScale, opacity: pose.ringOpacity)
                ringView(scale: pose.echoScale, opacity: pose.echoOpacity)
                Circle()
                    .fill(TTColor.accent)
                    .frame(width: size, height: size)
                    .scaleEffect(pose.dotScale)
            }
            .opacity(pose.opacity)
            .offset(y: pose.offsetY)
        }
    }

    @ViewBuilder private func ringView(scale: CGFloat, opacity: Double) -> some View {
        if opacity > 0 {
            Circle()
                .strokeBorder(TTColor.accent, lineWidth: ring)
                .frame(width: size + 2 * ring, height: size + 2 * ring)
                .scaleEffect(scale)
                .opacity(opacity)
        }
    }
}
