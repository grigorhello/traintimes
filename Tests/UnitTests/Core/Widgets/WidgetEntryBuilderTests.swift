import XCTest
@testable import TrainTimes

/// The widget timeline (TT-182, D107) at fixed Toronto times. Oakville ⇄ Union, Wed Nov 11 to Fri Nov 13, 2026; times are
/// on the service day, so 00:40 is the next morning.
final class WidgetEntryBuilderTests: XCTestCase {
    private let wed = ServiceDay(year: 2026, month: 11, day: 11)
    private var thu: ServiceDay { wed.adding(days: 1) }
    private var fri: ServiceDay { wed.adding(days: 2) }
    private let oakvilleToUnion = WidgetFile.RouteKey(fromId: "OA", toId: "UN")

    /// Stored out of order (the builder sorts). From Oakville: 6:00, 7:00, the 7:10 express (in 25 min, so it arrives before the 7:00), 8:00, 9:45, 10:15, 11:30 (an
    /// alert on Wednesday's), 12:30, 23:30 and 00:40. From Union: 12:15, 17:00, 18:00, 23:00.
    private func file(days: [ServiceDay]? = nil, usual: [WidgetFile.UsualTime] = []) -> WidgetFile {
        let days = days ?? [wed, thu, fri]
        let outbound = days.flatMap { day in
            ["06:00", "07:00", "08:00", "09:45", "10:15", "11:30", "12:30", "23:30", "00:40"].map { time in
                departure(day, time, alerted: day == wed && time == "11:30")
            } + [departure(day, "07:10", minutes: 25, express: true)]
        }
        let inbound = days.flatMap { day in ["12:15", "17:00", "18:00", "23:00"].map { departure(day, $0, prefix: "UN") } }
        return WidgetFile(
            firstDay: wed, lastDay: fri, openRoute: oakvilleToUnion,
            routes: [
                WidgetFile.Timetable(
                    from: WidgetFile.Stop(id: "OA", name: "Oakville"), to: WidgetFile.Stop(id: "UN", name: "Union"),
                    line: WidgetFile.TrainLine(id: "LW", name: "Lakeshore West", colorHex: "#8B1A31"),
                    outbound: outbound.reversed(), inbound: inbound
                ),
            ],
            usualTimes: usual, timeFormat: .twelveHour, stations: [], yourStationIds: []
        )
    }

    private func departure(
        _ day: ServiceDay, _ time: String, minutes: Int = 40, express: Bool = false, alerted: Bool = false, prefix: String = "LW"
    ) -> WidgetFile.Departure {
        let start = at(day, time)
        return WidgetFile.Departure(
            tripId: "\(prefix)-\(time.replacingOccurrences(of: ":", with: ""))-\(day.gtfsDate)", serviceDay: day, departure: start,
            arrival: start.addingTimeInterval(TimeInterval(minutes * 60)), isExpress: express, isAlerted: alerted
        )
    }

    private func at(_ day: ServiceDay, _ time: String) -> Date {
        let parts = time.split(separator: ":").map { Int($0)! }
        return day.date(hour: parts[0], minute: parts[1])
    }

    private func entry(
        _ day: ServiceDay, _ time: String, file: WidgetFile? = nil, route: WidgetFile.RouteKey? = nil, turnsAround: Bool = true
    ) -> WidgetEntry {
        WidgetEntryBuilder.entry(file: file ?? self.file(), route: route, turnsAround: turnsAround, at: at(day, time))
    }

    private func trains(_ entry: WidgetEntry, file: StaticString = #filePath, line: UInt = #line) -> WidgetEntry.Trains? {
        guard case .trains(let trains) = entry.state else {
            XCTFail("Expected trains, got \(entry.state)", file: file, line: line)
            return nil
        }
        return trains
    }

    /// "HH:mm" on the service day of each train, to compare lists quickly.
    private func times(_ trains: WidgetEntry.Trains?) -> [String] {
        trains?.trains.map { train in
            let minutes = ServiceDay.minutesIntoServiceDay(train.departure) % (24 * 60)
            return String(format: "%02d:%02d", minutes / 60, minutes % 60)
        } ?? []
    }

    // MARK: - States

    func testNoFileIsNotLoaded() {
        let entry = WidgetEntryBuilder.entry(file: nil, route: nil, turnsAround: true, at: at(wed, "08:00"))
        XCTAssertEqual(entry.state, .notLoaded)
    }

    func testAnotherVersionIsNotLoaded() throws {
        var other = file()
        other.version = 2
        XCTAssertNil(WidgetFile.decode(try other.encoded()))
        let original = file()
        XCTAssertEqual(WidgetFile.decode(try original.encoded()), original)
    }

    func testARouteNotInTheFileIsNotLoaded() {
        XCTAssertEqual(entry(wed, "08:00", route: WidgetFile.RouteKey(fromId: "OA", toId: "BU")).state, .notLoaded)
    }

    func testNoRoute() {
        var noRoute = file()
        noRoute.openRoute = nil
        XCTAssertEqual(entry(wed, "08:00", file: noRoute).state, .noRoute)
    }

    func testOutOfDateAfterTheFilesLastDay() {
        guard case .outOfDate(let header) = entry(fri.adding(days: 1), "08:00").state else { return XCTFail("Expected out of date") }
        XCTAssertEqual(header.to.name, "Union")
        if case .outOfDate = entry(fri, "08:00").state { XCTFail("Friday is still in the file") }
    }

    func testNoMoreTrainsTonightAfterTheLastTrainUntil3AM() {
        let late = entry(wed, "01:00", turnsAround: false)
        guard case .noMoreTrainsTonight(let header, let since, let next) = late.state else { return XCTFail("\(late.state)") }
        XCTAssertEqual(header.from.id, "OA")
        XCTAssertEqual(since, at(wed, "00:40"))
        XCTAssertEqual(next?.departure, at(thu, "06:00"))
        XCTAssertEqual(next?.arrival, at(thu, "06:40"))
        // At 3 AM the new service day starts with its trains.
        XCTAssertEqual(times(trains(entry(thu, "03:00", turnsAround: false))), ["06:00", "07:00", "07:10"])
    }

    func testNoTrainsToday() {
        let skipsThursday = file(days: [wed, fri])
        let thursday = entry(thu, "08:00", file: skipsThursday, turnsAround: false)
        guard case .noTrainsToday(_, let next) = thursday.state else { return XCTFail("\(thursday.state)") }
        XCTAssertEqual(next?.key.serviceDay, fri)
        XCTAssertEqual(next?.departure, at(fri, "06:00"))
    }

    // MARK: - Direction

    func testTurnsAroundAt12PM() {
        let morning = trains(entry(wed, "11:59"))
        XCTAssertEqual(morning?.header.from.name, "Oakville")
        XCTAssertEqual(times(morning), ["12:30", "23:30", "00:40"])
        XCTAssertEqual(morning?.trains.first?.departure, at(wed, "12:30"))

        let noon = trains(entry(wed, "12:00"))
        XCTAssertEqual(noon?.header.from.name, "Union")
        XCTAssertEqual(noon?.header.to.name, "Oakville")
        XCTAssertEqual(times(noon), ["12:15", "17:00", "18:00"])
        XCTAssertEqual(noon?.header.link, URL(string: "traintimes://route?destinationId=OA&originId=UN"))
    }

    func testTurnAroundOffKeepsFromTo() {
        XCTAssertEqual(times(trains(entry(wed, "12:00", turnsAround: false))), ["12:30", "23:30", "00:40"])
    }

    func testAWidgetRouteTurnsAroundFromItsOwnWay() {
        let unionToOakville = oakvilleToUnion.reversed
        XCTAssertEqual(trains(entry(wed, "08:00", route: unionToOakville))?.header.from.id, "UN")
        XCTAssertEqual(trains(entry(wed, "13:00", route: unionToOakville))?.header.from.id, "OA")
    }

    /// From midnight to 3 AM the day's late trains come first, then the next day's.
    func testAt1230AMLateTrainsMergeWithTheNextDays() {
        let night = trains(entry(wed, "00:30", turnsAround: false))
        XCTAssertEqual(night?.trains.map(\.key.serviceDay), [wed, thu, thu])
        XCTAssertEqual(times(night), ["00:40", "06:00", "07:00"])
        // Turned around, Union's last train left at 11 PM.
        guard case .noMoreTrainsTonight(let header, let since, let next) = entry(wed, "00:30").state else { return XCTFail() }
        XCTAssertEqual(header.from.id, "UN")
        XCTAssertEqual(since, at(wed, "23:00"))
        XCTAssertEqual(next?.departure, at(thu, "12:15"))
    }

    // MARK: - Labels

    func testYourTrainFromExactly2HoursBefore() {
        let before = trains(entry(wed, "09:29"))
        XCTAssertNil(before?.yourTrain)
        XCTAssertNil(before?.earlier)

        let due = trains(entry(wed, "09:30"))
        XCTAssertEqual(times(due), ["09:45", "10:15", "11:30"])
        XCTAssertEqual(due?.yourTrain, 2)
        XCTAssertEqual(due?.earlier, 0)
        XCTAssertEqual(due?.trains[2].isAlerted, true)

        // Once it is the next train, it has no Earlier.
        let next = trains(entry(wed, "10:20"))
        XCTAssertEqual(next?.yourTrain, 0)
        XCTAssertNil(next?.earlier)
    }

    /// Your train stays among the three, in time order, when more trains leave before it; the earliest of two alerted
    /// trains wins.
    func testYourTrainIsKeptAmongTheThree() {
        var busy = file()
        busy.routes[0].outbound = ["08:00", "08:10", "08:20", "08:30", "08:40", "08:50"].map {
            departure(wed, $0, alerted: $0 == "08:40" || $0 == "08:50")
        }
        let kept = trains(entry(wed, "07:55", file: busy))
        XCTAssertEqual(times(kept), ["08:00", "08:10", "08:40"])
        XCTAssertEqual(kept?.yourTrain, 2)
        XCTAssertEqual(kept?.earlier, 0)
        // The train it took the place of, for Departures' plain "Next" line (TT-183).
        XCTAssertEqual(times(kept.map { WidgetEntry.Trains(header: $0.header, trains: [$0.displaced].compactMap { $0 }) }), ["08:20"])
        XCTAssertNil(trains(entry(wed, "08:25", file: busy))?.displaced)
    }

    func testArrivesFirst() {
        let express = trains(entry(wed, "06:30"))
        XCTAssertEqual(times(express), ["07:00", "07:10", "08:00"])
        XCTAssertEqual(express?.arrivesFirst, 1)
        // The first train arriving first gets no label.
        XCTAssertNil(trains(entry(wed, "07:05"))?.arrivesFirst)
        // Nor does a tie.
        var tie = file()
        tie.routes[0].outbound = [departure(wed, "07:00"), departure(wed, "07:10", minutes: 20), departure(wed, "07:15", minutes: 15)]
        XCTAssertNil(trains(entry(wed, "06:30", file: tie))?.arrivesFirst)
    }

    func testLastTrainFrom10PMWithTheNextDaysFirst() {
        let evening = trains(entry(wed, "21:59", turnsAround: false))
        XCTAssertEqual(times(evening), ["23:30", "00:40", "06:00"])
        XCTAssertNil(evening?.lastTrain)

        let late = trains(entry(wed, "22:00", turnsAround: false))
        XCTAssertEqual(late?.lastTrain, 1)
        XCTAssertEqual(late?.nextDayFirst?.departure, at(thu, "06:00"))
    }

    // MARK: - Relevance and links

    func testRelevance() {
        // An alerted train: 1 in its last 30 min.
        XCTAssertEqual(entry(wed, "11:00").relevance, 1)
        XCTAssertEqual(entry(wed, "10:59").relevance, 0)
        // A Repeat alert's usual 8:00 AM on Wednesdays: 0.5 in the 30 min before, on its weekdays and its way only.
        let usual = file(usual: [WidgetFile.UsualTime(route: oakvilleToUnion, minutesIntoDay: 8 * 60, weekdays: [3])])
        XCTAssertEqual(entry(wed, "07:30", file: usual).relevance, 0.5)
        XCTAssertEqual(entry(wed, "07:29", file: usual).relevance, 0)
        XCTAssertEqual(entry(thu, "07:30", file: usual).relevance, 0)
        XCTAssertEqual(entry(wed, "07:30", file: usual, route: oakvilleToUnion.reversed, turnsAround: false).relevance, 0)
    }

    func testLinks() {
        let train = trains(entry(wed, "08:30"))?.trains.first
        let link = train?.link
        XCTAssertEqual(link, URL(string: "traintimes://trip?destinationId=UN&originId=OA&serviceDate=20261111&tripId=LW-0945-20261111"))
        XCTAssertEqual(
            link.flatMap { NotificationLink(url: $0, today: wed) },
            .trip(TripKey(serviceDay: wed, tripId: "LW-0945-20261111"), originId: "OA", destinationId: "UN")
        )
        XCTAssertEqual(trains(entry(wed, "08:30"))?.header.link, URL(string: "traintimes://route?destinationId=UN&originId=OA"))
    }

    func testTheEntryCarriesTheTimeFormat() {
        XCTAssertEqual(entry(wed, "08:00").timeFormat, .twelveHour)
    }

    // MARK: - Timeline

    /// The timeline is the next 3 h, or until 3 AM if sooner (TT-185, D117): a whole day's entries made an archive iOS
    /// refused.
    func testTimelineEntriesForTheNext3Hours() {
        let now = at(wed, "09:00")
        let timeline = WidgetEntryBuilder.timeline(file: file(), route: nil, turnsAround: true, now: now)
        let dates = timeline.entries.map(\.date)
        XCTAssertEqual(dates.first, now)
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertEqual(Set(dates).count, dates.count)
        XCTAssertTrue(dates.allSatisfy { $0 >= now && $0 < at(wed, "12:00") })
        XCTAssertLessThanOrEqual(dates.count, 150)
        // Departures, 2 h and 30 min before the alerted 11:30, and the minute before each departure, when the
        // countdown reads "now" (TT-183).
        for time in ["09:30", "09:45", "10:15", "11:00", "11:30", "09:44", "10:14", "11:29"] {
            XCTAssertTrue(dates.contains(at(wed, time)), time)
        }
        // 12 PM, the way home's trains and 10 PM, each from a timeline that reaches it.
        func later(from time: String, file: WidgetFile? = nil) -> [Date] {
            WidgetEntryBuilder.timeline(file: file ?? self.file(), route: nil, turnsAround: true, now: at(wed, time)).entries.map(\.date)
        }
        for time in ["12:00", "12:14", "12:15"] {
            XCTAssertTrue(later(from: "10:30").contains(at(wed, time)), time)
        }
        for time in ["16:59", "17:00"] {
            XCTAssertTrue(later(from: "15:00").contains(at(wed, time)), time)
        }
        for time in ["22:00", "22:59", "23:00"] {
            XCTAssertTrue(later(from: "21:00").contains(at(wed, time)), time)
        }
        XCTAssertTrue(later(from: "22:30").allSatisfy { $0 < at(wed, "01:30") })
        XCTAssertTrue(later(from: "01:00").allSatisfy { $0 < at(thu, "03:00") })
        // A usual time adds the moment 30 min before it.
        let usual = file(usual: [WidgetFile.UsualTime(route: oakvilleToUnion.reversed, minutesIntoDay: 17 * 60 + 40, weekdays: [3])])
        XCTAssertTrue(later(from: "15:00", file: usual).contains(at(wed, "17:10")))
    }

    /// The countdown is text in each entry (TT-183, D113): an entry each minute for 2 h, and iOS is asked again in 1 h.
    func testACountdownGetsAnEntryEachMinuteAndAnHourlyReload() {
        let now = at(wed, "09:00")
        let timeline = WidgetEntryBuilder.timeline(file: file(), route: nil, turnsAround: true, now: now)
        XCTAssertEqual(timeline.reloadAt, at(wed, "10:00"))
        let dates = timeline.entries.map(\.date)
        for time in ["09:01", "09:02", "09:59", "10:00", "10:59", "11:00"] {
            XCTAssertTrue(dates.contains(at(wed, time)), time)
        }
        XCTAssertFalse(dates.contains(at(wed, "11:01")))
        XCTAssertEqual(dates.filter { $0 <= at(wed, "11:00") }.count, 121)
        // From a moment between two minutes, the first one is the next whole minute.
        let late = WidgetEntryBuilder.timeline(file: file(), route: nil, turnsAround: true, now: now.addingTimeInterval(20))
        XCTAssertEqual(Array(late.entries.map(\.date).prefix(2)), [now.addingTimeInterval(20), at(wed, "09:01")])
        XCTAssertEqual(late.reloadAt, at(wed, "10:00").addingTimeInterval(20))
    }

    /// No countdown, no minutes: after the last train the timeline waits for 3 AM, and before a turn-around that brings
    /// trains back it asks again when they start.
    func testNoCountdownHasNoMinuteEntries() {
        let night = WidgetEntryBuilder.timeline(file: file(), route: nil, turnsAround: true, now: at(wed, "00:10"))
        XCTAssertEqual(night.entries.map(\.date), [at(wed, "00:10")])
        XCTAssertEqual(night.reloadAt, at(thu, "03:00"))
        // More than 3 h before 3 AM the entries end 3 h on, and iOS is asked again then.
        let evening = WidgetEntryBuilder.timeline(file: file(), route: nil, turnsAround: true, now: at(wed, "23:10"))
        XCTAssertEqual(evening.entries.map(\.date), [at(wed, "23:10")])
        XCTAssertEqual(evening.reloadAt, at(wed, "02:10"))

        var morningOnly = file()
        morningOnly.routes[0].outbound = [departure(wed, "08:00")]
        let waiting = WidgetEntryBuilder.timeline(file: morningOnly, route: nil, turnsAround: true, now: at(wed, "09:00"))
        XCTAssertFalse(waiting.entries.first?.showsCountdown ?? true)
        XCTAssertFalse(waiting.entries.map(\.date).contains(at(wed, "09:01")))
        XCTAssertEqual(waiting.reloadAt, at(wed, "12:00"))
    }

    func testNotLoadedTimelineIsOneEntry() {
        let timeline = WidgetEntryBuilder.timeline(file: nil, route: nil, turnsAround: true, now: at(wed, "09:00"))
        XCTAssertEqual(timeline.entries.map(\.state), [.notLoaded])
        XCTAssertEqual(timeline.reloadAt, at(wed, "12:00"))
    }

    // MARK: - The Lock Screen sizes (TT-184)

    /// The Lock Screen's switches all land on entries the timeline already has (the minutes of a countdown, D113), so it
    /// adds none: 59 min before a train the circular turns from the clock time to the minutes, 30 min before it the ring
    /// starts to empty and an alerted train goes to its Live Activity, and the last minute reads "now". From 10:20 AM
    /// with the alerted 11:30 next.
    func testTheLockScreensSwitchesLandOnTheTimelinesEntries() {
        let timeline = WidgetEntryBuilder.timeline(file: file(), route: nil, turnsAround: true, now: at(wed, "10:20"))
        func entry(_ time: String) -> WidgetEntry? {
            timeline.entries.first { $0.date == at(wed, time) }
        }
        func circular(_ time: String) -> LockCircularContent? {
            entry(time).map { LockCircularContent($0) }
        }
        // Your train, with the bell: the clock time until 59 min before, then the minutes, the ring still whole.
        XCTAssertEqual(circular("10:30")?.glyph, .bell)
        XCTAssertEqual(circular("10:30")?.value, "11:30")
        XCTAssertNil(circular("10:30")?.caption)
        XCTAssertEqual(circular("10:31")?.value, "59")
        XCTAssertEqual(circular("10:31")?.caption, "min")
        XCTAssertEqual(circular("10:59")?.glyph, .bell)
        XCTAssertEqual(circular("10:59")?.ring, 1)
        // 30 min before: the hand-over (the train, not the bell) and the ring's start.
        XCTAssertEqual(circular("11:00")?.glyph, .train)
        XCTAssertEqual(circular("11:00")?.value, "30")
        XCTAssertEqual(circular("11:00")?.ring, 1)
        XCTAssertEqual(circular("11:00")?.ringInterval, at(wed, "11:00")...at(wed, "11:30"))
        XCTAssertEqual(circular("11:15")?.ring, 0.5)
        // The last minute, and at the departure the next train, an hour away: its clock time.
        XCTAssertEqual(circular("11:29")?.value, "now")
        XCTAssertEqual(circular("11:29")?.caption, "11:30")
        XCTAssertEqual(circular("11:29")?.ring, 0)
        XCTAssertEqual(circular("11:30")?.value, "12:30")

        // The rectangular at the same moments: Your train until 30 min before, then the next train.
        func header(_ time: String) -> LockRectangularContent.Header? {
            guard let moment = entry(time), case .train(let train) = LockRectangularContent(moment).body else { return nil }
            return train.header
        }
        XCTAssertEqual(header("10:59"), .yourTrain(to: "Union"))
        XCTAssertEqual(header("11:00"), .route(from: "Oakville", to: "Union"))
        // The Home Screen keeps Your train until it leaves.
        guard let handedOver = entry("11:00"), case .train(let small) = NextTrainContent(handedOver).body else {
            return XCTFail("Expected a train at 11:00")
        }
        XCTAssertEqual(small.isYourTrain, true)
    }
}
