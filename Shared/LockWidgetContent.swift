import Foundation

// What Next train writes on the Lock Screen (TT-184, D114): the rectangular, circular and inline sizes of the same entry,
// as words, times and links, made here so the rules are unit tested and the views only lay them out. Every tap opens
// Schedule on the widget's route. Times come from the one formatter with the file's Time format (D17).

/// The rules the three Lock Screen sizes share.
enum LockWidget {
    /// From 30 min before an alerted train its Live Activity shows it (TT-178, D74), so the Lock Screen sizes go back to
    /// the next train and never show the same train twice. The Home Screen keeps Your train until it leaves.
    static let handOverLead: TimeInterval = 30 * 60
    /// The circular's ring empties over the 30 min before the departure; it is full before that.
    static let ringSpan: TimeInterval = 30 * 60
    /// The circular writes the minutes from 60 min before the departure; earlier, the clock time.
    static let minutesLead: TimeInterval = 60 * 60
}

/// The glyph the circular and inline sizes lead with: the train, or the bell while they show Your train.
enum LockWidgetGlyph: Equatable, Sendable {
    case train, bell

    var symbol: String {
        switch self {
        case .train: "tram.fill"
        case .bell: "bell.fill"
        }
    }
}

/// The train a Lock Screen size shows, with the entry's trains around it.
struct LockWidgetTrain: Equatable, Sendable {
    let train: WidgetEntry.Train
    /// The alerted train, from 2 h to 30 min before it leaves.
    let isYourTrain: Bool
    let index: Int
    let trains: WidgetEntry.Trains
}

extension WidgetEntry {
    /// The Lock Screen's train: Your train until 30 min before it leaves, else the next train; nil with no train to show.
    var lockTrain: LockWidgetTrain? {
        guard case .trains(let trains) = state, let next = trains.trains.first else { return nil }
        if let yours = trains.yourTrain, trains.trains.indices.contains(yours),
           trains.trains[yours].departure.timeIntervalSince(date) > LockWidget.handOverLead {
            return LockWidgetTrain(train: trains.trains[yours], isYourTrain: true, index: yours, trains: trains)
        }
        return LockWidgetTrain(train: next, isYourTrain: false, index: 0, trains: trains)
    }
}

// MARK: - Rectangular

/// Rectangular: the route, the train's time, and its countdown with the train after it.
struct LockRectangularContent: Equatable, Sendable {
    let body: Body
    /// The whole widget's tap: Schedule on the route at Now.
    let link: URL

    enum Body: Equatable, Sendable {
        case train(Train)
        /// After the last train, and a day with none: "No trains tonight" over the next train.
        case noTrains(NoTrains)
        /// Not loaded, no route, out of date: the message's two lines.
        case message(WidgetMessage)
    }

    enum Header: Equatable, Sendable {
        /// "Oakville → Union".
        case route(from: String, to: String)
        /// The bell and "Your train · Union".
        case yourTrain(to: String)
    }

    struct Train: Equatable, Sendable {
        let header: Header
        let time: WidgetClock
        let isExpress: Bool
        /// "in 5 min · then 8:28", "in 41 min · earlier 7:58", "Last train · in 32 min", "now · then 8:28".
        let note: WidgetText
        /// The bell after the note: the train named there is the alerted one.
        let thenIsAlerted: Bool
    }

    struct NoTrains: Equatable, Sendable {
        let from: String
        let to: String
        /// "tonight" once the last train left after 6 PM, else "today".
        let when: String
        /// "First train 5:43 AM" or "Next Mon 6:10 AM"; nil when the file has no later train.
        let note: WidgetText?
    }

    init(_ entry: WidgetEntry) {
        let formatter = TimeFormatter(format: entry.timeFormat)
        link = entry.routeLink(from: .lockRectangular)
        let names = entry.header.map(WidgetHeaderContent.init)
        if let shown = entry.lockTrain, let names {
            let (note, thenIsAlerted) = Self.note(shown, in: entry, formatter: formatter)
            body = .train(
                Train(
                    header: shown.isYourTrain ? .yourTrain(to: names.to) : .route(from: names.from, to: names.to),
                    time: WidgetClock(shown.train.departure, formatter: formatter), isExpress: shown.train.isExpress, note: note,
                    thenIsAlerted: thenIsAlerted
                )
            )
            return
        }
        let message = WidgetMessage(entry, formatter: formatter, addsArrival: false)
            ?? WidgetMessage(title: String(localized: "widget.not_loaded.title"), detail: nil)
        switch entry.state {
        case .noMoreTrainsTonight(_, let since, _):
            let isEvening = ServiceDay.minutesIntoServiceDay(since) >= WidgetMessage.tonightHour * 60
            let when = String(localized: isEvening ? "widget.lock.tonight" : "widget.lock.today")
            body = .noTrains(NoTrains(from: names?.from ?? "", to: names?.to ?? "", when: when, note: message.detail))
        case .noTrainsToday:
            body = .noTrains(
                NoTrains(from: names?.from ?? "", to: names?.to ?? "", when: String(localized: "widget.lock.today"), note: message.detail)
            )
        case .notLoaded, .noRoute, .outOfDate, .trains:
            body = .message(message)
        }
    }

    /// The third row: the countdown ("now" in the last minute, "Last train" before it from 10 PM), then the train after
    /// on the same service day, or the earlier one under Your train.
    private static func note(
        _ shown: LockWidgetTrain, in entry: WidgetEntry, formatter: any TimeFormatting
    ) -> (WidgetText, Bool) {
        let trains = shown.trains
        var lead = entry.isLeaving(shown.train)
            ? String(localized: "widget.now")
            : String(format: String(localized: "widget.lock.in"), WidgetCountdown.minutes(from: entry.date, to: shown.train.departure))
        if trains.lastTrain == shown.index {
            return (WidgetText("\(String(localized: "widget.last_train")) · \(lead)"), false)
        }
        var tail: WidgetText?
        var thenIsAlerted = false
        if shown.isYourTrain, let earlier = trains.earlier, earlier != shown.index, trains.trains.indices.contains(earlier) {
            tail = WidgetText(
                format: String(localized: "widget.lock.earlier"), strong: formatter.railTime(trains.trains[earlier].departure)
            )
        } else if trains.trains.indices.contains(shown.index + 1) {
            let then = trains.trains[shown.index + 1]
            if then.key.serviceDay == shown.train.key.serviceDay {
                tail = WidgetText(format: String(localized: "widget.lock.then"), strong: formatter.railTime(then.departure))
                thenIsAlerted = then.isAlerted
            }
        }
        guard let tail else { return (WidgetText(lead), false) }
        lead += " · "
        return (WidgetText(pieces: [WidgetText.Piece(text: lead, isStrong: false)] + tail.pieces), thenIsAlerted)
    }
}

// MARK: - Circular

/// Circular: the minutes to the train inside a ring that empties over its last 30 min.
struct LockCircularContent: Equatable, Sendable {
    let glyph: LockWidgetGlyph
    /// "5" (the minutes, from 60 min before), "now" in the last minute, "8:06" (the clock time) before that and for the
    /// next day's first train; nil draws the glyph alone.
    let value: String?
    /// "min" under the minutes, the clock time under "now".
    let caption: String?
    /// How much of the ring is left at the entry's moment: 1 until 30 min before the departure, 0 in the last minute; nil
    /// draws no ring (no train today).
    let ring: Double?
    /// The 30 min the ring empties over, ending at the departure.
    let ringInterval: ClosedRange<Date>?
    let link: URL

    init(_ entry: WidgetEntry) {
        let formatter = TimeFormatter(format: entry.timeFormat)
        link = entry.routeLink(from: .lockCircular)
        guard let shown = entry.lockTrain else {
            glyph = .train
            caption = nil
            ring = nil
            ringInterval = nil
            switch entry.state {
            case .noMoreTrainsTonight(_, _, let next), .noTrainsToday(_, let next):
                value = next.map { formatter.railTime($0.departure) }
            case .notLoaded, .noRoute, .outOfDate, .trains:
                value = nil
            }
            return
        }
        let departure = shown.train.departure
        let lead = departure.timeIntervalSince(entry.date)
        glyph = shown.isYourTrain ? .bell : .train
        ringInterval = departure.addingTimeInterval(-LockWidget.ringSpan)...departure
        if entry.isLeaving(shown.train) {
            value = String(localized: "widget.now")
            caption = formatter.railTime(departure)
            ring = 0
        } else if lead <= LockWidget.minutesLead {
            value = String(max(0, Int(lead / 60)))
            caption = String(localized: "widget.lock.min")
            ring = min(1, lead / LockWidget.ringSpan)
        } else {
            value = formatter.railTime(departure)
            caption = nil
            ring = 1
        }
    }
}

// MARK: - Inline

/// Inline, beside the date: the train's clock time and where it goes, never a countdown.
struct LockInlineContent: Equatable, Sendable {
    let glyph: LockWidgetGlyph
    /// "8:06 AM to Union"; with no train, "First train 5:43 AM", "Next Mon 6:10 AM" or the message's first line.
    let text: String
    /// "8:06 AM", for a line too short for the destination; nil when there is nothing shorter.
    let short: String?
    let link: URL

    init(_ entry: WidgetEntry) {
        let formatter = TimeFormatter(format: entry.timeFormat)
        link = entry.routeLink(from: .lockInline)
        if let shown = entry.lockTrain, let header = entry.header {
            let time = formatter.time(shown.train.departure)
            glyph = shown.isYourTrain ? .bell : .train
            text = String(format: String(localized: "widget.lock.inline"), time, StationNames.short(header.to.name))
            short = time
            return
        }
        glyph = .train
        short = nil
        let message = WidgetMessage(entry, formatter: formatter, addsArrival: false)
        let title = message?.title ?? String(localized: "widget.not_loaded.title")
        switch entry.state {
        case .noMoreTrainsTonight, .noTrainsToday:
            text = message?.detail?.plain ?? title
        case .notLoaded, .noRoute, .outOfDate, .trains:
            text = title
        }
    }
}
