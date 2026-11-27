import Foundation

// What the Home Screen widgets write (TT-183): each widget's entry as words, times and links, made here so the rules are
// unit tested and the views only lay them out. Times come from the one formatter with the file's Time format (D17).

/// A time as the widgets draw it: the digits, with AM or PM apart so it can be smaller (Next train) or left out (Departures).
struct WidgetClock: Equatable, Sendable {
    /// "7:58", or "07:58" on the 24-hour clock.
    let digits: String
    /// "AM" or "PM"; nil on the 24-hour clock.
    let period: String?

    init(_ date: Date, formatter: any TimeFormatting) {
        let parts = formatter.time(date).split(separator: " ", maxSplits: 1).map(String.init)
        digits = parts.first ?? ""
        period = parts.count > 1 ? parts[1] : nil
    }

    /// "7:58 AM".
    var full: String { period.map { "\(digits) \($0)" } ?? digits }
}

/// A line of a widget's message, its time strong: "First train " and "5:43 AM".
struct WidgetText: Equatable, Sendable {
    struct Piece: Equatable, Sendable {
        let text: String
        let isStrong: Bool
    }

    let pieces: [Piece]

    var plain: String { pieces.map(\.text).joined() }

    init(_ text: String) {
        pieces = [Piece(text: text, isStrong: false)]
    }

    init(pieces: [Piece]) {
        self.pieces = pieces
    }

    /// A localized format with its first value strong and the rest plain: "First train tomorrow %1$@, arrives %2$@".
    init(format: String, strong: String, _ rest: String...) {
        let mark = "\u{1}"
        let values = ([mark + strong + mark] + rest).map { $0 as any CVarArg }
        let parts = String(format: format, arguments: values).components(separatedBy: mark)
        pieces = parts.enumerated().compactMap { index, part in
            part.isEmpty ? nil : Piece(text: part, isStrong: index % 2 == 1)
        }
    }
}

/// The header both widgets share: the line's tile and the stations by the names a widget has room for.
struct WidgetHeaderContent: Equatable, Sendable {
    let line: Line?
    let from: String
    let to: String

    init(_ header: WidgetEntry.Header) {
        line = header.line.map { Line(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
        from = StationNames.short(header.from.name)
        to = StationNames.short(header.to.name)
    }
}

/// A state with no train to show: its two lines.
struct WidgetMessage: Equatable, Sendable {
    let title: String
    let detail: WidgetText?

    /// "No more trains today" when the last train left before 6 PM, "tonight" after.
    static let tonightHour = 18

    /// The message for an entry with no trains; nil while it has some. Departures adds when the first train arrives.
    init?(_ entry: WidgetEntry, formatter: any TimeFormatting, addsArrival: Bool) {
        switch entry.state {
        case .trains:
            return nil
        case .notLoaded:
            title = String(localized: "widget.not_loaded.title")
            detail = WidgetText(String(localized: "widget.not_loaded.body"))
        case .noRoute:
            title = String(localized: "widget.no_route.title")
            detail = WidgetText(String(localized: "widget.no_route.body"))
        case .outOfDate:
            title = String(localized: "widget.out_of_date.title")
            detail = WidgetText(String(localized: "widget.out_of_date.body"))
        case .noMoreTrainsTonight(_, let since, let next):
            let isEvening = ServiceDay.minutesIntoServiceDay(since) >= Self.tonightHour * 60
            title = String(localized: isEvening ? "widget.none_tonight.title" : "widget.none_today.title")
            detail = next.map { Self.firstTrain($0, after: entry.date, formatter: formatter, addsArrival: addsArrival) }
        case .noTrainsToday(_, let next):
            title = String(localized: "widget.no_trains.title")
            detail = next.map { train in
                let time = Self.unbroken("\(train.key.serviceDay.weekdayShort) \(formatter.time(train.departure))")
                return WidgetText(format: String(localized: "widget.no_trains.body"), strong: time)
            }
        }
    }

    /// A time with no-break spaces, so a line never ends between "5:43" and "AM" or "Mon" and its time; with the one after
    /// "arrives" in the strings, a line that wraps breaks before "arrives".
    private static func unbroken(_ time: String) -> String {
        time.replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    /// "First train 5:43 AM" (a later day's with its weekday); Departures: "First train tomorrow 5:43 AM, arrives 6:21 AM".
    private static func firstTrain(
        _ train: WidgetEntry.Train, after date: Date, formatter: any TimeFormatting, addsArrival: Bool
    ) -> WidgetText {
        let isTomorrow = train.key.serviceDay == ServiceDay(containing: date).adding(days: 1)
        let time = unbroken(formatter.time(train.departure))
        let dayAndTime = isTomorrow ? time : unbroken("\(train.key.serviceDay.weekdayShort) \(time)")
        guard addsArrival else {
            return WidgetText(format: String(localized: "widget.first_train"), strong: dayAndTime)
        }
        let arrival = unbroken(formatter.time(train.arrival))
        return isTomorrow
            ? WidgetText(format: String(localized: "widget.first_train_tomorrow"), strong: time, arrival)
            : WidgetText(format: String(localized: "widget.first_train_arrives"), strong: dayAndTime, arrival)
    }
}

extension WidgetEntry {
    /// The header, in the states that know the route.
    var header: Header? {
        switch state {
        case .notLoaded, .noRoute: nil
        case .outOfDate(let header), .noMoreTrainsTonight(let header, _, _), .noTrainsToday(let header, _): header
        case .trains(let trains): trains.header
        }
    }

    /// Schedule on the widget's route at Now; with no route, the Schedule tab.
    func routeLink(from widget: WidgetKind) -> URL {
        WidgetLink.tagged(header?.link ?? WidgetLink.route(nil), from: widget)
    }

    /// The departure is a minute away or less: the countdown reads "now".
    func isLeaving(_ train: Train) -> Bool {
        train.departure.timeIntervalSince(date) <= WidgetEntryBuilder.leavingLead
    }
}

/// Next train, small: one train in the big slot, the countdown under it and one footer line.
struct NextTrainContent: Equatable, Sendable {
    let header: WidgetHeaderContent?
    let body: Body
    /// The whole widget's tap: the big slot's train in Trip details, else Schedule on the route.
    let link: URL

    enum Body: Equatable, Sendable {
        case train(Train)
        case message(WidgetMessage)
    }

    struct Train: Equatable, Sendable {
        /// The alerted train from 2 h before it: "Your train" with the bell above the time.
        let isYourTrain: Bool
        let time: WidgetClock
        let isExpress: Bool
        /// The countdown's end.
        let departure: Date
        /// "11 min", at the entry's moment.
        let countdown: String
        /// The last minute: "now" in the countdown's place.
        let isLeavingNow: Bool
        /// The day's last train from 10 PM: "Last train · " before the countdown.
        let isLastTrain: Bool
        let footer: Footer?
    }

    struct Footer: Equatable, Sendable {
        enum Label: Equatable, Sendable {
            /// The train after the big slot's, the same day; the one that leaves before Your train; the next day's first
            /// under the day's last train.
            case then, earlier, first
        }

        enum Mark: Equatable, Sendable {
            case express, alert
        }

        let label: Label
        /// "8:06 AM".
        let time: String
        let mark: Mark?
    }

    init(_ entry: WidgetEntry) {
        let formatter = TimeFormatter(format: entry.timeFormat)
        header = entry.header.map(WidgetHeaderContent.init)
        guard case .trains(let trains) = entry.state, !trains.trains.isEmpty else {
            let message = WidgetMessage(entry, formatter: formatter, addsArrival: false)
            body = .message(message ?? WidgetMessage(title: String(localized: "widget.not_loaded.title"), detail: nil))
            link = entry.routeLink(from: .nextTrain)
            return
        }
        let index = trains.yourTrain.flatMap { trains.trains.indices.contains($0) ? $0 : nil } ?? 0
        let train = trains.trains[index]
        let isLast = trains.lastTrain == index

        let footer: Footer?
        if isLast {
            footer = trains.nextDayFirst.map { Footer(label: .first, time: formatter.time($0.departure), mark: nil) }
        } else if let earlier = trains.earlier, earlier != index, trains.trains.indices.contains(earlier) {
            footer = Footer(label: .earlier, time: formatter.time(trains.trains[earlier].departure), mark: nil)
        } else if trains.trains.indices.contains(index + 1) {
            let then = trains.trains[index + 1]
            if then.key.serviceDay == train.key.serviceDay {
                footer = Footer(
                    label: .then, time: formatter.time(then.departure),
                    mark: then.isAlerted ? .alert : then.isExpress ? .express : nil
                )
            } else {
                // The day's last train before 10 PM (a morning-only line): the train after it is another day's first.
                footer = Footer(label: .first, time: formatter.time(then.departure), mark: nil)
            }
        } else {
            footer = nil
        }
        body = .train(
            Train(
                isYourTrain: trains.yourTrain == index, time: WidgetClock(train.departure, formatter: formatter),
                isExpress: train.isExpress, departure: train.departure,
                countdown: WidgetCountdown.minutes(from: entry.date, to: train.departure), isLeavingNow: entry.isLeaving(train),
                isLastTrain: isLast, footer: footer
            )
        )
        link = WidgetLink.tagged(train.link, from: .nextTrain)
    }
}

extension WidgetMessage {
    init(title: String, detail: WidgetText?) {
        self.title = title
        self.detail = detail
    }
}

/// Departures, medium (revised Nov 13): the next train's departure, countdown and arrival, and the two after it on one
/// line. No AM or PM anywhere, and nothing about express, alerts or the last train: the small widget and the app say those.
struct DeparturesContent: Equatable, Sendable {
    let header: WidgetHeaderContent?
    let body: Body
    /// A tap outside the trains: Schedule on the widget's route at Now.
    let link: URL

    enum Body: Equatable, Sendable {
        case train(Train)
        case message(WidgetMessage)
    }

    struct Train: Equatable, Sendable {
        /// The countdown's end.
        let departure: Date
        /// "11 min", at the entry's moment.
        let countdown: String
        /// "7:58".
        let time: String
        /// "8:38".
        let arrival: String
        let isLeavingNow: Bool
        /// Trip details for the train.
        let link: URL
        /// The "Next" line: the two trains that leave after it on its service day, in time order whatever has an alert
        /// (one, or none after the day's last train; another day's trains are never "Next").
        let later: [Later]
    }

    struct Later: Equatable, Sendable, Identifiable {
        let time: String
        let link: URL

        var id: URL { link }
    }

    init(_ entry: WidgetEntry) {
        let formatter = TimeFormatter(format: entry.timeFormat)
        header = entry.header.map(WidgetHeaderContent.init)
        link = entry.routeLink(from: .departures)
        guard case .trains(let trains) = entry.state, let train = trains.trains.first else {
            let message = WidgetMessage(entry, formatter: formatter, addsArrival: true)
            body = .message(message ?? WidgetMessage(title: String(localized: "widget.not_loaded.title"), detail: nil))
            return
        }
        // The second train, then the third to leave: the one Your train displaced, else the third of the three.
        let following = [trains.trains.dropFirst().first, trains.displaced ?? trains.trains.dropFirst(2).first]
            .compactMap { $0 }
            .filter { $0.key.serviceDay == train.key.serviceDay }
        body = .train(
            Train(
                departure: train.departure, countdown: WidgetCountdown.minutes(from: entry.date, to: train.departure),
                time: formatter.railTime(train.departure), arrival: formatter.railTime(train.arrival),
                isLeavingNow: entry.isLeaving(train), link: WidgetLink.tagged(train.link, from: .departures),
                later: following.map {
                    Later(time: formatter.railTime($0.departure), link: WidgetLink.tagged($0.link, from: .departures))
                }
            )
        )
    }
}

/// The minutes to a departure as the widgets write them (TT-183, D113): "11 min", whole minutes rounded up, never
/// seconds; from an hour "1 h 20 min", as everywhere in the app (TT-246, D123: `TimeFormatter.duration(minutes:)`). Each
/// entry carries its own, and the timeline has an entry a minute while one shows (`WidgetEntryBuilder.countdownSpan`); the
/// last minute is "now" (`WidgetEntryBuilder.leavingLead`).
enum WidgetCountdown {
    static func minutes(from now: Date, to departure: Date) -> String {
        TimeFormatter.duration(minutes: wholeMinutes(from: now, to: departure))
    }

    /// The minutes left, rounded up (TT-185): every entry but a timeline's first is on a whole minute, so a first entry
    /// between two minutes reads what the entry on the minute before it would, and the number steps on the minute.
    static func wholeMinutes(from now: Date, to departure: Date) -> Int {
        max(0, Int((departure.timeIntervalSince(now) / 60).rounded(.up)))
    }
}

extension WidgetEntry {
    /// The gallery's sample (TT-183), fixed in code: Wed Nov 11, 2026 at 7:47 AM, Oakville to Union on Lakeshore West, the
    /// 7:58 in 11 min, then the 8:06 express and the 8:28.
    static let sample: WidgetEntry = {
        let day = ServiceDay(year: 2026, month: 11, day: 11)
        let route = WidgetFile.RouteKey(fromId: "OA", toId: "UN")
        func train(_ hour: Int, _ minute: Int, arrives: (Int, Int), express: Bool = false) -> Train {
            let key = TripKey(serviceDay: day, tripId: "sample-\(hour)\(minute)")
            return Train(
                key: key, departure: day.date(hour: hour, minute: minute), arrival: day.date(hour: arrives.0, minute: arrives.1),
                isExpress: express, isAlerted: false, link: WidgetLink.trip(key, route: route)
            )
        }
        let header = Header(
            from: WidgetFile.Stop(id: "OA", name: "Oakville GO"), to: WidgetFile.Stop(id: "UN", name: "Union Station GO"),
            line: WidgetFile.TrainLine(id: "LW", name: "Lakeshore West", colorHex: nil), link: WidgetLink.route(route)
        )
        let trains = Trains(
            header: header,
            trains: [train(7, 58, arrives: (8, 38)), train(8, 6, arrives: (8, 36), express: true), train(8, 28, arrives: (9, 8))]
        )
        return WidgetEntry(date: day.date(hour: 7, minute: 47), state: .trains(trains), relevance: 0, timeFormat: .device)
    }()
}
