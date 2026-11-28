import Foundation
@testable import TrainTimes

/// The Home Screen widgets' board states as entries (TT-183; board Widgets-States): Oakville ⇄ Union on Lakeshore West,
/// Wed Nov 11, 2026, 12-hour clock.
enum WidgetFixtures {
    static let day = ServiceDay(year: 2026, month: 11, day: 11)
    static let route = WidgetFile.RouteKey(fromId: "OA", toId: "UN")
    static let line = WidgetFile.TrainLine(id: "LW", name: "Lakeshore West", colorHex: "#8B1A31")

    /// The widgets' sizes on the iPhone 17 Pro, measured on its simulator (iOS 26.3) by TT-185: 493 px square and
    /// 1049 × 493 px at 3×, which iOS's own log gives as 164.33 and 349.67 × 164.33 pt (the boards drew Apple's 393 pt
    /// class, 158 and 338 × 158 pt). The snapshots draw them to the pixel.
    static let small = CGSize(width: 493.0 / 3, height: 493.0 / 3)
    static let medium = CGSize(width: 1049.0 / 3, height: 493.0 / 3)
    /// The Lock Screen sizes there: the boxes iOS lays the views out in, read with a `GeometryReader` on the placed
    /// widgets (the boards drew 160 × 72 and 72 pt, and iOS's own log says 162 × 72 and 72 × 72).
    static let lockRectangular = CGSize(width: 148, height: 72)
    static let lockCircular = CGSize(width: 58, height: 58)

    static func at(_ hour: Int, _ minute: Int, second: Int = 0, on day: ServiceDay = day) -> Date {
        day.date(hour: hour, minute: minute).addingTimeInterval(TimeInterval(second))
    }

    /// To Union; `home` is the way back, to Oakville.
    static func header(home: Bool = false) -> WidgetEntry.Header {
        let oakville = WidgetFile.Stop(id: "OA", name: "Oakville GO")
        let union = WidgetFile.Stop(id: "UN", name: "Union Station GO")
        let key = home ? route.reversed : route
        return WidgetEntry.Header(from: home ? union : oakville, to: home ? oakville : union, line: line, link: WidgetLink.route(key))
    }

    static func train(
        _ hour: Int, _ minute: Int, minutes: Int = 40, express: Bool = false, alerted: Bool = false, on day: ServiceDay = day,
        home: Bool = false
    ) -> WidgetEntry.Train {
        let key = TripKey(serviceDay: day, tripId: "LW-\(String(format: "%02d%02d", hour, minute))")
        let departure = at(hour, minute, on: day)
        return WidgetEntry.Train(
            key: key, departure: departure, arrival: departure.addingTimeInterval(TimeInterval(minutes * 60)), isExpress: express,
            isAlerted: alerted, link: WidgetLink.trip(key, route: home ? route.reversed : route)
        )
    }

    static func entry(_ date: Date, _ state: WidgetEntry.State, format: TimeFormat = .twelveHour) -> WidgetEntry {
        WidgetEntry(date: date, state: state, relevance: 0, timeFormat: format)
    }

    /// The builder's three, with "Next" as it makes it: the trains after the first on its service day.
    private static func trains(_ list: [WidgetEntry.Train], home: Bool = false) -> WidgetEntry.Trains {
        var trains = WidgetEntry.Trains(header: header(home: home), trains: list)
        if let first = list.first {
            trains.later = Array(list.dropFirst().prefix { $0.key.serviceDay == first.key.serviceDay })
        }
        return trains
    }

    /// 7:47 AM: the 7:58 in 11 min, then the 8:06 express and the 8:28.
    static func nextTrain(format: TimeFormat = .twelveHour) -> WidgetEntry {
        entry(
            at(7, 47), .trains(trains([train(7, 58), train(8, 6, minutes: 30, express: true), train(8, 28)])), format: format
        )
    }

    /// 7:47 AM with an alert on the 8:28: it takes the big slot, the 7:58 is Earlier.
    static var yourTrain: WidgetEntry {
        var list = trains([train(7, 58), train(8, 6, minutes: 30, express: true), train(8, 28, alerted: true)])
        list.yourTrain = 2
        list.earlier = 0
        return entry(at(7, 47), .trains(list))
    }

    /// 8:01 AM: the 8:06 express in 5 min, then the 8:28 with an alert.
    static var expressNext: WidgetEntry {
        entry(at(8, 1), .trains(trains([train(8, 6, minutes: 30, express: true), train(8, 28, alerted: true), train(8, 58)])))
    }

    /// The alerted 8:28 behind the 8:06 express, as the builder marks it from 2 h before (Your train, the 8:06 Earlier). At
    /// 7:58 AM it is 30 min away: on the Lock Screen its Live Activity has it, so the 8:06 leads there (TT-184).
    static func handOver(at date: Date = at(7, 58)) -> WidgetEntry {
        var list = trains([train(8, 6, minutes: 30, express: true), train(8, 28, alerted: true), train(8, 58)])
        list.yourTrain = 1
        list.earlier = 0
        return entry(date, .trains(list))
    }

    /// The 7:58 from further away: 6:30 AM is 88 min before it.
    static func farTrain(at date: Date = at(6, 30), format: TimeFormat = .twelveHour) -> WidgetEntry {
        entry(date, .trains(trains([train(7, 58), train(8, 6, minutes: 30, express: true), train(8, 28)])), format: format)
    }

    /// 8:05:30 AM: the 8:06 leaves in the minute.
    static var leavingNow: WidgetEntry {
        entry(at(8, 5, second: 30), .trains(trains([train(8, 6, minutes: 30, express: true), train(8, 28), train(8, 58)])))
    }

    /// 11:15 PM: the 11:47 is the last train, tomorrow's first is the 5:43.
    static var lastTrain: WidgetEntry {
        var list = trains([train(23, 47)])
        list.lastTrain = 0
        list.nextDayFirst = train(5, 43, minutes: 38, on: day.adding(days: 1))
        return entry(at(23, 15), .trains(list))
    }

    /// 10:20 PM: the 10:47 and the last train, the 11:47, after it.
    static var oneLater: WidgetEntry {
        var list = trains([train(22, 47), train(23, 47)])
        list.lastTrain = 1
        list.nextDayFirst = train(5, 43, minutes: 38, on: day.adding(days: 1))
        return entry(at(22, 20), .trains(list))
    }

    /// 11:50 PM, after the 11:47: tomorrow's first train, the 5:43 that arrives at 6:21.
    static var afterLastTrain: WidgetEntry {
        entry(
            at(23, 50),
            .noMoreTrainsTonight(header: header(), since: at(23, 47), next: train(5, 43, minutes: 38, on: day.adding(days: 1)))
        )
    }

    /// 6:02 PM, turned around: to Oakville, the 6:13, then the 6:20 express and the 6:43.
    static var evening: WidgetEntry {
        entry(
            at(18, 2),
            .trains(trains([train(18, 13, home: true), train(18, 20, minutes: 30, express: true, home: true), train(18, 43, home: true)], home: true))
        )
    }

    /// No trains to Oakville today; the next is Monday's 6:10 AM.
    static var noTrainsToday: WidgetEntry {
        entry(at(9, 0), .noTrainsToday(header: header(home: true), next: train(6, 10, on: day.adding(days: 5), home: true)))
    }

    static var notLoaded: WidgetEntry { entry(at(9, 0), .notLoaded) }
    static var noRoute: WidgetEntry { entry(at(9, 0), .noRoute) }
    static var outOfDate: WidgetEntry { entry(at(9, 0), .outOfDate(header: header())) }

    /// The widget file's station list for Edit widget: Aldershot, Clarkson, Oakville, Port Credit and Union, with Oakville
    /// and Union as Your stations (Union the most recent), the open route Oakville to Union.
    static var stationsFile: WidgetFile {
        WidgetFile(
            firstDay: day, lastDay: day.adding(days: 13), openRoute: route, routes: [], usualTimes: [], timeFormat: .twelveHour,
            stations: [
                WidgetFile.Stop(id: "AL", name: "Aldershot GO"), WidgetFile.Stop(id: "CL", name: "Clarkson GO"),
                WidgetFile.Stop(id: "OA", name: "Oakville GO"), WidgetFile.Stop(id: "PO", name: "Port Credit GO"),
                WidgetFile.Stop(id: "UN", name: "Union Station GO"),
            ],
            yourStationIds: ["UN", "OA"]
        )
    }

    // MARK: - My trains (TT-257, D131; board "Commute first")

    /// Oakville ⇄ Union for a week from Wed Nov 11 (to Mon Nov 16): to Union 6:58, 7:28, 7:58, the 8:06 express, 8:28 and
    /// 8:58; home 4:43, 5:13, 5:43 and 6:13 PM. Each time in `saved` ("07:58" to Union, "17:13" home) has a Repeat alert on
    /// weekdays, one id for all its days. `ids` false writes no alert ids, as a file from before TT-257.
    static func commuteFile(
        saved: Set<String> = ["07:58", "17:13"], ids: Bool = true, openRoute: WidgetFile.RouteKey? = route
    ) -> WidgetFile {
        let days = 6
        func departures(_ list: [(Int, Int, Int, Bool)]) -> [WidgetFile.Departure] {
            (0..<days).flatMap { offset -> [WidgetFile.Departure] in
                let serviceDay = day.adding(days: offset)
                return list.map { hour, minute, length, express in
                    let time = String(format: "%02d:%02d", hour, minute)
                    let start = at(hour, minute, on: serviceDay)
                    let isSaved = (1...5).contains(serviceDay.isoWeekday) && saved.contains(time)
                    return WidgetFile.Departure(
                        tripId: "LW-\(String(format: "%02d%02d", hour, minute))", serviceDay: serviceDay, departure: start,
                        arrival: start.addingTimeInterval(TimeInterval(length * 60)), isExpress: express, isAlerted: isSaved,
                        alertId: isSaved && ids ? "alert-\(time)" : nil
                    )
                }
            }
        }
        let outbound = departures([(6, 58, 40, false), (7, 28, 40, false), (7, 58, 40, false), (8, 6, 30, true), (8, 28, 40, false), (8, 58, 40, false)])
        let inbound = departures([(16, 43, 39, false), (17, 13, 39, false), (17, 43, 39, false), (18, 13, 39, false)])
        return WidgetFile(
            firstDay: day, lastDay: day.adding(days: days - 1), openRoute: openRoute,
            routes: [
                WidgetFile.Timetable(
                    from: WidgetFile.Stop(id: "OA", name: "Oakville GO"), to: WidgetFile.Stop(id: "UN", name: "Union Station GO"),
                    line: line, outbound: outbound, inbound: inbound
                ),
            ],
            usualTimes: [], timeFormat: .twelveHour, stations: [], yourStationIds: []
        )
    }

    /// A My trains widget's entry at `date`.
    static func mine(_ date: Date, file: WidgetFile = commuteFile()) -> WidgetEntry {
        WidgetEntryBuilder.entry(file: file, route: nil, turnsAround: true, mode: .myTrains, at: date)
    }
}
