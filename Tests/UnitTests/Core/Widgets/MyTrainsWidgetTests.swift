import XCTest
@testable import TrainTimes

/// My trains (TT-257, D131; board "Commute first"): the saved trains on every route, on the small, medium and Lock Screen
/// sizes, from `WidgetFixtures.commuteFile()`: Oakville ⇄ Union, the 7:58 AM to Union and the 5:13 PM home saved on
/// weekdays, Wed Nov 11, 2026.
final class MyTrainsWidgetTests: XCTestCase {
    private let wed = WidgetFixtures.day

    private func at(_ hour: Int, _ minute: Int, on day: ServiceDay? = nil) -> Date {
        WidgetFixtures.at(hour, minute, on: day ?? wed)
    }

    private func mine(_ entry: WidgetEntry, file: StaticString = #filePath, line: UInt = #line) -> WidgetEntry.MyTrains? {
        guard case .myTrains(let mine) = entry.state else {
            XCTFail("Expected My trains, got \(entry.state)", file: file, line: line)
            return nil
        }
        return mine
    }

    private func small(_ entry: WidgetEntry, file: StaticString = #filePath, line: UInt = #line) -> NextTrainContent.Train? {
        guard case .train(let train) = NextTrainContent(entry).body else {
            XCTFail("Expected a train", file: file, line: line)
            return nil
        }
        return train
    }

    private func rows(_ entry: WidgetEntry, file: StaticString = #filePath, line: UInt = #line) -> DeparturesContent.Rows? {
        guard case .rows(let rows) = DeparturesContent(entry).body else {
            XCTFail("Expected rows", file: file, line: line)
            return nil
        }
        return rows
    }

    private func second(_ rows: DeparturesContent.Rows?) -> DeparturesContent.Row? {
        if case .row(let row)? = rows?.second { row } else { nil }
    }

    private func rectangular(_ entry: WidgetEntry, file: StaticString = #filePath, line: UInt = #line) -> LockRectangularContent.Train? {
        guard case .train(let train) = LockRectangularContent(entry).body else {
            XCTFail("Expected a train", file: file, line: line)
            return nil
        }
        return train
    }

    // MARK: - The saved trains

    /// One saved train per alert, at its next departure, soonest first, on either route.
    func testTheSavedTrainsAreOnePerAlertSoonestFirst() {
        let morning = mine(WidgetFixtures.mine(at(7, 47)))
        XCTAssertEqual(morning?.saved.map(\.train.departure), [at(7, 58), at(17, 13)])
        XCTAssertEqual(morning?.saved.map(\.route), [WidgetFixtures.route, WidgetFixtures.route.reversed])
        XCTAssertEqual(morning?.saved.first?.after.map(\.departure), [at(8, 6), at(8, 28), at(8, 58)])
        // Once the 7:58 has left, it is tomorrow's.
        let later = mine(WidgetFixtures.mine(at(8, 0)))
        XCTAssertEqual(later?.saved.map(\.train.departure), [at(17, 13), at(7, 58, on: wed.adding(days: 1))])
        // Friday evening: Monday's, past the weekend.
        let friday = mine(WidgetFixtures.mine(at(19, 0, on: wed.adding(days: 2))))
        XCTAssertEqual(friday?.saved.map(\.train.key.serviceDay), [wed.adding(days: 5), wed.adding(days: 5)])
    }

    /// A file written before TT-257 has no alert ids: a saved train is told by its direction and trip.
    func testAFileWithoutAlertIdsGoesByTrip() {
        let old = mine(WidgetFixtures.mine(at(7, 47), file: WidgetFixtures.commuteFile(ids: false)))
        XCTAssertEqual(old?.saved.map(\.train.departure), [at(7, 58), at(17, 13)])
    }

    /// With no saved train the widget is the open route's, turned around at 12 PM, as A route with no stations shows it;
    /// its links still say My trains.
    func testWithNoSavedTrainTheOpenRouteShows() {
        let file = WidgetFixtures.commuteFile(saved: [])
        let entry = WidgetFixtures.mine(at(7, 47), file: file)
        let route = WidgetEntryBuilder.entry(file: file, route: nil, turnsAround: true, at: at(7, 47))
        XCTAssertEqual(entry.state, route.state)
        XCTAssertEqual(entry.mode, .myTrains)
        XCTAssertEqual(small(entry)?.isYourTrain, false)
        XCTAssertEqual(WidgetLink.mode(of: NextTrainContent(entry).link), .myTrains)
        // A route of its own on the widget is not used in My trains.
        let other = WidgetEntryBuilder.entry(
            file: file, route: WidgetFile.RouteKey(fromId: "UN", toId: "OA"), turnsAround: false, mode: .myTrains, at: at(7, 47)
        )
        XCTAssertEqual(other.state, route.state)
        // In the afternoon, the way home.
        XCTAssertEqual(NextTrainContent(WidgetFixtures.mine(at(16, 0), file: file)).header?.to, "Oakville")
    }

    func testRelevanceIsOneInTheHalfHourBeforeASavedTrain() {
        XCTAssertEqual(WidgetFixtures.mine(at(7, 40)).relevance, 1)
        XCTAssertEqual(WidgetFixtures.mine(at(6, 30)).relevance, 0)
        XCTAssertEqual(WidgetFixtures.mine(at(16, 50)).relevance, 1)
    }

    // MARK: - When

    /// The minutes from 2 h before, "now" in the last minute, else the day.
    func testWhenIsTheMinutesFrom2HoursElseTheDay() {
        let train = WidgetFixtures.train(7, 58)
        XCTAssertEqual(WidgetWhen(train, at: at(7, 57, on: wed).addingTimeInterval(1), fullWeekday: true), .now)
        XCTAssertEqual(WidgetWhen(train, at: at(7, 47), fullWeekday: true), .countdown("11 min"))
        XCTAssertEqual(WidgetWhen(train, at: at(5, 58), fullWeekday: true), .countdown("2 h"))
        XCTAssertEqual(WidgetWhen(train, at: at(5, 57), fullWeekday: true), .day("Today"))
        let thursday = WidgetFixtures.train(7, 58, on: wed.adding(days: 1))
        XCTAssertEqual(WidgetWhen(thursday, at: at(19, 0), fullWeekday: true), .day("Tomorrow"))
        let monday = WidgetFixtures.train(7, 58, on: wed.adding(days: 5))
        XCTAssertEqual(WidgetWhen(monday, at: at(19, 0), fullWeekday: true), .day("Monday"))
        XCTAssertEqual(WidgetWhen(monday, at: at(19, 0), fullWeekday: false), .day("Mon"))
        // A week or more on, the date as the Alerts tab writes it.
        let nextWeek = WidgetFixtures.train(7, 58, on: wed.adding(days: 7))
        XCTAssertEqual(WidgetWhen(nextWeek, at: at(19, 0), fullWeekday: true), .day("Wed 18"))
    }

    // MARK: - Small

    /// Your next train: always "Your train", "Then" the saved train after it.
    func testSmallShowsTheNextSavedTrainThenTheOneAfter() {
        let entry = WidgetFixtures.mine(at(7, 47))
        let train = small(entry)
        XCTAssertEqual(train?.isYourTrain, true)
        XCTAssertEqual(train?.time.full, "7:58 AM")
        XCTAssertEqual(train?.countdown, "11 min")
        XCTAssertNil(train?.day)
        XCTAssertEqual(train?.footer, NextTrainContent.Footer(label: .then, time: "5:13 PM", mark: nil))
        XCTAssertEqual(NextTrainContent(entry).header?.to, "Union")
        XCTAssertEqual(
            NextTrainContent(entry).link,
            WidgetLink.tagged(WidgetFixtures.train(7, 58).link, from: .nextTrain, mode: .myTrains)
        )
    }

    /// The afternoon turns to the way home by itself; "Then" is tomorrow's morning train with its weekday.
    func testSmallInTheAfternoon() {
        let entry = WidgetFixtures.mine(at(16, 40))
        XCTAssertEqual(NextTrainContent(entry).header?.to, "Oakville")
        XCTAssertEqual(small(entry)?.time.full, "5:13 PM")
        XCTAssertEqual(small(entry)?.countdown, "33 min")
        XCTAssertEqual(small(entry)?.footer, NextTrainContent.Footer(label: .then, time: "Thu 7:58 AM", mark: nil))
    }

    /// Nothing more today: the day in the countdown's place.
    func testSmallWritesTheDayWhenTheTrainIsFarOff() {
        let evening = small(WidgetFixtures.mine(at(19, 0)))
        XCTAssertEqual(evening?.day, "Tomorrow")
        XCTAssertEqual(evening?.footer?.time, "5:13 PM")
        XCTAssertEqual(small(WidgetFixtures.mine(at(19, 0, on: wed.adding(days: 2))))?.day, "Monday")
        XCTAssertEqual(small(WidgetFixtures.mine(at(5, 0)))?.day, "Today")
    }

    /// One saved train: "Then" is the train after it on its route.
    func testSmallWithOneSavedTrain() {
        let entry = WidgetFixtures.mine(at(7, 47), file: WidgetFixtures.commuteFile(saved: ["07:58"]))
        XCTAssertEqual(small(entry)?.footer, NextTrainContent.Footer(label: .then, time: "8:06 AM", mark: .express))
    }

    // MARK: - Medium

    /// Two-way commute: the next saved train on each route, the first's minutes in the accent, the other's day.
    func testMediumShowsASavedTrainOnEachRoute() {
        let entry = WidgetFixtures.mine(at(7, 47))
        let rows = rows(entry)
        XCTAssertNil(DeparturesContent(entry).header)
        XCTAssertEqual([rows?.first.header.from, rows?.first.header.to], ["Oakville", "Union"])
        XCTAssertEqual(rows?.first.isSaved, true)
        XCTAssertEqual(rows?.first.time.full, "7:58 AM")
        XCTAssertEqual(rows?.first.arrival, "8:38")
        XCTAssertEqual(rows?.first.when, .countdown("11 min"))
        XCTAssertEqual(rows?.first.isLead, true)
        let other = second(rows)
        XCTAssertEqual([other?.header.from, other?.header.to], ["Union", "Oakville"])
        XCTAssertEqual(other?.time.full, "5:13 PM")
        XCTAssertEqual(other?.arrival, "5:52")
        XCTAssertEqual(other?.when, .day("Today"))
        XCTAssertEqual(other?.isLead, false)
        // A tap outside the trains opens the Alerts tab; each row its train.
        XCTAssertEqual(DeparturesContent(entry).link, WidgetLink.tagged(WidgetLink.alerts(), from: .departures, mode: .myTrains))
        XCTAssertEqual(rows?.first.link, WidgetLink.tagged(WidgetFixtures.train(7, 58).link, from: .departures, mode: .myTrains))
    }

    /// The afternoon: the way home first, tomorrow's morning train under it.
    func testMediumTurnsByItself() {
        let rows = rows(WidgetFixtures.mine(at(16, 40)))
        XCTAssertEqual(rows?.first.header.to, "Oakville")
        XCTAssertEqual(rows?.first.when, .countdown("33 min"))
        XCTAssertEqual(second(rows)?.header.to, "Union")
        XCTAssertEqual(second(rows)?.when, .day("Tomorrow"))
        XCTAssertEqual(second(self.rows(WidgetFixtures.mine(at(16, 40, on: wed.adding(days: 2)))))?.when, .day("Mon"))
    }

    /// Saved trains on one route only: its next two.
    func testMediumWithSavedTrainsOnOneRoute() {
        let rows = rows(WidgetFixtures.mine(at(7, 47), file: WidgetFixtures.commuteFile(saved: ["07:58", "08:28"])))
        XCTAssertEqual(second(rows)?.time.full, "8:28 AM")
        XCTAssertEqual(second(rows)?.when, .countdown("41 min"))
        XCTAssertEqual(second(rows)?.isLead, false)
    }

    /// One saved train: "Next" with the trains after it on its route.
    func testMediumWithOneSavedTrain() {
        let rows = rows(WidgetFixtures.mine(at(7, 47), file: WidgetFixtures.commuteFile(saved: ["07:58"])))
        guard case .next(let later)? = rows?.second else { return XCTFail("Expected the Next line") }
        XCTAssertEqual(later.map(\.time), ["8:06", "8:28", "8:58"])
    }

    /// No saved train: the open route's row and "Next", with no bell.
    func testMediumWithNoSavedTrain() {
        let entry = WidgetFixtures.mine(at(7, 47), file: WidgetFixtures.commuteFile(saved: []))
        let rows = rows(entry)
        XCTAssertEqual(rows?.first.isSaved, false)
        XCTAssertEqual(rows?.first.time.digits, "7:58")
        guard case .next(let later)? = rows?.second else { return XCTFail("Expected the Next line") }
        XCTAssertEqual(later.map(\.time), ["8:06", "8:28", "8:58"])
        XCTAssertEqual(DeparturesContent(entry).header?.to, "Union")
    }

    // MARK: - Lock Screen

    /// More than 30 min before: Your train with its minutes or day, then the saved train after it that day.
    func testTheLockScreenShowsTheSavedTrain() {
        let early = rectangular(WidgetFixtures.mine(at(6, 30)))
        XCTAssertEqual(early?.header, .yourTrain(to: "Union"))
        XCTAssertEqual(early?.time.full, "7:58 AM")
        XCTAssertEqual(early?.note.plain, "in 1 h 28 min · then 5:13")
        XCTAssertEqual(early?.lead.plain, "in 1 h 28 min")
        XCTAssertEqual(early?.thenIsAlerted, true)
        // Another day: its day, and nothing after it from another day.
        let friday = rectangular(WidgetFixtures.mine(at(19, 0, on: wed.adding(days: 2))))
        XCTAssertEqual(friday?.note.plain, "Mon · then 5:13")
        let evening = rectangular(WidgetFixtures.mine(at(19, 0)))
        XCTAssertEqual(evening?.note.plain, "Tomorrow · then 5:13")
        // The afternoon: the way home, and no "then" from the next morning.
        let afternoon = rectangular(WidgetFixtures.mine(at(16, 40)))
        XCTAssertEqual(afternoon?.header, .yourTrain(to: "Oakville"))
        XCTAssertEqual(afternoon?.note.plain, "in 33 min")
        // One saved train: the train after it on its route.
        let one = rectangular(WidgetFixtures.mine(at(6, 30), file: WidgetFixtures.commuteFile(saved: ["07:58"])))
        XCTAssertEqual(one?.note.plain, "in 1 h 28 min · then 8:06")
        XCTAssertEqual(one?.thenIsAlerted, false)
        XCTAssertEqual(
            LockRectangularContent(WidgetFixtures.mine(at(6, 30))).link,
            WidgetLink.tagged(WidgetFixtures.train(7, 58).link, from: .lockRectangular, mode: .myTrains)
        )
    }

    /// In the 30 min before, its Live Activity has the train: the Lock Screen shows its route's next trains.
    func testTheLockScreenHandsOverIn30Minutes() {
        let handedOver = rectangular(WidgetFixtures.mine(at(7, 28)))
        XCTAssertEqual(handedOver?.header, .route(from: "Oakville", to: "Union"))
        XCTAssertEqual(handedOver?.note.plain, "in 30 min · then 8:06")
        XCTAssertEqual(rectangular(WidgetFixtures.mine(at(7, 27)))?.header, .yourTrain(to: "Union"))
        XCTAssertEqual(
            LockRectangularContent(WidgetFixtures.mine(at(7, 47))).link,
            WidgetLink.tagged(WidgetFixtures.header().link, from: .lockRectangular, mode: .myTrains)
        )
        // The Home Screen keeps Your train.
        XCTAssertEqual(small(WidgetFixtures.mine(at(7, 47)))?.isYourTrain, true)
    }

    func testTheCircularShowsTheSavedTrain() {
        let early = LockCircularContent(WidgetFixtures.mine(at(6, 30)))
        XCTAssertEqual(early.glyph, .bell)
        XCTAssertEqual(early.value, "7:58")
        XCTAssertEqual(early.ring, 1)
        XCTAssertEqual(early.ringInterval, at(7, 28)...at(7, 58))
        let close = LockCircularContent(WidgetFixtures.mine(at(7, 20)))
        XCTAssertEqual(close.value, "38")
        XCTAssertEqual(close.caption, "min")
        XCTAssertEqual(close.glyph, .bell)
        // Handed over: the train glyph and the next train's minutes.
        let handedOver = LockCircularContent(WidgetFixtures.mine(at(7, 47)))
        XCTAssertEqual(handedOver.glyph, .train)
        XCTAssertEqual(handedOver.value, "11")
        // Another day: the clock time, no ring.
        let tomorrow = LockCircularContent(WidgetFixtures.mine(at(19, 0)))
        XCTAssertEqual(tomorrow.value, "7:58")
        XCTAssertNil(tomorrow.ring)
        XCTAssertNil(tomorrow.ringInterval)
    }

    func testTheInlineNamesTheSavedTrainAndItsDay() {
        let early = LockInlineContent(WidgetFixtures.mine(at(6, 30)))
        XCTAssertEqual(early.glyph, .bell)
        XCTAssertEqual(early.text, "7:58 AM to Union")
        XCTAssertEqual(early.short, "7:58 AM")
        XCTAssertEqual(LockInlineContent(WidgetFixtures.mine(at(19, 0))).text, "Thu 7:58 AM to Union")
        XCTAssertEqual(LockInlineContent(WidgetFixtures.mine(at(7, 47))).glyph, .train)
    }

    // MARK: - Timeline

    /// Far from a saved train the timeline is short: its minutes start 2 h before it, with no entry for the open route's
    /// trains.
    func testTheTimelineCountsFrom2HoursBeforeTheSavedTrain() {
        let timeline = WidgetEntryBuilder.timeline(file: WidgetFixtures.commuteFile(), route: nil, turnsAround: true, mode: .myTrains, now: at(4, 0))
        // Now, then the countdown's start and the minutes of the next 2 h after it; WidgetKit is asked again an hour on.
        XCTAssertEqual(timeline.entries.map(\.date), [at(4, 0), at(5, 58), at(5, 59), at(6, 0)])
        XCTAssertEqual(timeline.reloadAt, at(5, 0))
        XCTAssertTrue(timeline.entries.allSatisfy { $0.mode == .myTrains })
    }

    /// A saved train late in the day: the trains after it stop at its service day's last train.
    func testTheTrainsAfterASavedTrainStopAtItsDaysLast() {
        guard case .myTrains(let mine) = WidgetFixtures.mine(at(17, 0), file: WidgetFixtures.commuteFile(saved: ["17:43"])).state else {
            return XCTFail("Expected My trains")
        }
        XCTAssertEqual(mine.saved.map(\.train.departure), [at(17, 43)])
        XCTAssertEqual(mine.saved.first?.after.map(\.departure), [at(18, 13)])
    }

    /// A countdown that starts late in the timeline is asked for an hour before it starts, so the next timeline has an hour
    /// of minutes in hand when iOS asks late; that one is asked again an hour on.
    func testACountdownStartingLaterIsAskedForAnHourBefore() {
        let night = WidgetEntryBuilder.timeline(file: WidgetFixtures.commuteFile(), route: nil, turnsAround: true, mode: .myTrains, now: at(3, 0))
        XCTAssertEqual(night.entries.map(\.date), [at(3, 0), at(5, 58)])
        XCTAssertEqual(night.reloadAt, at(4, 58))
        // Built then, it writes the minutes from the countdown's start to an hour past its own reload.
        let next = WidgetEntryBuilder.timeline(file: WidgetFixtures.commuteFile(), route: nil, turnsAround: true, mode: .myTrains, now: at(4, 58))
        XCTAssertEqual(next.reloadAt, at(5, 58))
        let dates = Set(next.entries.map(\.date))
        XCTAssertTrue((0...60).allSatisfy { dates.contains(at(5, 58).addingTimeInterval(TimeInterval($0 * 60))) })
        XCTAssertLessThan(next.entries.count, 150)
    }

    /// Once the saved train has left and the next is hours away, no more minutes.
    func testTheTimelineStopsCountingWhenTheSavedTrainLeaves() {
        let timeline = WidgetEntryBuilder.timeline(file: WidgetFixtures.commuteFile(), route: nil, turnsAround: true, mode: .myTrains, now: at(7, 30))
        XCTAssertEqual(timeline.entries.last?.date, at(7, 58))
        XCTAssertLessThan(timeline.entries.count, 150)
    }

    /// With no saved train, the open route's timeline.
    func testTheTimelineWithNoSavedTrainIsTheOpenRoutes() {
        let file = WidgetFixtures.commuteFile(saved: [])
        let mine = WidgetEntryBuilder.timeline(file: file, route: nil, turnsAround: true, mode: .myTrains, now: at(7, 0))
        let route = WidgetEntryBuilder.timeline(file: file, route: nil, turnsAround: true, mode: .route, now: at(7, 0))
        XCTAssertEqual(mine.entries.map(\.state), route.entries.map(\.state))
        XCTAssertEqual(mine.reloadAt, route.reloadAt)
    }
}
