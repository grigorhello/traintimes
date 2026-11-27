import XCTest
@testable import TrainTimes

/// What the two Home Screen widgets write and open (TT-183), from the board states in `WidgetFixtures`.
final class WidgetContentTests: XCTestCase {
    private func smallTrain(_ entry: WidgetEntry, file: StaticString = #filePath, line: UInt = #line) -> NextTrainContent.Train? {
        guard case .train(let train) = NextTrainContent(entry).body else {
            XCTFail("Expected a train", file: file, line: line)
            return nil
        }
        return train
    }

    private func mediumRows(_ entry: WidgetEntry, file: StaticString = #filePath, line: UInt = #line) -> DeparturesContent.Rows? {
        guard case .rows(let rows) = DeparturesContent(entry).body else {
            XCTFail("Expected rows", file: file, line: line)
            return nil
        }
        return rows
    }

    /// The second row's train, or nil under "Next".
    private func secondRow(_ rows: DeparturesContent.Rows?) -> DeparturesContent.Row? {
        if case .row(let row)? = rows?.second { row } else { nil }
    }

    /// The "Next" line's times; nil under a second row.
    private func nextTimes(_ rows: DeparturesContent.Rows?) -> [String]? {
        if case .next(let later)? = rows?.second { later.map(\.time) } else { nil }
    }

    private func message(_ body: NextTrainContent.Body) -> WidgetMessage? {
        if case .message(let message) = body { message } else { nil }
    }

    private func message(_ body: DeparturesContent.Body) -> WidgetMessage? {
        if case .message(let message) = body { message } else { nil }
    }

    /// A detail with ordinary spaces: its times, and "arrives" with its time, are held together by no-break spaces.
    private func plain(_ text: WidgetText?) -> String? {
        text?.plain.replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private func pieces(_ text: WidgetText?) -> [WidgetText.Piece] {
        (text?.pieces ?? []).map {
            WidgetText.Piece(text: $0.text.replacingOccurrences(of: "\u{00A0}", with: " "), isStrong: $0.isStrong)
        }
    }

    // MARK: - Next train

    func testNextTrainShowsTheTimeAndThenTheExpressAfterIt() {
        let content = NextTrainContent(WidgetFixtures.nextTrain())
        XCTAssertEqual(content.header?.to, "Union")
        XCTAssertEqual(content.header?.line?.id, "LW")
        let train = smallTrain(WidgetFixtures.nextTrain())
        XCTAssertEqual(train?.time.digits, "7:58")
        XCTAssertEqual(train?.time.period, "AM")
        XCTAssertEqual(train?.departure, WidgetFixtures.at(7, 58))
        XCTAssertEqual(train?.isExpress, false)
        XCTAssertEqual(train?.isYourTrain, false)
        XCTAssertEqual(train?.isLeavingNow, false)
        XCTAssertEqual(train?.footer, NextTrainContent.Footer(label: .then, time: "8:06 AM", mark: .express))
    }

    func testThenCarriesTheBellOfAnAlertedTrain() {
        let train = smallTrain(WidgetFixtures.expressNext)
        XCTAssertEqual(train?.isExpress, true)
        XCTAssertEqual(train?.footer, NextTrainContent.Footer(label: .then, time: "8:28 AM", mark: .alert))
    }

    func testYourTrainTakesTheBigSlotWithTheEarlierTrainUnderIt() {
        let train = smallTrain(WidgetFixtures.yourTrain)
        XCTAssertEqual(train?.isYourTrain, true)
        XCTAssertEqual(train?.time.digits, "8:28")
        XCTAssertEqual(train?.footer, NextTrainContent.Footer(label: .earlier, time: "7:58 AM", mark: nil))
        XCTAssertEqual(
            NextTrainContent(WidgetFixtures.yourTrain).link,
            WidgetLink.tagged(WidgetFixtures.train(8, 28).link, from: .nextTrain)
        )
    }

    func testTheLastMinuteReadsNow() {
        XCTAssertEqual(smallTrain(WidgetFixtures.leavingNow)?.isLeavingNow, true)
        XCTAssertEqual(mediumRows(WidgetFixtures.leavingNow)?.first.when, .now)
        // A minute and a second before, it still counts.
        let before = WidgetFixtures.entry(WidgetFixtures.at(8, 4, second: 59), WidgetFixtures.leavingNow.state)
        XCTAssertEqual(smallTrain(before)?.isLeavingNow, false)
    }

    func testTheLastTrainSaysSoWithTomorrowsFirstUnderIt() {
        let train = smallTrain(WidgetFixtures.lastTrain)
        XCTAssertEqual(train?.isLastTrain, true)
        XCTAssertEqual(train?.time.full, "11:47 PM")
        XCTAssertEqual(train?.footer, NextTrainContent.Footer(label: .first, time: "5:43 AM", mark: nil))
        // The train before the last one keeps "Then".
        let before = smallTrain(WidgetFixtures.oneLater)
        XCTAssertEqual(before?.isLastTrain, false)
        XCTAssertEqual(before?.footer, NextTrainContent.Footer(label: .then, time: "11:47 PM", mark: nil))
    }

    /// The day's last train before 10 PM (a line with morning trains only): the next one is another day's first, not "Then".
    func testATrainOnAnotherDayIsFirstNotThen() {
        let tomorrow = WidgetFixtures.day.adding(days: 1)
        let list = WidgetEntry.Trains(
            header: WidgetFixtures.header(), trains: [WidgetFixtures.train(10, 30), WidgetFixtures.train(6, 10, on: tomorrow)]
        )
        let footer = smallTrain(WidgetFixtures.entry(WidgetFixtures.at(10, 0), .trains(list)))?.footer
        XCTAssertEqual(footer?.label, .first)
        XCTAssertEqual(footer?.time, "6:10 AM")
        XCTAssertNil(footer?.mark)
    }

    func testATrainWithNoneAfterItHasNoFooter() {
        let state = WidgetEntry.State.trains(WidgetEntry.Trains(header: WidgetFixtures.header(), trains: [WidgetFixtures.train(21, 30)]))
        XCTAssertNil(smallTrain(WidgetFixtures.entry(WidgetFixtures.at(21, 0), state))?.footer)
    }

    func testThe24HourClockHasNoPeriod() {
        let train = smallTrain(WidgetFixtures.nextTrain(format: .twentyFourHour))
        XCTAssertEqual(train?.time.digits, "07:58")
        XCTAssertNil(train?.time.period)
        XCTAssertEqual(train?.footer?.time, "08:06")
    }

    // MARK: - Departures

    /// A route (TT-257, D131): one row, the next train with its route, minutes and arrival, then "Next" with the trains
    /// after it that day.
    func testDeparturesShowsTheNextTrainAndTheTrainsAfterIt() {
        let rows = mediumRows(WidgetFixtures.nextTrain())
        XCTAssertEqual(rows?.first.time.full, "7:58 AM")
        XCTAssertEqual(rows?.first.arrival, "8:38")
        XCTAssertEqual(rows?.first.when, .countdown("11 min"))
        XCTAssertEqual(rows?.first.isLead, true)
        XCTAssertEqual(rows?.first.isSaved, false)
        XCTAssertEqual([rows?.first.header.from, rows?.first.header.to], ["Oakville", "Union"])
        XCTAssertEqual(nextTimes(rows), ["8:06", "8:28"])
        let header = DeparturesContent(WidgetFixtures.nextTrain()).header
        XCTAssertEqual([header?.from, header?.to], ["Oakville", "Union"])
        // Your train is the small widget's: the first to leave stays in front, and a saved train in "Next" is just a time.
        XCTAssertEqual(mediumRows(WidgetFixtures.yourTrain)?.first.time.digits, "7:58")
        // The minutes at any distance on a route, "now" in the last minute.
        XCTAssertEqual(mediumRows(WidgetFixtures.farTrain())?.first.when, .countdown("1 h 28 min"))
        XCTAssertEqual(mediumRows(WidgetFixtures.leavingNow)?.first.when, .now)
    }

    func testTheNextLineShowsOneTimeOrNone() {
        XCTAssertEqual(nextTimes(mediumRows(WidgetFixtures.oneLater)), ["11:47"])
        XCTAssertNil(mediumRows(WidgetFixtures.lastTrain)?.second)
    }

    func testDeparturesLinks() {
        let content = DeparturesContent(WidgetFixtures.nextTrain())
        let rows = mediumRows(WidgetFixtures.nextTrain())
        XCTAssertEqual(
            content.link.absoluteString,
            "traintimes://route?destinationId=UN&mode=route&originId=OA&source=widget&widget=departures"
        )
        XCTAssertEqual(
            rows?.first.link.absoluteString,
            "traintimes://trip?destinationId=UN&mode=route&originId=OA&serviceDate=20261111&source=widget&tripId=LW-0758&widget=departures"
        )
        guard case .next(let later)? = rows?.second else { return XCTFail("Expected the Next line") }
        XCTAssertEqual(later.map(\.link), [
            WidgetLink.tagged(WidgetFixtures.train(8, 6).link, from: .departures),
            WidgetLink.tagged(WidgetFixtures.train(8, 28).link, from: .departures),
        ])
    }

    // MARK: - Messages

    func testAfterTheLastTrainNamesTheFirstTrainAndDeparturesItsArrival() {
        let small = NextTrainContent(WidgetFixtures.afterLastTrain)
        XCTAssertEqual(small.header?.to, "Union")
        XCTAssertEqual(message(small.body)?.title, "No more trains tonight")
        XCTAssertEqual(pieces(message(small.body)?.detail), [
            WidgetText.Piece(text: "First train ", isStrong: false), WidgetText.Piece(text: "5:43 AM", isStrong: true),
        ])
        XCTAssertEqual(small.link.absoluteString, "traintimes://route?destinationId=UN&mode=route&originId=OA&source=widget&widget=next_train")
        let medium = DeparturesContent(WidgetFixtures.afterLastTrain)
        XCTAssertEqual(plain(message(medium.body)?.detail), "First train tomorrow 5:43 AM, arrives 6:21 AM")
        XCTAssertEqual(pieces(message(medium.body)?.detail).filter(\.isStrong).map(\.text), ["5:43 AM"])
        // A line that wraps breaks before "arrives", never inside a time.
        XCTAssertEqual(message(medium.body)?.detail?.plain, "First train tomorrow 5:43\u{00A0}AM, arrives\u{00A0}6:21\u{00A0}AM")
    }

    func testTheLastTrainBefore6PMSaysTodayAndALaterDayItsWeekday() {
        let friday = WidgetFixtures.train(6, 10, on: WidgetFixtures.day.adding(days: 2))
        let entry = WidgetFixtures.entry(
            WidgetFixtures.at(17, 0),
            .noMoreTrainsTonight(header: WidgetFixtures.header(), since: WidgetFixtures.at(16, 40), next: friday)
        )
        XCTAssertEqual(message(NextTrainContent(entry).body)?.title, "No more trains today")
        XCTAssertEqual(plain(message(NextTrainContent(entry).body)?.detail), "First train Fri 6:10 AM")
        XCTAssertEqual(plain(message(DeparturesContent(entry).body)?.detail), "First train Fri 6:10 AM, arrives 6:50 AM")
        // From 6 PM it is tonight, after midnight too.
        let late = WidgetFixtures.entry(
            WidgetFixtures.at(0, 50), .noMoreTrainsTonight(header: WidgetFixtures.header(), since: WidgetFixtures.at(0, 40), next: nil)
        )
        XCTAssertEqual(message(NextTrainContent(late).body)?.title, "No more trains tonight")
        XCTAssertNil(message(NextTrainContent(late).body)?.detail)
    }

    func testNoTrainsTodayNamesTheNextDay() {
        let content = NextTrainContent(WidgetFixtures.noTrainsToday)
        XCTAssertEqual(content.header?.to, "Oakville")
        XCTAssertEqual(message(content.body)?.title, "No trains today")
        XCTAssertEqual(pieces(message(content.body)?.detail), [
            WidgetText.Piece(text: "Next ", isStrong: false), WidgetText.Piece(text: "Mon 6:10 AM", isStrong: true),
        ])
    }

    func testNotLoadedNoRouteAndOutOfDate() {
        let notLoaded = NextTrainContent(WidgetFixtures.notLoaded)
        XCTAssertNil(notLoaded.header)
        XCTAssertEqual(message(notLoaded.body)?.title, "Open Train Times once")
        XCTAssertEqual(message(notLoaded.body)?.detail?.plain, "to load the timetable.")
        XCTAssertEqual(notLoaded.link.absoluteString, "traintimes://route?mode=route&source=widget&widget=next_train")

        let noRoute = DeparturesContent(WidgetFixtures.noRoute)
        XCTAssertNil(noRoute.header)
        XCTAssertEqual(message(noRoute.body)?.title, "Choose your route")
        XCTAssertEqual(message(noRoute.body)?.detail?.plain, "in Train Times.")
        XCTAssertEqual(noRoute.link.absoluteString, "traintimes://route?mode=route&source=widget&widget=departures")

        let outOfDate = NextTrainContent(WidgetFixtures.outOfDate)
        XCTAssertEqual(outOfDate.header?.to, "Union")
        XCTAssertEqual(message(outOfDate.body)?.title, "Timetable out of date")
        XCTAssertEqual(message(outOfDate.body)?.detail?.plain, "Open Train Times to update it.")
    }

    // MARK: - Names, the countdown and the sample

    func testShortNamesDropGOAndStation() {
        XCTAssertEqual(StationNames.short("Oakville GO"), "Oakville")
        XCTAssertEqual(StationNames.short("Union Station GO"), "Union")
        XCTAssertEqual(StationNames.short("Union Station"), "Union")
        XCTAssertEqual(StationNames.short("West Harbour GO"), "West Harbour")
        XCTAssertEqual(StationNames.short("Hamilton GO Centre"), "Hamilton GO Centre")
        XCTAssertEqual(StationNames.short("GO"), "GO")
    }

    /// Rounded up (TT-185): a timeline that starts between two minutes reads what the one on the minute before reads,
    /// and steps with it on the next minute.
    func testTheCountdownIsWholeMinutesRoundedUp() {
        let departure = WidgetFixtures.at(7, 58)
        XCTAssertEqual(WidgetCountdown.minutes(from: WidgetFixtures.at(7, 47), to: departure), "11 min")
        XCTAssertEqual(WidgetCountdown.minutes(from: WidgetFixtures.at(7, 47, second: 30), to: departure), "11 min")
        XCTAssertEqual(WidgetCountdown.minutes(from: WidgetFixtures.at(7, 48), to: departure), "10 min")
        XCTAssertEqual(WidgetCountdown.minutes(from: WidgetFixtures.at(4, 51), to: departure), "3 h 7 min")
        XCTAssertEqual(WidgetCountdown.minutes(from: WidgetFixtures.at(7, 57), to: departure), "1 min")
        XCTAssertEqual(WidgetCountdown.minutes(from: WidgetFixtures.at(7, 59), to: WidgetFixtures.at(7, 58)), "0 min")
    }

    func testTheGallerySampleIsThe758FromOakvilleToUnion() {
        let train = smallTrain(.sample)
        XCTAssertEqual(train?.departure, WidgetFixtures.at(7, 58))
        XCTAssertEqual(WidgetCountdown.minutes(from: WidgetEntry.sample.date, to: WidgetFixtures.at(7, 58)), "11 min")
        XCTAssertEqual(train?.footer?.mark, .express)
        let header = DeparturesContent(.sample).header
        XCTAssertEqual([header?.from, header?.to], ["Oakville", "Union"])
        XCTAssertEqual(train?.countdown, "11 min")
        // Departures: the 7:58 in 11 min, then "Next" with the two after it, each with its own link.
        XCTAssertEqual(mediumRows(.sample)?.first.when, .countdown("11 min"))
        guard case .next(let later)? = mediumRows(.sample)?.second else { return XCTFail("Expected the Next line") }
        XCTAssertEqual(Set(later.map(\.id)).count, 2)
    }

    // MARK: - Links

    func testAWidgetsLinkNamesItsWidgetAndStillOpensTheSameThing() throws {
        let trip = WidgetFixtures.train(7, 58).link
        let tagged = WidgetLink.tagged(trip, from: .nextTrain)
        XCTAssertEqual(WidgetLink.widget(of: tagged), .nextTrain)
        XCTAssertEqual(WidgetLink.widget(of: WidgetLink.tagged(WidgetLink.route(nil), from: .departures)), .departures)
        // Tagging twice keeps one of each; the Show is A route unless said (TT-257).
        XCTAssertEqual(WidgetLink.tagged(tagged, from: .nextTrain), tagged)
        XCTAssertEqual(WidgetLink.mode(of: tagged), .route)
        let mine = WidgetLink.tagged(tagged, from: .nextTrain, mode: .myTrains)
        XCTAssertEqual(WidgetLink.mode(of: mine), .myTrains)
        XCTAssertEqual(WidgetLink.widget(of: mine), .nextTrain)
        XCTAssertEqual(WidgetLink.tagged(mine, from: .nextTrain, mode: .myTrains), mine)
        XCTAssertNil(WidgetLink.mode(of: trip))
        // The app reads the same trip from it.
        XCTAssertEqual(
            NotificationLink(url: tagged, today: WidgetFixtures.day), NotificationLink(url: trip, today: WidgetFixtures.day)
        )
        // Any other link is not a widget's.
        XCTAssertNil(WidgetLink.widget(of: trip))
        XCTAssertNil(WidgetLink.widget(of: try XCTUnwrap(URL(string: "traintimes://route?source=widget&widget=clock"))))
        XCTAssertNil(WidgetLink.widget(of: try XCTUnwrap(URL(string: "traintimes://route?source=push&widget=departures"))))
        XCTAssertNil(WidgetLink.widget(of: try XCTUnwrap(URL(string: "https://traintimes.ca/?source=widget&widget=departures"))))
    }

    func testWidgetKinds() {
        XCTAssertEqual(WidgetKind(kind: "NextTrain"), .nextTrain)
        XCTAssertEqual(WidgetKind(kind: "Departures"), .departures)
        XCTAssertNil(WidgetKind(kind: "RideActivity"))
        XCTAssertEqual(WidgetKind.nextTrain.rawValue, "next_train")
    }

    // MARK: - Edit widget's stations

    func testYourStationsComeFirst() {
        let stations = WidgetStations(file: WidgetFixtures.stationsFile)
        XCTAssertEqual(stations.suggested.map(\.id), ["UN", "OA", "AL", "CL", "PO"])
        XCTAssertEqual(WidgetStations(file: nil).suggested, [])
    }

    func testSearchMatchesAWordPrefixLikeTheStationPicker() {
        let stations = WidgetStations(file: WidgetFixtures.stationsFile)
        XCTAssertEqual(stations.matching("uni").map(\.name), ["Union Station GO"])
        XCTAssertEqual(stations.matching("st").map(\.id), ["UN"])
        XCTAssertEqual(stations.matching("cred").map(\.id), ["PO"])
        XCTAssertEqual(stations.matching("ville").map(\.id), [])
        XCTAssertEqual(stations.matching("  ").map(\.id), ["UN", "OA", "AL", "CL", "PO"])
    }

    func testStoredIdsResolve() {
        let stations = WidgetStations(file: WidgetFixtures.stationsFile)
        XCTAssertEqual(stations.stops(for: ["OA", "XX", "UN"]).map(\.name), ["Oakville GO", "Union Station GO"])
        XCTAssertEqual(StationEntity(stations.stops(for: ["OA"])[0]).id, "OA")
    }

    /// A route with no From or To follows the open route in its morning way, turned around after 12 PM; Edit widget no
    /// longer fills From and To in (TT-257, D131: My trains is every new widget's Show).
    func testARouteWithNoStationsFollowsTheOpenRouteAndTurnsAroundAt12PM() {
        var file = WidgetFixtures.stationsFile
        file.routes = [
            WidgetFile.Timetable(
                from: WidgetFile.Stop(id: "OA", name: "Oakville GO"), to: WidgetFile.Stop(id: "UN", name: "Union Station GO"),
                line: WidgetFixtures.line, outbound: [departure(8, 0), departure(13, 30)], inbound: [departure(9, 0), departure(17, 0)]
            ),
        ]
        let morning = WidgetEntryBuilder.entry(file: file, route: nil, turnsAround: true, at: WidgetFixtures.at(7, 0))
        let afternoon = WidgetEntryBuilder.entry(file: file, route: nil, turnsAround: true, at: WidgetFixtures.at(12, 30))
        XCTAssertEqual(NextTrainContent(morning).header?.to, "Union")
        XCTAssertEqual(NextTrainContent(afternoon).header?.to, "Oakville")
    }

    private func departure(_ hour: Int, _ minute: Int) -> WidgetFile.Departure {
        let start = WidgetFixtures.at(hour, minute)
        return WidgetFile.Departure(
            tripId: "T-\(hour)\(minute)", serviceDay: WidgetFixtures.day, departure: start, arrival: start.addingTimeInterval(2400),
            isExpress: false, isAlerted: false
        )
    }

    // MARK: - The placed widgets

    func testPlacedWidgetsGiveTheFileTheirRoutes() async {
        let stations = FakeStations()
        let placed = FakePlacedWidgets(list: [
            PlacedWidget(kind: .nextTrain, route: WidgetFile.RouteKey(fromId: "CL", toId: "UN")),
            // No From and To of its own: it follows the open route, which the file has anyway.
            PlacedWidget(kind: .departures, route: nil),
            // A station the feed no longer lists.
            PlacedWidget(kind: .departures, route: WidgetFile.RouteKey(fromId: "XX", toId: "UN")),
        ])
        let routes = try? await PlacedWidgetRoutes(widgets: placed, stations: stations).routes()
        XCTAssertEqual(routes?.map { [$0.from.id, $0.to.id] }, [["CL", "UN"]])
        let none = try? await PlacedWidgetRoutes(widgets: FakePlacedWidgets(list: []), stations: stations).routes()
        XCTAssertEqual(none, [])
    }

    /// Widgets that cannot be read are not "no widgets": the routes throw, so the writer keeps the last file.
    func testUnreadableWidgetsAreNotNoWidgets() async {
        let unreadable = PlacedWidgetRoutes(widgets: FakePlacedWidgets(list: nil), stations: FakeStations())
        do {
            _ = try await unreadable.routes()
            XCTFail("Expected the routes to throw")
        } catch {
            XCTAssertTrue(error is PlacedWidgetRoutes.Unreadable)
        }
    }

    @MainActor
    func testWidgetsPlacedIsSentOnlyWhenTheCountsChange() {
        let recorder = RecordingAnalytics.install()
        defer { Analytics.tracker = nil }
        let count = WidgetsPlacedCount(defaults: .ephemeral())
        let small = PlacedWidget(kind: .nextTrain, route: nil)
        let medium = PlacedWidget(kind: .departures, route: nil)

        // Never placed one: nothing to say.
        count.report([])
        XCTAssertEqual(recorder.events, [])
        count.report([small, small, medium])
        XCTAssertEqual(recorder.events, [.widgetsPlaced(nextTrain: 2, departures: 1, lock: 0, myTrains: 3, route: 0)])
        // The same widgets on the next foreground send nothing.
        count.report([medium, small, small])
        XCTAssertEqual(recorder.events.count, 1)
        // A widget turned to A route is a change (TT-257).
        let routeSmall = PlacedWidget(kind: .nextTrain, route: WidgetFile.RouteKey(fromId: "CL", toId: "UN"), mode: .route)
        count.report([small, routeSmall, medium])
        XCTAssertEqual(recorder.events.last, .widgetsPlaced(nextTrain: 2, departures: 1, lock: 0, myTrains: 2, route: 1))
        // All removed is a change.
        count.report([])
        XCTAssertEqual(recorder.events.last, .widgetsPlaced(nextTrain: 0, departures: 0, lock: 0, myTrains: 0, route: 0))
        XCTAssertEqual(recorder.events.last?.properties, [
            "next_train": .int(0), "departures": .int(0), "lock": .int(0), "my_trains": .int(0), "route": .int(0),
        ])
    }

    /// A count stored by an older build (two numbers before TT-184, three before TT-257) reads with zeros for the rest, so
    /// an install that never placed a widget still sends nothing.
    @MainActor
    func testWidgetsPlacedReadsAnOlderBuildsCounts() {
        let recorder = RecordingAnalytics.install()
        defer { Analytics.tracker = nil }
        let defaults = UserDefaults.ephemeral()
        defaults.set("0,0", forKey: WidgetsPlacedCount.key)
        WidgetsPlacedCount(defaults: defaults).report([])
        defaults.set("0,0,0", forKey: WidgetsPlacedCount.key)
        WidgetsPlacedCount(defaults: defaults).report([])
        XCTAssertEqual(recorder.events, [])
        defaults.set("1,0,0", forKey: WidgetsPlacedCount.key)
        WidgetsPlacedCount(defaults: defaults).report([PlacedWidget(kind: .nextTrain, route: nil)])
        XCTAssertEqual(recorder.events, [.widgetsPlaced(nextTrain: 1, departures: 0, lock: 0, myTrains: 1, route: 0)])
    }

    @MainActor
    func testWidgetsPlacedIsNotStoredWithoutATracker() {
        let defaults = UserDefaults.ephemeral()
        Analytics.tracker = nil
        WidgetsPlacedCount(defaults: defaults).report([PlacedWidget(kind: .nextTrain, route: nil)])
        XCTAssertNil(defaults.string(forKey: WidgetsPlacedCount.key))
    }

    func testWidgetOpenedNamesTheWidgetTheTargetAndTheShow() {
        XCTAssertEqual(
            AnalyticsEvent.widgetOpened(.nextTrain, target: .trip, mode: .myTrains).properties,
            ["widget": .string("next_train"), "target": .string("trip"), "mode": .string("my_trains")]
        )
        XCTAssertEqual(
            AnalyticsEvent.widgetOpened(.departures, target: .route, mode: .route).properties,
            ["widget": .string("departures"), "target": .string("route"), "mode": .string("route")]
        )
        XCTAssertEqual(AnalyticsEvent.widgetOpened(.departures, target: .alerts, mode: .myTrains).properties["target"], .string("alerts"))
        XCTAssertEqual(AnalyticsEvent.widgetOpened(.departures, target: .route, mode: .route).name, "widget_opened")
    }

    /// My trains' Departures opens the Alerts tab outside its trains.
    func testTheAlertsLinkOpensTheAlertsTab() throws {
        let link = WidgetLink.tagged(WidgetLink.alerts(), from: .departures, mode: .myTrains)
        let opened = try XCTUnwrap(NotificationLink(url: link, today: WidgetFixtures.day))
        XCTAssertEqual(opened, .alerts)
        XCTAssertEqual(opened.target(today: WidgetFixtures.day), .alerts)
        XCTAssertFalse(opened.hasStations)
    }
}

private struct FakePlacedWidgets: PlacedWidgetsProviding {
    let list: [PlacedWidget]?
    func widgets() async -> [PlacedWidget]? { list }
}

private struct FakeStations: StationRepository {
    func stations() async throws -> [Station] {
        [Station(id: "CL", name: "Clarkson GO"), Station(id: "OA", name: "Oakville GO"), Station(id: "UN", name: "Union Station GO")]
    }

    func route(from: Station, to: Station) async throws -> Route {
        Route(from: from, to: to, line: Line(id: "LW", name: "Lakeshore West", colorHex: nil))
    }
}
