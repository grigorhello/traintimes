import XCTest
@testable import TrainTimes

/// TT-206: the first launch's flow (welcome, your line, your station, the route), the tile shortcut, going back, the
/// before-noon direction and Search stations; the splash's exit rule; the bundled lines against GO's feed.
@MainActor
final class WelcomeViewModelTests: XCTestCase {
    /// Thu Nov 5, 2026 in Toronto (EST, UTC-5).
    private func toronto(_ hour: Int, _ minute: Int = 0) -> Date {
        ServiceDay(year: 2026, month: 11, day: 5).date(hour: hour, minute: minute)
    }

    private func model(at date: Date) throws -> WelcomeViewModel {
        WelcomeViewModel(
            stations: try FixtureScheduleRepository(bundle: Bundle(for: Self.self)), clock: FixedClock(now: date),
            recents: RecentRoutes(defaults: .ephemeral())
        )
    }

    private func oakville() throws -> Station {
        try XCTUnwrap(GONetwork.line("LW")?.stations.first { $0.id == "OA" })
    }

    /// "Choose your line", Lakeshore West, Oakville GO: three taps; before noon the route runs to Union.
    func testThreeTapsMakeTheMorningRoute() throws {
        let model = try model(at: toronto(7, 21))
        XCTAssertEqual(model.step, .welcome)
        XCTAssertNil(model.stepNumber)

        model.chooseYourLine()
        XCTAssertEqual(model.step, .lines)
        XCTAssertEqual(model.stepNumber, 1)
        XCTAssertEqual(model.lines.map(\.id), ["LW", "MI", "KI", "BR", "RH", "ST", "LE"])

        model.pick(lineId: "LW")
        XCTAssertEqual(model.step, .station(lineId: "LW", fromMap: false))
        XCTAssertEqual(model.stepNumber, 2)
        XCTAssertEqual(model.chosenLine?.line.name, "Lakeshore West")
        XCTAssertFalse(model.chosenLine?.stations.contains { $0.id == "UN" } ?? true, "Union is not listed")

        let route = try XCTUnwrap(model.route(to: oakville()))
        XCTAssertEqual(route.from.id, "OA")
        XCTAssertEqual(route.to.id, "UN")
        XCTAssertEqual(route.line?.id, "LW")
        XCTAssertFalse(model.unionIsFirst)
    }

    /// From noon on, the route runs from Union to your station.
    func testFromNoonTheRouteRunsFromUnion() throws {
        let clock = TestClock(now: toronto(11, 59))
        let model = WelcomeViewModel(
            stations: try FixtureScheduleRepository(bundle: Bundle(for: Self.self)), clock: clock,
            recents: RecentRoutes(defaults: .ephemeral())
        )
        model.pick(lineId: "LW", fromMap: true)
        XCTAssertEqual(try XCTUnwrap(model.route(to: oakville())).from.id, "OA")

        clock.advance(minutes: 1)
        XCTAssertTrue(model.unionIsFirst)
        let route = try XCTUnwrap(model.route(to: oakville()))
        XCTAssertEqual(route.from.id, "UN")
        XCTAssertEqual(route.to.id, "OA")
    }

    /// A tile on the welcome's picture picks its line and skips the list: two taps in all.
    func testATileOnThePictureSkipsTheList() throws {
        let model = try model(at: toronto(8))
        model.pick(lineId: "RH", fromMap: true)
        XCTAssertEqual(model.step, .station(lineId: "RH", fromMap: true))
        XCTAssertEqual(model.chosenLine?.stations.first?.name, "Oriole GO")
        XCTAssertNotNil(model.route(to: try XCTUnwrap(model.chosenLine?.stations.last)))
    }

    func testTheXGoesBackToTheLinesAndTheNameToTheWelcome() throws {
        let model = try model(at: toronto(8))
        model.pick(lineId: "KI")
        model.backToLines()
        XCTAssertEqual(model.step, .lines)
        XCTAssertNil(model.chosenLine)
        XCTAssertNil(model.route(to: try oakville()), "No route without a line")
        model.backToWelcome()
        XCTAssertEqual(model.step, .welcome)
    }

    func testAnUnknownLineIsIgnored() throws {
        let model = try model(at: toronto(8))
        model.chooseYourLine()
        model.pick(lineId: "UP")
        XCTAssertEqual(model.step, .lines)
    }

    /// "Search stations" opens the route form as first use had it: nothing chosen, the picker closed.
    func testSearchStationsOpensTheRouteForm() throws {
        let model = try model(at: toronto(8))
        model.chooseYourLine()
        model.searchStations()
        XCTAssertEqual(model.step, .search)
        let form = try XCTUnwrap(model.routeForm)
        XCTAssertNil(form.from)
        XCTAssertNil(form.to)
        XCTAssertFalse(form.isPickingStation)
        XCTAssertFalse(form.appliesAtOnce, "A pick waits for Show trains, as before")
    }

    /// A station row of step 2's card: the route form keeps Union where the card had it and searches the tapped row.
    func testAStationRowSearchesWithUnionKept() throws {
        let morning = try model(at: toronto(8))
        morning.pick(lineId: "LW")
        morning.search(.from)
        let form = try XCTUnwrap(morning.routeForm)
        XCTAssertEqual(morning.step, .search)
        XCTAssertNil(form.from)
        XCTAssertEqual(form.to?.id, "UN")
        XCTAssertTrue(form.isPickingStation)
        XCTAssertEqual(form.pickingField, .from)

        let evening = try model(at: toronto(18))
        evening.pick(lineId: "LW")
        evening.search(.to)
        XCTAssertEqual(evening.routeForm?.from?.id, "UN")
        XCTAssertNil(evening.routeForm?.to)
        XCTAssertEqual(evening.routeForm?.pickingField, .to)
    }

    /// The splash folds into Schedule with a saved route and becomes the welcome with none.
    func testSplashExit() {
        let route = Route(from: GONetwork.union, to: Station(id: "OA", name: "Oakville GO"), line: nil)
        XCTAssertEqual(LaunchMotion.exit(savedRoute: route), .schedule)
        XCTAssertEqual(LaunchMotion.exit(savedRoute: nil), .welcome)
        XCTAssertFalse(LaunchMotion.plays, "Never in the unit test host")
    }

    /// The bundled lines run from Union outward in the order GO's trains call: Lakeshore West and Kitchener against the
    /// sample feed, with the same ids and names, and every rail station of the feed is on one of the seven lines.
    func testBundledLinesMatchTheFeed() throws {
        let timetable = GTFSTimetable(feed: try GTFSFeed(zip: GTFSTimetableTests.sampleZip(), importedAt: Date()))
        for (id, name) in [("LW", "Lakeshore West"), ("KI", "Kitchener")] {
            let fromFeed = timetable.stations
                .filter { $0.lines.contains(name) && $0.id != "UN" }
                .sorted { ($0.distanceFromUnion[name] ?? 0) < ($1.distanceFromUnion[name] ?? 0) }
            let bundled = try XCTUnwrap(GONetwork.line(id)).stations
            XCTAssertEqual(bundled.map(\.id), fromFeed.map(\.id), id)
            XCTAssertEqual(bundled.map(\.name), fromFeed.map(\.name), id)
        }
        let bundledIds = Set(GONetwork.lines.flatMap { $0.stations.map(\.id) } + ["UN"])
        let feedIds = Set(timetable.stations.map(\.id))
        XCTAssertTrue(feedIds.isSubset(of: bundledIds), "Missing: \(feedIds.subtracting(bundledIds))")
        XCTAssertEqual(GONetwork.lines.map(\.stations.count), [15, 8, 13, 10, 6, 9, 9])
    }
}
