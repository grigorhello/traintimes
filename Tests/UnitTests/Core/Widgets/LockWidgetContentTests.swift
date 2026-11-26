import WidgetKit
import XCTest
@testable import TrainTimes

/// What Next train writes and opens on the Lock Screen (TT-184, D115), at fixed Toronto times, from the board states in
/// `WidgetFixtures`.
final class LockWidgetContentTests: XCTestCase {
    private func rectangular(_ entry: WidgetEntry, file: StaticString = #filePath, line: UInt = #line) -> LockRectangularContent.Train? {
        guard case .train(let train) = LockRectangularContent(entry).body else {
            XCTFail("Expected a train", file: file, line: line)
            return nil
        }
        return train
    }

    private func noTrains(_ entry: WidgetEntry, file: StaticString = #filePath, line: UInt = #line) -> LockRectangularContent.NoTrains? {
        guard case .noTrains(let quiet) = LockRectangularContent(entry).body else {
            XCTFail("Expected no trains", file: file, line: line)
            return nil
        }
        return quiet
    }

    private func message(_ entry: WidgetEntry) -> WidgetMessage? {
        if case .message(let message) = LockRectangularContent(entry).body { message } else { nil }
    }

    /// A line with ordinary spaces: a time is held together by no-break spaces.
    private func plain(_ text: WidgetText?) -> String? {
        text?.plain.replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private func strong(_ text: WidgetText?) -> [String] {
        (text?.pieces ?? []).filter(\.isStrong).map { $0.text.replacingOccurrences(of: "\u{00A0}", with: " ") }
    }

    /// One train, then another day's first: a line whose last train leaves in the morning.
    private func morningOnly(at date: Date) -> WidgetEntry {
        let tomorrow = WidgetFixtures.day.adding(days: 1)
        let trains = WidgetEntry.Trains(
            header: WidgetFixtures.header(), trains: [WidgetFixtures.train(8, 0), WidgetFixtures.train(6, 10, on: tomorrow)]
        )
        return WidgetFixtures.entry(date, .trains(trains))
    }

    // MARK: - Rectangular

    func testRectangularShowsTheNextTrainItsCountdownAndTheTrainAfter() {
        let train = rectangular(WidgetFixtures.nextTrain())
        XCTAssertEqual(train?.header, .route(from: "Oakville", to: "Union"))
        XCTAssertEqual(train?.time.digits, "7:58")
        XCTAssertEqual(train?.time.period, "AM")
        XCTAssertEqual(train?.isExpress, false)
        XCTAssertEqual(train?.note.plain, "in 11 min · then 8:06")
        XCTAssertEqual(strong(train?.note), ["8:06"])
        // Then carries the bell only: the 8:06 is an express, with no alert.
        XCTAssertEqual(train?.thenIsAlerted, false)
    }

    func testTheBoltIsOnTheTimeAndTheBellOnThen() {
        let train = rectangular(WidgetFixtures.expressNext)
        XCTAssertEqual(train?.time.full, "8:06 AM")
        XCTAssertEqual(train?.isExpress, true)
        XCTAssertEqual(train?.note.plain, "in 5 min · then 8:28")
        XCTAssertEqual(train?.thenIsAlerted, true)
    }

    func testYourTrainFrom2HoursBeforeNamesTheEarlierTrain() {
        let train = rectangular(WidgetFixtures.yourTrain)
        XCTAssertEqual(train?.header, .yourTrain(to: "Union"))
        XCTAssertEqual(train?.time.full, "8:28 AM")
        XCTAssertEqual(train?.note.plain, "in 41 min · earlier 7:58")
        XCTAssertEqual(strong(train?.note), ["7:58"])
        XCTAssertEqual(train?.thenIsAlerted, false)
    }

    /// Your train that is the next to leave has no earlier train: the third row names the one after it.
    func testYourTrainThatLeavesFirstNamesTheTrainAfter() {
        var trains = WidgetEntry.Trains(
            header: WidgetFixtures.header(), trains: [WidgetFixtures.train(8, 28, alerted: true), WidgetFixtures.train(8, 58)]
        )
        trains.yourTrain = 0
        let train = rectangular(WidgetFixtures.entry(WidgetFixtures.at(7, 47), .trains(trains)))
        XCTAssertEqual(train?.header, .yourTrain(to: "Union"))
        XCTAssertEqual(train?.note.plain, "in 41 min · then 8:58")
    }

    /// From 30 min before an alerted train its Live Activity shows it: every Lock Screen size goes back to the next train,
    /// the bell stays on "then", and the Home Screen keeps Your train.
    func testFrom30MinutesBeforeYourTrainTheLockScreenShowsTheNextTrain() {
        let before = WidgetFixtures.handOver(at: WidgetFixtures.at(7, 57))
        XCTAssertEqual(rectangular(before)?.header, .yourTrain(to: "Union"))
        XCTAssertEqual(rectangular(before)?.time.full, "8:28 AM")
        XCTAssertEqual(rectangular(before)?.note.plain, "in 31 min · earlier 8:06")
        XCTAssertEqual(LockCircularContent(before).glyph, .bell)
        XCTAssertEqual(LockCircularContent(before).value, "31")
        XCTAssertEqual(LockInlineContent(before).glyph, .bell)
        XCTAssertEqual(LockInlineContent(before).text, "8:28 AM to Union")

        let handedOver = WidgetFixtures.handOver()
        XCTAssertEqual(handedOver.date, WidgetFixtures.at(8, 28).addingTimeInterval(-LockWidget.handOverLead))
        let train = rectangular(handedOver)
        XCTAssertEqual(train?.header, .route(from: "Oakville", to: "Union"))
        XCTAssertEqual(train?.time.full, "8:06 AM")
        XCTAssertEqual(train?.isExpress, true)
        XCTAssertEqual(train?.note.plain, "in 8 min · then 8:28")
        XCTAssertEqual(train?.thenIsAlerted, true)
        XCTAssertEqual(LockCircularContent(handedOver).glyph, .train)
        XCTAssertEqual(LockCircularContent(handedOver).value, "8")
        XCTAssertEqual(LockInlineContent(handedOver).glyph, .train)
        XCTAssertEqual(LockInlineContent(handedOver).text, "8:06 AM to Union")

        guard case .train(let small) = NextTrainContent(handedOver).body else { return XCTFail("Expected a train") }
        XCTAssertEqual(small.isYourTrain, true)
        XCTAssertEqual(small.time.digits, "8:28")
    }

    func testTheLastMinuteReadsNow() {
        XCTAssertEqual(rectangular(WidgetFixtures.leavingNow)?.note.plain, "now · then 8:28")
        // A minute and a second before, it still counts.
        let before = WidgetFixtures.entry(WidgetFixtures.at(8, 4, second: 59), WidgetFixtures.leavingNow.state)
        XCTAssertEqual(rectangular(before)?.note.plain, "in 2 min · then 8:28")
    }

    func testTheLastTrainSaysSoFrom10PM() {
        let last = rectangular(WidgetFixtures.lastTrain)
        XCTAssertEqual(last?.time.full, "11:47 PM")
        XCTAssertEqual(last?.note.plain, "Last train · in 32 min")
        XCTAssertEqual(strong(last?.note), [])
        // The train before it names it like any other.
        XCTAssertEqual(rectangular(WidgetFixtures.oneLater)?.note.plain, "in 27 min · then 11:47")
        let leaving = WidgetFixtures.entry(WidgetFixtures.at(23, 46, second: 30), WidgetFixtures.lastTrain.state)
        XCTAssertEqual(rectangular(leaving)?.note.plain, "Last train · now")
    }

    /// Another day's first train is never "then": the countdown stands alone.
    func testAnotherDaysTrainIsNotThen() {
        XCTAssertEqual(rectangular(morningOnly(at: WidgetFixtures.at(7, 47)))?.note.plain, "in 13 min")
    }

    func testAfterTheLastTrainNoTrainsTonightOverTheFirstTrain() {
        let quiet = noTrains(WidgetFixtures.afterLastTrain)
        XCTAssertEqual(quiet?.from, "Oakville")
        XCTAssertEqual(quiet?.to, "Union")
        XCTAssertEqual(quiet?.when, "tonight")
        XCTAssertEqual(plain(quiet?.note), "First train 5:43 AM")
        XCTAssertEqual(strong(quiet?.note), ["5:43 AM"])
        // A last train that left before 6 PM leaves the rest of the day, not the night.
        let morning = WidgetFixtures.entry(
            WidgetFixtures.at(9, 0), .noMoreTrainsTonight(header: WidgetFixtures.header(), since: WidgetFixtures.at(8, 0), next: nil)
        )
        XCTAssertEqual(noTrains(morning)?.when, "today")
        XCTAssertNil(noTrains(morning)?.note)
    }

    func testADayWithNoTrainsNamesTheNextOne() {
        let quiet = noTrains(WidgetFixtures.noTrainsToday)
        XCTAssertEqual(quiet?.from, "Union")
        XCTAssertEqual(quiet?.to, "Oakville")
        XCTAssertEqual(quiet?.when, "today")
        XCTAssertEqual(plain(quiet?.note), "Next Mon 6:10 AM")
    }

    func testNotSetUpShowsTheMessagesTwoLines() {
        XCTAssertEqual(message(WidgetFixtures.notLoaded)?.title, "Open Train Times once")
        XCTAssertEqual(message(WidgetFixtures.notLoaded)?.detail?.plain, "to load the timetable.")
        XCTAssertEqual(message(WidgetFixtures.noRoute)?.title, "Choose your route")
        XCTAssertEqual(message(WidgetFixtures.noRoute)?.detail?.plain, "in Train Times.")
        XCTAssertEqual(message(WidgetFixtures.outOfDate)?.title, "Timetable out of date")
        XCTAssertEqual(message(WidgetFixtures.outOfDate)?.detail?.plain, "Open Train Times to update it.")
    }

    // MARK: - Circular

    func testCircularCountsTheMinutesInARingThatEmptiesOverTheLast30() {
        let next = LockCircularContent(WidgetFixtures.nextTrain())
        XCTAssertEqual(next.glyph, .train)
        XCTAssertEqual(next.value, "11")
        XCTAssertEqual(next.caption, "min")
        XCTAssertEqual(next.ring ?? -1, 11.0 / 30.0, accuracy: 0.0001)
        XCTAssertEqual(next.ringInterval, WidgetFixtures.at(7, 28)...WidgetFixtures.at(7, 58))
        // Half way through the 30 min, half the ring; before them, the whole ring.
        XCTAssertEqual(LockCircularContent(WidgetFixtures.farTrain(at: WidgetFixtures.at(7, 43))).ring ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(LockCircularContent(WidgetFixtures.farTrain(at: WidgetFixtures.at(7, 28))).ring, 1)
        XCTAssertEqual(LockCircularContent(WidgetFixtures.farTrain(at: WidgetFixtures.at(7, 20))).ring, 1)
    }

    func testCircularShowsTheBellForYourTrain() {
        let yours = LockCircularContent(WidgetFixtures.yourTrain)
        XCTAssertEqual(yours.glyph, .bell)
        XCTAssertEqual(yours.value, "41")
        XCTAssertEqual(yours.caption, "min")
        XCTAssertEqual(yours.ring, 1)
        XCTAssertEqual(yours.ringInterval, WidgetFixtures.at(7, 58)...WidgetFixtures.at(8, 28))
    }

    /// An hour or more away the circle shows the clock time; from 59 min, the minutes, so it never reads "60 min" (TT-246,
    /// D123).
    func testCircularShowsTheClockTimeUntil59MinutesBefore() {
        let far = LockCircularContent(WidgetFixtures.farTrain())
        XCTAssertEqual(far.value, "7:58")
        XCTAssertNil(far.caption)
        XCTAssertEqual(far.ring, 1)
        XCTAssertEqual(LockCircularContent(WidgetFixtures.farTrain(at: WidgetFixtures.at(6, 58))).value, "7:58")
        let hour = LockCircularContent(WidgetFixtures.farTrain(at: WidgetFixtures.at(6, 59)))
        XCTAssertEqual(hour.value, "59")
        XCTAssertEqual(hour.caption, "min")
        XCTAssertEqual(hour.ring, 1)
    }

    func testCircularReadsNowOverTheTimeInTheLastMinute() {
        let leaving = LockCircularContent(WidgetFixtures.leavingNow)
        XCTAssertEqual(leaving.value, "now")
        XCTAssertEqual(leaving.caption, "8:06")
        XCTAssertEqual(leaving.ring, 0)
        let before = LockCircularContent(WidgetFixtures.entry(WidgetFixtures.at(8, 4, second: 59), WidgetFixtures.leavingNow.state))
        XCTAssertEqual(before.value, "2")
    }

    func testCircularWithNoTrainShowsTheNextOnesTimeOrTheTrainAlone() {
        let after = LockCircularContent(WidgetFixtures.afterLastTrain)
        XCTAssertEqual(after.glyph, .train)
        XCTAssertEqual(after.value, "5:43")
        XCTAssertNil(after.caption)
        XCTAssertNil(after.ring)
        XCTAssertNil(after.ringInterval)
        XCTAssertEqual(LockCircularContent(WidgetFixtures.noTrainsToday).value, "6:10")
        for entry in [WidgetFixtures.notLoaded, WidgetFixtures.noRoute, WidgetFixtures.outOfDate] {
            let content = LockCircularContent(entry)
            XCTAssertEqual(content.glyph, .train)
            XCTAssertNil(content.value)
            XCTAssertNil(content.ring)
        }
    }

    // MARK: - Inline

    /// The clock time and the destination, never a countdown, whatever the moment.
    func testInlineIsTheClockTimeAndTheDestination() {
        let next = LockInlineContent(WidgetFixtures.nextTrain())
        XCTAssertEqual(next.glyph, .train)
        XCTAssertEqual(next.text, "7:58 AM to Union")
        XCTAssertEqual(next.short, "7:58 AM")
        XCTAssertEqual(LockInlineContent(WidgetFixtures.yourTrain).glyph, .bell)
        XCTAssertEqual(LockInlineContent(WidgetFixtures.yourTrain).text, "8:28 AM to Union")
        XCTAssertEqual(LockInlineContent(WidgetFixtures.leavingNow).text, "8:06 AM to Union")
        XCTAssertEqual(LockInlineContent(WidgetFixtures.lastTrain).text, "11:47 PM to Union")
        XCTAssertEqual(LockInlineContent(WidgetFixtures.evening).text, "6:13 PM to Oakville")
    }

    func testInlineWithNoTrainNamesTheNextOneOrSaysWhatToDo() {
        func text(_ entry: WidgetEntry) -> String {
            LockInlineContent(entry).text.replacingOccurrences(of: "\u{00A0}", with: " ")
        }
        XCTAssertEqual(text(WidgetFixtures.afterLastTrain), "First train 5:43 AM")
        XCTAssertNil(LockInlineContent(WidgetFixtures.afterLastTrain).short)
        XCTAssertEqual(LockInlineContent(WidgetFixtures.afterLastTrain).glyph, .train)
        XCTAssertEqual(text(WidgetFixtures.noTrainsToday), "Next Mon 6:10 AM")
        XCTAssertEqual(text(WidgetFixtures.notLoaded), "Open Train Times once")
        XCTAssertEqual(text(WidgetFixtures.noRoute), "Choose your route")
        XCTAssertEqual(text(WidgetFixtures.outOfDate), "Timetable out of date")
        // No later train in the file: the message's first line.
        let none = WidgetFixtures.entry(
            WidgetFixtures.at(23, 50), .noMoreTrainsTonight(header: WidgetFixtures.header(), since: WidgetFixtures.at(23, 47), next: nil)
        )
        XCTAssertEqual(text(none), "No more trains tonight")
    }

    // MARK: - Time format and links

    func testTimesFollowTheTimeFormat() {
        let entry = WidgetFixtures.nextTrain(format: .twentyFourHour)
        let train = rectangular(entry)
        XCTAssertEqual(train?.time.digits, "07:58")
        XCTAssertNil(train?.time.period)
        XCTAssertEqual(train?.note.plain, "in 11 min · then 08:06")
        XCTAssertEqual(LockInlineContent(entry).text, "07:58 to Union")
        XCTAssertEqual(LockCircularContent(WidgetFixtures.farTrain(format: .twentyFourHour)).value, "07:58")
        let evening = WidgetFixtures.entry(WidgetFixtures.at(23, 46, second: 30), WidgetFixtures.lastTrain.state, format: .twentyFourHour)
        XCTAssertEqual(LockCircularContent(evening).caption, "23:47")
    }

    /// Each size opens Schedule on the widget's route at Now, never a train, and names itself for `widget_opened`.
    func testEverySizeOpensScheduleOnItsRouteAndNamesItself() {
        let route = WidgetFixtures.header().link
        for entry in [WidgetFixtures.nextTrain(), WidgetFixtures.yourTrain, WidgetFixtures.afterLastTrain, WidgetFixtures.outOfDate] {
            XCTAssertEqual(LockRectangularContent(entry).link, WidgetLink.tagged(route, from: .lockRectangular))
            XCTAssertEqual(LockCircularContent(entry).link, WidgetLink.tagged(route, from: .lockCircular))
            XCTAssertEqual(LockInlineContent(entry).link, WidgetLink.tagged(route, from: .lockInline))
        }
        // The way home links the way home.
        XCTAssertEqual(
            LockRectangularContent(WidgetFixtures.evening).link, WidgetLink.tagged(WidgetFixtures.header(home: true).link, from: .lockRectangular)
        )
        // With no route yet, the Schedule tab, where the app shows the route form.
        for entry in [WidgetFixtures.notLoaded, WidgetFixtures.noRoute] {
            XCTAssertEqual(LockRectangularContent(entry).link, WidgetLink.tagged(WidgetLink.route(nil), from: .lockRectangular))
            XCTAssertEqual(LockCircularContent(entry).link, WidgetLink.tagged(WidgetLink.route(nil), from: .lockCircular))
            XCTAssertEqual(LockInlineContent(entry).link, WidgetLink.tagged(WidgetLink.route(nil), from: .lockInline))
        }
        let link = LockCircularContent(WidgetFixtures.nextTrain()).link
        XCTAssertEqual(WidgetLink.widget(of: link), .lockCircular)
        XCTAssertEqual(NotificationLink(url: link, today: WidgetFixtures.day), .route(originId: "OA", destinationId: "UN"))
        XCTAssertEqual(link.absoluteString, "traintimes://route?destinationId=UN&originId=OA&source=widget&widget=lock_circular")
    }

    // MARK: - Analytics

    func testLockScreenSizesHaveNamesOfTheirOwn() {
        XCTAssertEqual(WidgetKind(kind: "NextTrain", family: .systemSmall), .nextTrain)
        XCTAssertEqual(WidgetKind(kind: "NextTrain", family: .accessoryRectangular), .lockRectangular)
        XCTAssertEqual(WidgetKind(kind: "NextTrain", family: .accessoryCircular), .lockCircular)
        XCTAssertEqual(WidgetKind(kind: "NextTrain", family: .accessoryInline), .lockInline)
        XCTAssertEqual(WidgetKind(kind: "Departures", family: .systemMedium), .departures)
        XCTAssertNil(WidgetKind(kind: "RideActivity", family: .accessoryCircular))
        XCTAssertEqual(WidgetKind.lockRectangular.rawValue, "lock_rectangular")
        XCTAssertEqual(WidgetKind.lockCircular.rawValue, "lock_circular")
        XCTAssertEqual(WidgetKind.lockInline.rawValue, "lock_inline")
        XCTAssertEqual(WidgetKind.allCases.filter(\.isOnLockScreen).map(\.kind), ["NextTrain", "NextTrain", "NextTrain"])
        XCTAssertEqual(
            AnalyticsEvent.widgetOpened(.lockInline, opensTrip: false).properties, ["widget": .string("lock_inline"), "target": .string("route")]
        )
    }

    @MainActor
    func testWidgetsPlacedCountsTheLockScreenSizesTogether() {
        let recorder = RecordingAnalytics.install()
        defer { Analytics.tracker = nil }
        let defaults = UserDefaults.ephemeral()
        // A build before the Lock Screen sizes stored the Home Screen's two counts: the same widgets send nothing new.
        defaults.set("1,0", forKey: WidgetsPlacedCount.key)
        let count = WidgetsPlacedCount(defaults: defaults)
        let small = PlacedWidget(kind: .nextTrain, route: nil)
        count.report([small])
        XCTAssertEqual(recorder.events, [])

        count.report([small, PlacedWidget(kind: .lockCircular, route: nil), PlacedWidget(kind: .lockInline, route: nil)])
        XCTAssertEqual(recorder.events, [.widgetsPlaced(nextTrain: 1, departures: 0, lock: 2)])
        XCTAssertEqual(recorder.events.last?.properties, ["next_train": .int(1), "departures": .int(0), "lock": .int(2)])
        count.report([small, PlacedWidget(kind: .lockRectangular, route: nil), PlacedWidget(kind: .lockCircular, route: nil)])
        XCTAssertEqual(recorder.events.count, 1)
    }
}
