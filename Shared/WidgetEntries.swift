import Foundation

/// One moment of a widget's timeline (TT-182): what TT-183 and TT-184 draw. Times stay `Date`s; the views format them with
/// the one formatter and `timeFormat` (D17).
struct WidgetEntry: Equatable, Sendable {
    let date: Date
    let state: State
    /// WidgetKit's relevance: 1 in the 30 min before an alerted train, 0.5 in the 30 min before a Repeat alert's usual time
    /// on its weekdays, else 0.
    let relevance: Double
    let timeFormat: TimeFormat
    /// The widget's Show (TT-257, D131), for its links: the app counts a tap with it (`widget_opened`'s `mode`). A My trains
    /// widget with no saved train draws the open route's states with this still `.myTrains`.
    var mode: WidgetMode = .route

    enum State: Equatable, Sendable {
        /// No file, a file of another version, or the widget's route is not in it.
        case notLoaded
        /// No route open in the app and none on the widget.
        case noRoute
        /// The current service day is past the file's last day; the route is still known.
        case outOfDate(header: Header)
        case trains(Trains)
        /// After the service day's last train until 3 AM: when that train left, and the next day's first train.
        case noMoreTrainsTonight(header: Header, since: Date, next: Train?)
        /// No train in the shown direction on the current service day: the next day with trains and its first train.
        case noTrainsToday(header: Header, next: Train?)
        /// My trains (TT-257, D131): the saved trains, on any route.
        case myTrains(MyTrains)
    }

    /// The trains whose bell is on (a switched-on alert, D70), on every route in the file, at this moment.
    struct MyTrains: Equatable, Sendable {
        /// Each saved train (one per alert) at its next departure, soonest first; never empty (with no saved train the
        /// widget shows the open route instead). A train that has left is at its next day.
        let saved: [Saved]
        /// In the 30 min before the first saved train (`LockWidget.handOverLead`), its direction's trains as A route shows
        /// them: on the Lock Screen its Live Activity has the train then, so the Lock Screen sizes go back to the next train
        /// there, as they did before TT-257. Nil otherwise.
        var handover: Trains?
    }

    struct Saved: Equatable, Sendable {
        /// Its route, in the direction it is saved in.
        let header: Header
        let train: Train
        /// The trains that leave after it in its direction on its service day, three at most: the medium's "Next" line and
        /// the small's "Then" when it is the only saved train.
        let after: [Train]

        /// Its direction, by station ids.
        var route: WidgetFile.RouteKey { WidgetFile.RouteKey(fromId: header.from.id, toId: header.to.id) }
    }

    struct Header: Equatable, Sendable {
        let from: WidgetFile.Stop
        let to: WidgetFile.Stop
        let line: WidgetFile.TrainLine?
        /// Schedule on this direction at Now.
        let link: URL
    }

    struct Train: Equatable, Sendable {
        let key: TripKey
        let departure: Date
        let arrival: Date
        let isExpress: Bool
        /// The bell.
        let isAlerted: Bool
        /// Trip details for the train.
        let link: URL
    }

    struct Trains: Equatable, Sendable {
        let header: Header
        /// The next three trains, in time order; Your train is always among them while it is due.
        let trains: [Train]
        /// From 2 h before an alerted train: its index, and the train that leaves first is Earlier.
        var yourTrain: Int?
        var earlier: Int?
        /// The train that arrives first, when it is not the first to leave (a tie gets none).
        var arrivesFirst: Int?
        /// The last train of its service day, from 10 PM, with the next day's first train.
        var lastTrain: Int?
        var nextDayFirst: Train?
        /// The trains that leave after the first one on its service day, in time order whatever has an alert, three at most:
        /// the medium's "Next" line (TT-257, D131; TT-183's Departures listed two).
        var later: [Train] = []
    }

    /// True while the widgets write a countdown: a train is still to leave today; in My trains, the first saved train is
    /// 2 h away or less (`WidgetEntryBuilder.countdownSpan`; further off its day is written).
    var showsCountdown: Bool {
        switch state {
        case .trains(let trains): !trains.trains.isEmpty
        case .myTrains(let mine): mine.saved.first.map { $0.train.departure.timeIntervalSince(date) <= WidgetEntryBuilder.countdownSpan } ?? false
        default: false
        }
    }
}

/// A widget's timeline: its entries for the next 3 h (or until 3 AM, if sooner), and when WidgetKit asks again (after an
/// hour while a countdown shows, else when the entries end).
struct WidgetTimeline: Equatable, Sendable {
    let entries: [WidgetEntry]
    let reloadAt: Date
}

/// Builds a widget's entries from the widget file (TT-182, D107), pure Foundation so the extension and the tests share it.
/// In: the file, the widget's route (nil is the app's open route), "Turn around at 12 PM", its Show (TT-257, D131) and now.
/// My trains lists the saved trains while there is one to come, else shows the open route turned around at 12 PM.
enum WidgetEntryBuilder {
    /// Turn-around on: From → To from 3 AM to 12 PM, To → From from 12 PM to 3 AM (D101).
    static let turnAroundHour = 12
    /// The last train is marked from 10 PM.
    static let lastTrainHour = 22
    static let yourTrainLead: TimeInterval = 2 * 60 * 60
    static let relevanceLead: TimeInterval = 30 * 60
    static let trainCount = 3
    /// The last minute before a departure, when the countdown reads "now" (TT-183).
    static let leavingLead: TimeInterval = 60
    /// The countdown is text in each entry, so the timeline has an entry a minute while one shows (TT-183, D113: in a
    /// placed widget iOS did not redraw a counting text by itself). The minutes are written for the next 2 h and
    /// WidgetKit is asked again after 1 h, well inside its daily budget, so an hour of them is in hand when it asks late.
    static let countdownSpan: TimeInterval = 2 * 60 * 60
    static let countdownReload: TimeInterval = 60 * 60
    /// The timeline ends 3 h on, or at 3 AM if sooner (TT-185, D117): iOS drops a timeline whose archive is too large.
    /// A whole day's 304 entries made Departures' archive 12 MB on a tinted Home Screen, and the widget stayed a
    /// placeholder; 8 MB still loaded. Three hours are about 150 entries at most, and iOS is asked again before they end.
    static let horizon: TimeInterval = 3 * 60 * 60

    static func timeline(
        file: WidgetFile?, route: WidgetFile.RouteKey?, turnsAround: Bool, mode: WidgetMode = .route, now: Date
    ) -> WidgetTimeline {
        let cutoff = ServiceDay(containing: now).adding(days: 1).date(hour: ServiceDay.cutoffHour, minute: 0)
        let end = min(cutoff, now.addingTimeInterval(horizon))
        func make(_ date: Date) -> WidgetEntry {
            entry(file: file, route: route, turnsAround: turnsAround, mode: mode, at: date)
        }
        let moments = [now] + changes(file: file, route: route, turnsAround: turnsAround, mode: mode, after: now, before: end)
        // Each whole minute of the next 2 h that is not a change already, kept where a countdown shows.
        let known = Set(moments)
        let firstMinute = (now.timeIntervalSince1970 / 60).rounded(.down) * 60 + 60
        let lastMinute = min(end, now.addingTimeInterval(countdownSpan)).timeIntervalSince1970
        let minutes = stride(from: firstMinute, through: lastMinute, by: 60)
            .map { Date(timeIntervalSince1970: $0) }
            .filter { $0 < end && !known.contains($0) }
        let entries = (moments.map(make) + minutes.map(make).filter(\.showsCountdown)).sorted { $0.date < $1.date }
        // Asked again an hour on while a countdown shows (or when the first one starts, if later), else when the entries
        // end: 3 h on, or at 3 AM.
        let firstCountdown = entries.first(where: \.showsCountdown)?.date
        let reloadAt = firstCountdown.map { min(end, max($0, now.addingTimeInterval(countdownReload))) } ?? end
        return WidgetTimeline(entries: entries, reloadAt: reloadAt)
    }

    /// The entry at one moment.
    static func entry(
        file: WidgetFile?, route: WidgetFile.RouteKey?, turnsAround: Bool, mode: WidgetMode = .route, at date: Date
    ) -> WidgetEntry {
        guard let file else { return WidgetEntry(date: date, state: .notLoaded, relevance: 0, timeFormat: .device, mode: mode) }
        if mode == .myTrains, let mine = myTrains(file: file, at: date) {
            return WidgetEntry(
                date: date, state: .myTrains(mine), relevance: savedRelevance(file: file, at: date), timeFormat: file.timeFormat,
                mode: mode
            )
        }
        // A route, or My trains with no saved train to come: the widget's route, else the open route (My trains has none
        // of its own and keeps "Turn around at 12 PM" on).
        let route = mode == .myTrains ? nil : route
        let turnsAround = mode == .myTrains ? true : turnsAround
        let state: WidgetEntry.State
        var relevance = 0.0
        if let shown = direction(file: file, route: route, turnsAround: turnsAround, at: date) {
            state = Self.state(file: file, shown: shown, at: date)
            relevance = Self.relevance(file: file, shown: shown, at: date)
        } else {
            state = route == nil && file.openRoute == nil ? .noRoute : .notLoaded
        }
        return WidgetEntry(date: date, state: state, relevance: relevance, timeFormat: file.timeFormat, mode: mode)
    }

    // MARK: - My trains

    /// Every direction in the file with a saved train, with all its trains in time order.
    private static func savedDirections(file: WidgetFile) -> [Shown] {
        file.routes.flatMap { timetable -> [Shown] in
            [timetable.key, timetable.key.reversed].compactMap { key in
                guard let way = timetable.direction(key), way.trains.contains(where: \.isAlerted) else { return nil }
                let trains = way.trains.sorted { ($0.departure, $0.tripId) < ($1.departure, $1.tripId) }
                let header = WidgetEntry.Header(from: way.from, to: way.to, line: timetable.line, link: WidgetLink.route(key))
                return Shown(key: key, header: header, trains: trains)
            }
        }
    }

    /// The saved trains to come at `date`, one per alert at its next departure, soonest first; nil when there is none (the
    /// file is past its last day, no alert is switched on, or every saved train has left for good).
    static func myTrains(file: WidgetFile, at date: Date) -> WidgetEntry.MyTrains? {
        let today = ServiceDay(containing: date)
        guard today <= file.lastDay else { return nil }
        var seen: Set<String> = []
        var next: [(shown: Shown, departure: WidgetFile.Departure)] = []
        let upcoming = savedDirections(file: file).flatMap { shown in
            shown.trains.filter { $0.isAlerted && $0.departure > date }.map { (shown: shown, departure: $0) }
        }.sorted { ($0.departure.departure, $0.departure.tripId) < ($1.departure.departure, $1.departure.tripId) }
        for item in upcoming {
            // One alert is one saved train; a file from before TT-257 has no ids, so each train is its own.
            let id = item.departure.alertId ?? "\(item.shown.key.fromId)>\(item.shown.key.toId)>\(item.departure.tripId)"
            guard seen.insert(id).inserted else { continue }
            next.append(item)
        }
        guard let first = next.first else { return nil }
        let saved = next.map { item in
            let day = item.departure.serviceDay
            let after = item.shown.trains.filter { $0.serviceDay == day && $0.departure > item.departure.departure }
            return WidgetEntry.Saved(
                header: item.shown.header, train: train(item.departure, item.shown),
                after: after.prefix(trainCount).map { train($0, item.shown) }
            )
        }
        var mine = WidgetEntry.MyTrains(saved: saved)
        if first.departure.departure.timeIntervalSince(date) <= LockWidget.handOverLead,
           case .trains(let trains) = state(file: file, shown: first.shown, at: date) {
            mine.handover = trains
        }
        return mine
    }

    /// 1 in the 30 min before a saved train, 0.5 in the 30 min before a Repeat alert's usual time on its weekdays, else 0.
    private static func savedRelevance(file: WidgetFile, at date: Date) -> Double {
        func isSoon(_ moment: Date) -> Bool {
            let lead = moment.timeIntervalSince(date)
            return lead > 0 && lead <= relevanceLead
        }
        if savedDirections(file: file).contains(where: { $0.trains.contains { $0.isAlerted && isSoon($0.departure) } }) { return 1 }
        let keys = Set(file.usualTimes.map(\.route))
        if keys.contains(where: { usualMoments(file: file, key: $0, around: date).contains(where: isSoon) }) { return 0.5 }
        return 0
    }

    // MARK: - Direction

    private struct Shown {
        let key: WidgetFile.RouteKey
        let header: WidgetEntry.Header
        let trains: [WidgetFile.Departure]
    }

    /// The direction the widget shows at `date`: its route (or the open route's morning way), turned around after 12 PM.
    private static func direction(file: WidgetFile, route: WidgetFile.RouteKey?, turnsAround: Bool, at date: Date) -> Shown? {
        guard let base = route ?? file.openRoute else { return nil }
        let day = ServiceDay(containing: date)
        let afternoon = date >= day.date(hour: turnAroundHour, minute: 0)
        let key = turnsAround && afternoon ? base.reversed : base
        guard let way = file.timetable(for: key)?.direction(key) else { return nil }
        let trains = way.trains.sorted { ($0.departure, $0.tripId) < ($1.departure, $1.tripId) }
        let line = file.timetable(for: key)?.line
        return Shown(key: key, header: WidgetEntry.Header(from: way.from, to: way.to, line: line, link: WidgetLink.route(key)), trains: trains)
    }

    // MARK: - State

    private static func state(file: WidgetFile, shown: Shown, at date: Date) -> WidgetEntry.State {
        let today = ServiceDay(containing: date)
        guard today <= file.lastDay else { return .outOfDate(header: shown.header) }
        let todays = shown.trains.filter { $0.serviceDay == today }
        guard let last = todays.last else {
            let next = shown.trains.first { $0.serviceDay > today }
            return .noTrainsToday(header: shown.header, next: next.map { train($0, shown) })
        }
        let upcoming = shown.trains.filter { $0.departure > date }
        guard last.departure > date else {
            return .noMoreTrainsTonight(header: shown.header, since: last.departure, next: upcoming.first.map { train($0, shown) })
        }

        var three = Array(upcoming.prefix(trainCount))
        let yours = upcoming.first { $0.isAlerted && $0.departure.timeIntervalSince(date) <= yourTrainLead }
        if let yours, !three.contains(yours) {
            three = Array(upcoming.prefix(trainCount - 1)) + [yours]
        }
        var trains = WidgetEntry.Trains(header: shown.header, trains: three.map { train($0, shown) })
        if let first = upcoming.first {
            trains.later = upcoming.dropFirst().prefix { $0.serviceDay == first.serviceDay }.prefix(trainCount).map { train($0, shown) }
        }
        if let yours, let index = three.firstIndex(of: yours) {
            trains.yourTrain = index
            if index != 0 { trains.earlier = 0 }
        }
        if let first = three.map(\.arrival).min(), three.filter({ $0.arrival == first }).count == 1,
           let index = three.firstIndex(where: { $0.arrival == first }), index != 0 {
            trains.arrivesFirst = index
        }
        if let index = three.firstIndex(where: { isLast($0, in: shown.trains) && date >= $0.serviceDay.date(hour: lastTrainHour, minute: 0) }) {
            trains.lastTrain = index
            let day = three[index].serviceDay
            trains.nextDayFirst = shown.trains.first { $0.serviceDay > day }.map { train($0, shown) }
        }
        return .trains(trains)
    }

    private static func isLast(_ departure: WidgetFile.Departure, in trains: [WidgetFile.Departure]) -> Bool {
        trains.last { $0.serviceDay == departure.serviceDay } == departure
    }

    private static func train(_ departure: WidgetFile.Departure, _ shown: Shown) -> WidgetEntry.Train {
        WidgetEntry.Train(
            key: departure.key, departure: departure.departure, arrival: departure.arrival, isExpress: departure.isExpress,
            isAlerted: departure.isAlerted, link: WidgetLink.trip(departure.key, route: shown.key)
        )
    }

    // MARK: - Relevance and entry times

    private static func relevance(file: WidgetFile, shown: Shown, at date: Date) -> Double {
        func isSoon(_ moment: Date) -> Bool {
            let lead = moment.timeIntervalSince(date)
            return lead > 0 && lead <= relevanceLead
        }
        if shown.trains.contains(where: { $0.isAlerted && isSoon($0.departure) }) { return 1 }
        if usualMoments(file: file, key: shown.key, around: date).contains(where: isSoon) { return 0.5 }
        return 0
    }

    /// A Repeat alert's usual time in this direction on its weekdays, on the service day of `date` and the next.
    private static func usualMoments(file: WidgetFile, key: WidgetFile.RouteKey, around date: Date) -> [Date] {
        let today = ServiceDay(containing: date)
        return file.usualTimes.filter { $0.route == key }.flatMap { usual in
            [today, today.adding(days: 1)].filter { usual.weekdays.contains($0.isoWeekday) }
                .map { $0.date(minutesIntoDay: usual.minutesIntoDay) }
        }
    }

    /// When the entry changes before `end`: each departure in the direction shown then and the minute before it (the
    /// countdown's "now", TT-183), 12 PM, 10 PM, 2 h and 30 min before an alerted train, and 30 min before a usual time.
    ///
    /// My trains (TT-257, D131): each saved train's departure, the minute before it, 2 h before it (its countdown starts)
    /// and 30 min before it (the Lock Screen hands over), and 30 min before a usual time. Its direction's own departures in
    /// those 30 min fall on the countdown's minutes. After the last saved train to come leaves, the open route's changes.
    private static func changes(
        file: WidgetFile?, route: WidgetFile.RouteKey?, turnsAround: Bool, mode: WidgetMode, after start: Date, before end: Date
    ) -> [Date] {
        guard let file else { return [] }
        var fallbackFrom = start
        var mine: [Date] = []
        if mode == .myTrains {
            let saved = savedDirections(file: file).flatMap { $0.trains.filter(\.isAlerted).map(\.departure) }.filter { $0 > start }
            for departure in saved {
                mine += [
                    departure, departure.addingTimeInterval(-leavingLead), departure.addingTimeInterval(-countdownSpan),
                    departure.addingTimeInterval(-LockWidget.handOverLead),
                ]
            }
            mine += Set(file.usualTimes.map(\.route)).flatMap { usualMoments(file: file, key: $0, around: start) }
                .map { $0.addingTimeInterval(-relevanceLead) }
            // The open route shows only once no saved train is left to come (at once with none).
            if let last = saved.max() {
                guard last < end else { return Array(Set(mine.filter { $0 > start && $0 < end })).sorted() }
                fallbackFrom = last
            }
        }
        let route = mode == .myTrains ? nil : route
        let turnsAround = mode == .myTrains ? true : turnsAround
        let day = ServiceDay(containing: start)
        var moments = [day.date(hour: turnAroundHour, minute: 0), day.date(hour: lastTrainHour, minute: 0)]
        for moment in [fallbackFrom, day.date(hour: turnAroundHour, minute: 0)] {
            guard let shown = direction(file: file, route: route, turnsAround: turnsAround, at: max(moment, fallbackFrom)) else { continue }
            for train in shown.trains {
                moments += [train.departure, train.departure.addingTimeInterval(-leavingLead)]
                if train.isAlerted {
                    moments += [train.departure.addingTimeInterval(-yourTrainLead), train.departure.addingTimeInterval(-relevanceLead)]
                }
            }
            moments += usualMoments(file: file, key: shown.key, around: start).map { $0.addingTimeInterval(-relevanceLead) }
        }
        let within = (mine + moments.filter { $0 >= fallbackFrom }).filter { $0 > start && $0 < end }
        // A departure from the other direction lands on an entry that shows the same thing; harmless, and deduped here.
        return Array(Set(within)).sorted()
    }
}
