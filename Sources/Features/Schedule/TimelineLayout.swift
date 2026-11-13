import CoreGraphics
import Foundation

/// The measured size of one timeline card. TT-113 measures the cards; the engine only places them.
struct TimelineCardSize: Hashable, Sendable {
    var height: CGFloat
    /// From the card's top to the centre of its departure time line, which is centred on the marker.
    var anchor: CGFloat

    /// Every card (D50): 14 pt padding, a 38 pt time row, a 20 pt and a 24 pt row 4 pt apart, 14 pt padding.
    static let standard = TimelineCardSize(height: 118, anchor: 33)
}

/// Everything the timeline layout reads. The same input always gives the same layout.
struct TimelineInput: Hashable, Sendable {
    var departures: [Departure]
    /// The device clock on today's timeline. Nil on any other day: no Now line, and the timeline starts at the first train.
    var now: Date?
    /// `TTTimeline.pointsPerMinute`, or `TTTimeline.pointsPerMinuteCompact` on a compact phone.
    var pointsPerMinute: CGFloat = TTTimeline.pointsPerMinute
    /// Measured card sizes by trip. A card that has not been measured yet uses `TimelineCardSize.standard`.
    var cardSizes: [TripKey: TimelineCardSize] = [:]
}

/// Where everything on the to-scale timeline goes (requirements § Schedule screen, Timeline geometry), in points from the
/// top of the scroll content. Pure maths with no views, so it can be recomputed on every refresh; cards keep their trip key
/// as identity, so a refresh does not reset the scroll position.
struct TimelineLayout: Hashable, Sendable {
    struct Card: Hashable, Sendable, Identifiable {
        let id: TripKey
        /// The train's place on the rail: the expected departure, else the scheduled one.
        let markerY: CGFloat
        let top: CGFloat
        let bottom: CGFloat
        /// Delayed train only: the hollow marker at the scheduled time. None once the train has left.
        let scheduledMarkerY: CGFloat?
        /// Departed on Today (TT-203, D86): the card is drawn `TTTimeline.departedLift` above its timetable place, so
        /// departed cards stack above the Now line and never cover it.
        var isSteppedUp = false

        /// Where the marker and the connector are drawn: the train's place, or for a stepped-up card
        /// `TTTimeline.departedRailLift` above it, level with the card's bottom row.
        var railY: CGFloat { isSteppedUp ? markerY - TTTimeline.departedRailLift : markerY }

        /// The 4 pt bar from the scheduled marker down to the expected one; its length is the delay.
        var delayBar: ClosedRange<CGFloat>? { scheduledMarkerY.map { $0...markerY } }
    }

    struct Gridline: Hashable, Sendable {
        let time: Date
        let y: CGFloat
    }

    /// A gap over 30 min between two markers, folded to 30 min of rail.
    struct Fold: Hashable, Sendable {
        /// The dashed part of the rail.
        let dashed: ClosedRange<CGFloat>
        /// The centre of the fold pill.
        let pillY: CGFloat
        /// The real length of the gap.
        let minutes: Int
        /// The departure of the next usable train after the gap; cancelled trains are skipped. Nil when no usable
        /// train follows, and then the fold has no pill.
        let next: Date?

        /// "No trains for 48 min · next 6:40 PM".
        func label(_ formatter: some TimeFormatting) -> String? {
            next.map { String(format: String(localized: "schedule.no_trains_gap"), minutes, formatter.time($0)) }
        }
    }

    /// In departure order.
    var cards: [Card] = []
    var gridlines: [Gridline] = []
    var folds: [Fold] = []
    var nowY: CGFloat?
    /// The line after the last train of the service day.
    var endOfServiceY: CGFloat = 0
    var height: CGFloat = 0
    /// Puts Now about 5 min below the top edge; 0 on another day, where the timeline starts at the first train.
    var initialScrollOffset: CGFloat = 0
}

extension TimelineLayout {
    /// The first card's marker keeps this much room above it, as its old time pill did (22 pt tall, centred on the marker).
    private static let markerRoom: CGFloat = 22
    /// A fold's pill: one 13 pt footnote line with 3 pt above and below.
    private static let foldPillHeight: CGFloat = 22

    init(_ input: TimelineInput) {
        let departures = input.departures.sorted {
            ($0.departureTime, $0.trip.key.tripId) < ($1.departureTime, $1.trip.key.tripId)
        }
        guard let first = departures.first else { return }
        let ppm = input.pointsPerMinute
        let gap = TTTimeline.minCardGap
        func size(_ index: Int) -> TimelineCardSize { input.cardSizes[departures[index].id] ?? .standard }
        /// Departed on Today: expected departure at or before now (TT-203, D86). Departures are in time order, so the
        /// stepped-up cards are the first ones and all move by the same amount: they never overlap.
        func stepsUp(_ index: Int) -> Bool { input.now.map { departures[index].departureTime <= $0 } ?? false }
        func lift(_ index: Int) -> CGFloat { stepsUp(index) ? TTTimeline.departedLift : 0 }

        // Every marker on the rail, in time order: each card's marker, plus the scheduled marker of a delayed train.
        let origin = departures.map { $0.scheduledMarker ?? $0.departureTime }.min() ?? first.departureTime
        func minutes(_ date: Date) -> Double { date.timeIntervalSince(origin) / 60 }
        var markers: [(minute: Double, card: Int, isScheduled: Bool)] = []
        for (index, departure) in departures.enumerated() {
            markers.append((minute: minutes(departure.departureTime), card: index, isScheduled: false))
            if let scheduled = departure.scheduledMarker {
                markers.append((minute: minutes(scheduled), card: index, isScheduled: true))
            }
        }
        markers.sort { ($0.minute, $0.card) < ($1.minute, $1.card) }

        // The rail is pieces between breakpoints. A piece covers fixed minutes; its length can stretch.
        let foldAfter = Double(TTTimeline.foldAfterMinutes)
        var breaks: [Double] = []
        var lengths: [CGFloat] = []
        var foldPieces: [(piece: Int, start: Double, end: Double, fromNow: Bool)] = []
        func addFold(from start: Double, to end: Double, fromNow: Bool = false) {
            // Fold: 30 min of rail. The 10 min at each end stay to scale, so the cards and the gridlines next to
            // them are true; the middle 10 min of rail stand for the rest of the gap and are dashed.
            let side = foldAfter / 3
            breaks += [start + side, end - side, end]
            lengths += Array(repeating: CGFloat(side) * ppm, count: 3)
            foldPieces.append((piece: lengths.count - 2, start: start, end: end, fromNow: fromNow))
        }
        // A wait of over 30 min from Now to the first train folds too, so the first screen is never empty rail.
        if let now = input.now.map(minutes), markers[0].minute - now > foldAfter {
            breaks = [now]
            addFold(from: now, to: markers[0].minute, fromNow: true)
        } else {
            breaks = [markers[0].minute]
        }
        var markerBreak = [breaks.count - 1]
        // A delay bar is never folded: its length is the delay.
        let delayBars = markers.filter { $0.isScheduled }.compactMap { scheduled in
            markers.first { $0.card == scheduled.card && !$0.isScheduled }.map { (scheduled.minute, $0.minute) }
        }
        for (previous, marker) in zip(markers, markers.dropFirst()) {
            let span = marker.minute - previous.minute
            let isDelayBar = delayBars.contains { $0.0 <= previous.minute && marker.minute <= $0.1 }
            if span > foldAfter && !isDelayBar {
                addFold(from: previous.minute, to: marker.minute)
            } else {
                breaks.append(marker.minute)
                lengths.append(CGFloat(span) * ppm)
            }
            markerBreak.append(breaks.count - 1)
        }
        var cardBreak = [Int](repeating: 0, count: departures.count)
        var scheduledBreak: [Int: Int] = [:]
        for (marker, point) in zip(markers, markerBreak) {
            if marker.isScheduled { scheduledBreak[marker.card] = point } else { cardBreak[marker.card] = point }
        }

        // Minimum gap: cards never come closer than 16 pt. Stretch only the pieces between the two markers, so the
        // gridlines in that segment follow the zoom and the rest of the timeline keeps its scale.
        for index in departures.indices.dropFirst() {
            let above = size(index - 1)
            let required = above.height - above.anchor + gap + size(index).anchor
            let pieces = cardBreak[index - 1]..<cardBreak[index]
            let actual = pieces.reduce(CGFloat(0)) { $0 + lengths[$1] }
            guard actual < required else { continue }
            if actual > 0 {
                for piece in pieces { lengths[piece] *= required / actual }
            } else {
                lengths[pieces.upperBound - 1] = required // trains at the same minute
            }
        }

        // A fold's pill keeps 16 pt below the card above it: a tall card (an Express row that wraps, a delay's
        // scheduled line) stretches the 10 min of rail before the dashed part rather than covering the pill.
        for fold in foldPieces where !fold.fromNow {
            guard let above = departures.indices.last(where: { cardBreak[$0] == fold.piece - 1 }) else { continue }
            let card = size(above)
            let required = card.height - card.anchor + gap + Self.foldPillHeight / 2 - lengths[fold.piece] / 2
            if lengths[fold.piece - 1] < required { lengths[fold.piece - 1] = required }
        }

        var breakY: [CGFloat] = [0]
        for length in lengths { breakY.append(breakY[breakY.count - 1] + length) }
        func rawY(_ minute: Double) -> CGFloat {
            let firstBreak = breaks[0], lastBreak = breaks[breaks.count - 1]
            if minute <= firstBreak { return breakY[0] - CGFloat(firstBreak - minute) * ppm }
            if minute >= lastBreak { return breakY[breakY.count - 1] + CGFloat(minute - lastBreak) * ppm }
            let piece = breaks.lastIndex { $0 <= minute } ?? 0
            let fraction = (minute - breaks[piece]) / (breaks[piece + 1] - breaks[piece])
            return breakY[piece] + CGFloat(fraction) * lengths[piece]
        }

        // Shift everything down so the first card and marker sit 16 pt below the top, and Now can sit 5 min below it.
        let nowOffset = CGFloat(TTTimeline.nowOffsetFromTopMinutes) * ppm
        let firstCardTop = breakY[cardBreak[0]] - size(0).anchor - lift(0)
        var top = min(firstCardTop, breakY[markerBreak[0]] - Self.markerRoom / 2) - gap
        if let now = input.now { top = min(top, rawY(minutes(now)) - nowOffset) }
        let contentTop = top
        func y(_ minute: Double) -> CGFloat { rawY(minute) - contentTop }

        cards = departures.indices.map { index in
            let markerY = breakY[cardBreak[index]] - contentTop
            let card = size(index)
            let top = markerY - card.anchor - lift(index)
            return Card(
                id: departures[index].id,
                markerY: markerY,
                top: top,
                bottom: top + card.height,
                scheduledMarkerY: stepsUp(index) ? nil : scheduledBreak[index].map { breakY[$0] - contentTop },
                isSteppedUp: stepsUp(index)
            )
        }

        folds = foldPieces.map { fold in
            let dashed = (breakY[fold.piece] - contentTop)...(breakY[fold.piece + 1] - contentTop)
            // The real gap runs between usable trains: a cancelled train at either end is left out of the label.
            let next = departures.first { $0.isUsable && minutes($0.departureTime) >= fold.end }?.departureTime
            let start = fold.fromNow ? fold.start
                : departures.last { $0.isUsable && minutes($0.departureTime) <= fold.start }.map { minutes($0.departureTime) }
                    ?? fold.start
            return Fold(
                dashed: dashed,
                pillY: (dashed.lowerBound + dashed.upperBound) / 2,
                minutes: Int(((next.map(minutes) ?? fold.end) - start).rounded()),
                next: next
            )
        }

        nowY = input.now.map { y(minutes($0)) }
        initialScrollOffset = nowY.map { max(0, $0 - nowOffset) } ?? 0
        endOfServiceY = (cards.last?.bottom ?? 0) + gap
        height = max(endOfServiceY, nowY ?? 0) + gap

        // Gridlines every 15 min of Toronto wall-clock time, from the top of the content to the end of service.
        // Toronto's UTC offset is whole hours, so 15-min steps from the reference date land on :00, :15, :30 and :45.
        // None inside a fold's dashed part, where the rail is not to scale. Every line carries its time (D49).
        let lastBreakY = breakY[breakY.count - 1] - contentTop
        let startMinute = breaks[0] - Double(breakY[0] - contentTop) / Double(ppm)
        let endMinute = breaks[breaks.count - 1] + Double(endOfServiceY - lastBreakY) / Double(ppm)
        let step = Double(TTTimeline.gridlineEveryMinutes * 60)
        let start = origin.addingTimeInterval(startMinute * 60).timeIntervalSinceReferenceDate
        var time = Date(timeIntervalSinceReferenceDate: (start / step).rounded(.up) * step)
        while minutes(time) <= endMinute {
            let minute = minutes(time)
            let isFolded = foldPieces.contains { breaks[$0.piece] < minute && minute < breaks[$0.piece + 1] }
            if !isFolded {
                gridlines.append(Gridline(time: time, y: y(minute)))
            }
            time = time.addingTimeInterval(step)
        }
    }

    /// Each card's place in the cascade when a new set of trains is shown (TT-164, D61), counted from the first card in view
    /// with the timeline scrolled to `scrollOffset` (where it opens: Now on today, the first train on another day). The
    /// cards above count as the first, so the stagger starts where the rider looks.
    func cascadeOrder(scrolledTo scrollOffset: CGFloat) -> [TripKey: Int] {
        let first = cards.firstIndex { $0.bottom > scrollOffset } ?? 0
        return Dictionary(cards.enumerated().map { ($0.element.id, max(0, $0.offset - first)) }, uniquingKeysWith: { kept, _ in kept })
    }
}

extension Departure {
    /// Cancelled trains and skipped stops are never usable: never the next train, and left out of fold labels.
    var isUsable: Bool {
        switch status {
        case .cancelled, .stopSkipped: false
        default: true
        }
    }

    /// A delayed train keeps a hollow marker and a struck pill at its scheduled time; its card moves to the expected time.
    var scheduledMarker: Date? {
        guard case .delayed = status, let expected = expectedDeparture, expected > trip.scheduledDeparture else { return nil }
        return trip.scheduledDeparture
    }
}
