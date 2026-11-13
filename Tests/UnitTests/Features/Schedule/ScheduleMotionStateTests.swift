import XCTest
@testable import TrainTimes

/// When Schedule asks for its motion (TT-164, D61): the cascade for a new set of trains only, the Now pulse on the Schedule
/// tab and once after the launch's scroll settles, and the cascade's order counted from the first card in view.
@MainActor
final class ScheduleMotionStateTests: XCTestCase {
    private let thursday = ServiceDay(year: 2026, month: 11, day: 5)
    private let measured = TimelineCardSize(height: 118, anchor: 33)

    /// A day tapped, the route swapped or picked, the first load and back to Today from another day all cascade.
    func testANewSetOfTrainsCascades() async throws {
        let model = try await ScheduleViewModel.loadedFixture()
        XCTAssertEqual(model.entranceRequest, 1, "The first load")
        await model.select(model.days[1])
        XCTAssertEqual(model.entranceRequest, 2, "A day tapped")
        await model.swap()
        XCTAssertEqual(model.entranceRequest, 3, "The route swapped")
        await model.backToNow()
        XCTAssertEqual(model.entranceRequest, 4, "Back to Today from another day")
        await model.show(try XCTUnwrap(model.route))
        XCTAssertEqual(model.entranceRequest, 5, "A route picked")
    }

    /// The same trains never cascade again: a refresh, a minute tick, the tab on Today, the midnight turn.
    func testTheSameTrainsNeverCascade() async throws {
        let repository = try FixtureScheduleRepository(bundle: Bundle(for: ScheduleMotionStateTests.self))
        let clock = TestClock(now: thursday.date(hour: 23, minute: 58))
        let model = ScheduleViewModel(route: repository.route, repository: repository, clock: clock)
        await model.loadIfNeeded()
        XCTAssertEqual(model.entranceRequest, 1)
        await model.refresh()
        clock.advance(minutes: 1)
        model.tick()
        await model.backToNow()
        XCTAssertEqual(model.entranceRequest, 1)
        clock.advance(minutes: 2)
        await model.rollOverIfNeeded()
        XCTAssertEqual(model.selectedDay, thursday.adding(days: 1), "The day turned")
        XCTAssertEqual(model.entranceRequest, 1, "The midnight turn does not cascade")
        XCTAssertEqual(model.daySelection, 0, "Nor does the accent tile glide at midnight")
    }

    /// The accent tile glides only to a day the rider picks, or back to Today from the Schedule tab.
    func testOnlyAPickedDayGlides() async throws {
        let model = try await ScheduleViewModel.loadedFixture()
        XCTAssertEqual(model.daySelection, 0)
        await model.select(model.days[1])
        XCTAssertEqual(model.daySelection, 1, "A day tapped")
        await model.select(model.days[1])
        XCTAssertEqual(model.daySelection, 1, "The selected day tapped again")
        await model.backToNow()
        XCTAssertEqual(model.daySelection, 2, "Back to Today from another day")
        await model.backToNow()
        XCTAssertEqual(model.daySelection, 2, "The tab on Today")
    }

    /// New trains jump the timeline to where they open (the cards cascade in there); the tab on Today and the midnight turn
    /// still glide.
    func testNewTrainsJumpTheTimeline() async throws {
        let model = try await ScheduleViewModel.loadedFixture()
        await model.select(model.days[1])
        XCTAssertTrue(model.scrollJumps, "A day tapped")
        await model.backToNow()
        XCTAssertTrue(model.scrollJumps, "Back to Today from another day")
        await model.backToNow()
        XCTAssertFalse(model.scrollJumps, "The tab on Today")
        await model.swap()
        XCTAssertTrue(model.scrollJumps, "The route swapped")
        XCTAssertFalse(model.awaitsNewTrains)
    }

    /// From the tap until the new trains land, the old cards are hidden; a load that fails ends the wait too.
    func testTheOldCardsHideWhileNewTrainsLoad() async throws {
        let repository = GatedRepository()
        let route = Route(
            from: Station(id: "OA", name: "Oakville GO"), to: Station(id: "UN", name: "Union Station GO"),
            line: Line(id: "LW", name: "Lakeshore West", colorHex: "#98002e")
        )
        let model = ScheduleViewModel(route: route, repository: repository, clock: FixedClock(now: thursday.date(hour: 7, minute: 21)))
        await model.loadIfNeeded()
        XCTAssertFalse(model.awaitsNewTrains)
        await repository.close()
        let selecting = Task { await model.select(model.days[1]) }
        await repository.held()
        XCTAssertTrue(model.awaitsNewTrains, "Hidden from the tap")
        await repository.open()
        await selecting.value
        XCTAssertFalse(model.awaitsNewTrains, "Shown once the trains land")
    }

    /// New trains that keep the timeline empty for long (today's wait for live status on a slow network) show the loading
    /// timeline until they land; a quick load never shows it.
    func testSlowNewTrainsShowTheLoadingTimeline() async throws {
        let repository = GatedRepository()
        let route = Route(
            from: Station(id: "OA", name: "Oakville GO"), to: Station(id: "UN", name: "Union Station GO"),
            line: Line(id: "LW", name: "Lakeshore West", colorHex: "#98002e")
        )
        let model = ScheduleViewModel(route: route, repository: repository, clock: FixedClock(now: thursday.date(hour: 7, minute: 21)))
        await model.loadIfNeeded()
        let flag = ChangeFlag()
        withObservationTracking { _ = model.newTrainsAreSlow } onChange: { MainActor.assumeIsolated { flag.changed = true } }
        await model.select(model.days[1])
        XCTAssertFalse(flag.changed, "A quick load never shows it")
        await repository.close()
        let selecting = Task { await model.select(model.days[2]) }
        await repository.held()
        XCTAssertNotEqual(model.content, .loading, "Hidden by the cascade's wait at first, not loading")
        try await Task.sleep(for: ScheduleViewModel.slowNewTrains + .milliseconds(200))
        XCTAssertEqual(model.content, .loading, "Loading once the wait is long")
        await repository.open()
        await selecting.value
        XCTAssertFalse(model.newTrainsAreSlow)
        XCTAssertNotEqual(model.content, .loading, "The trains landed")
    }

    /// A load overtaken by a newer one (today's, waiting for live status) neither keeps the newer trains hidden nor shows the
    /// loading timeline over them, and its trains never replace them.
    func testAnOvertakenLoadLeavesTheNewTrainsAlone() async throws {
        let repository = GatedRepository()
        let route = Route(
            from: Station(id: "OA", name: "Oakville GO"), to: Station(id: "UN", name: "Union Station GO"),
            line: Line(id: "LW", name: "Lakeshore West", colorHex: "#98002e")
        )
        let model = ScheduleViewModel(route: route, repository: repository, clock: FixedClock(now: thursday.date(hour: 7, minute: 21)))
        await model.loadIfNeeded()
        await repository.close(day: model.days[1])
        let overtaken = Task { await model.select(model.days[1]) }
        await repository.held()
        await model.select(model.days[2])
        XCTAssertFalse(model.awaitsNewTrains, "The latest trains have landed")
        try await Task.sleep(for: ScheduleViewModel.slowNewTrains + .milliseconds(200))
        XCTAssertFalse(model.newTrainsAreSlow, "The overtaken load's wait does not count")
        XCTAssertNotEqual(model.content, .loading)
        let request = model.entranceRequest
        await repository.open()
        await overtaken.value
        XCTAssertFalse(model.awaitsNewTrains)
        XCTAssertEqual(model.selectedDay, model.days[2])
        XCTAssertEqual(model.entranceRequest, request, "Its trains never land")
    }

    /// A card measured at the size the layout already gave it leaves the layout as it is, so the cards are not all redrawn;
    /// another size moves it.
    func testACardMeasuredAtTheStandardSizeLeavesTheLayoutAlone() async throws {
        let model = try await ScheduleViewModel.loadedFixture()
        let card = try XCTUnwrap(model.departures.first)
        let flag = ChangeFlag()
        withObservationTracking { _ = model.layout } onChange: { MainActor.assumeIsolated { flag.changed = true } }
        model.setCardSize(.standard, for: card.id)
        XCTAssertFalse(flag.changed, "The same layout")
        model.setCardSize(TimelineCardSize(height: 160, anchor: 33), for: card.id)
        XCTAssertTrue(flag.changed, "A taller card moves the others")
    }

    /// A past day's cards only fade in.
    func testPastDaysOnlyFade() async throws {
        let model = try await ScheduleViewModel.loadedFixture()
        XCTAssertFalse(model.isPastDay)
        await model.select(model.days[1])
        XCTAssertFalse(model.isPastDay)
        await model.select(try XCTUnwrap(model.pastDays.last))
        XCTAssertTrue(model.isPastDay)
    }

    /// Trains that replace "Loading timetable" after a failed first load cascade, even from a refresh; the next refresh does not.
    func testTrainsReplacingTheLoadingSkeletonCascade() async {
        let repository = OfflineFirstRepository()
        let route = Route(
            from: Station(id: "OA", name: "Oakville GO"), to: Station(id: "UN", name: "Union Station GO"),
            line: Line(id: "LW", name: "Lakeshore West", colorHex: "#98002e")
        )
        let model = ScheduleViewModel(route: route, repository: repository, clock: FixedClock(now: thursday.date(hour: 7, minute: 21)))
        await model.loadIfNeeded()
        XCTAssertEqual(model.content, .loading)
        XCTAssertEqual(model.entranceRequest, 0, "Nothing to cascade while the skeleton shows")
        await repository.connect()
        await model.refresh()
        XCTAssertEqual(model.entranceRequest, 1)
        await model.refresh()
        XCTAssertEqual(model.entranceRequest, 1)
    }

    /// Tapping the Schedule tab again pulses the Now dot each time.
    func testTheScheduleTabPulsesNow() async throws {
        let model = try await ScheduleViewModel.loadedFixture()
        await model.backToNow()
        XCTAssertEqual(model.nowPulse, 1)
        await model.select(model.days[1])
        await model.backToNow()
        XCTAssertEqual(model.nowPulse, 2)
    }

    /// The Today tile does what the Schedule tab does: from another day back to Today, and on Today (where a tap used to do
    /// nothing) a scroll to Now, each with the pulse (TT-197, D80).
    func testTheTodayTileGoesBackToNow() async throws {
        let model = try await ScheduleViewModel.loadedFixture()
        XCTAssertEqual(model.days[0], model.today)
        await model.select(model.days[1])
        let scrolls = model.scrollRequest
        await model.select(model.today)
        XCTAssertTrue(model.isToday)
        XCTAssertEqual(model.scrollRequest, scrolls + 1)
        XCTAssertEqual(model.nowPulse, 1)
        await model.select(model.today)
        XCTAssertEqual(model.scrollRequest, scrolls + 2, "Today tapped on Today scrolls to Now")
        XCTAssertEqual(model.nowPulse, 2)
        XCTAssertFalse(model.scrollJumps, "On Today the scroll glides, as the tab's does")
    }

    /// Coming back to the timeline plays Now where it is, on Today only, and never before the launch's own play.
    func testTheTimelineAppearingPlaysNow() async throws {
        let model = try await ScheduleViewModel.loadedFixture()
        model.timelineAppeared()
        XCTAssertEqual(model.nowPulse, 0, "The launch plays once its scroll settles")
        for id in model.departures.map(\.id) { model.setCardSize(measured, for: id) }
        XCTAssertEqual(model.nowPulse, 1)
        let scrolls = model.scrollRequest
        model.timelineAppeared()
        XCTAssertEqual(model.nowPulse, 2)
        XCTAssertEqual(model.scrollRequest, scrolls, "It does not scroll")
        await model.select(model.days[1])
        model.timelineAppeared()
        XCTAssertEqual(model.nowPulse, 2, "No Now line on another day")
    }

    /// The launch pulses Now once, when its scroll has settled on the measured cards; a later settle does not.
    func testTheLaunchPulsesNowOnceItsScrollHasSettled() async throws {
        let model = try await ScheduleViewModel.loadedFixture()
        XCTAssertEqual(model.nowPulse, 0, "Not before every card is measured")
        for id in model.departures.map(\.id) { model.setCardSize(measured, for: id) }
        XCTAssertEqual(model.settleRequest, 1)
        XCTAssertEqual(model.nowPulse, 1)
        await model.select(model.days[1])
        for id in model.departures.map(\.id) { model.setCardSize(measured, for: id) }
        XCTAssertEqual(model.settleRequest, 2)
        XCTAssertEqual(model.nowPulse, 1, "Only the launch's settle pulses")
    }

    /// The stagger starts with the first card in view where the timeline opens; the cards above it count as the first.
    func testTheCascadeCountsFromTheFirstCardInView() async throws {
        let model = try await ScheduleViewModel.loadedFixture()
        let cards = model.layout.cards
        XCTAssertEqual(cards.count, 4)
        let fromTop = model.layout.cascadeOrder(scrolledTo: 0)
        XCTAssertEqual(cards.map { fromTop[$0.id] }, [0, 1, 2, 3])
        let pastFirst = model.layout.cascadeOrder(scrolledTo: cards[0].bottom + 1)
        XCTAssertEqual(cards.map { pastFirst[$0.id] }, [0, 0, 1, 2])
    }
}

/// Set when an observed property changes; the observation's callback runs on the main actor, during the change.
@MainActor private final class ChangeFlag {
    var changed = false
}

/// No timetable until `connect()`, like a first launch without a connection (TT-130).
private actor OfflineFirstRepository: ScheduleRepository {
    private var isConnected = false

    func connect() { isConnected = true }

    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] {
        guard isConnected else { throw URLError(.notConnectedToInternet) }
        return []
    }

    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot { .empty }
    func lineNotices(for line: Line) async throws -> [LineNotice] { [] }
}

/// Holds a load at the gate while it is closed, so a test can look at the screen while new trains load.
private actor GatedRepository: ScheduleRepository {
    private var isOpen = true
    /// The one day held at the closed gate; nil holds every day.
    private var heldDay: ServiceDay?
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var watchers: [CheckedContinuation<Void, Never>] = []

    func close(day: ServiceDay? = nil) {
        isOpen = false
        heldDay = day
    }

    func open() {
        isOpen = true
        parked.forEach { $0.resume() }
        parked = []
    }

    /// Returns once a load waits at the closed gate.
    func held() async {
        guard parked.isEmpty else { return }
        await withCheckedContinuation { watchers.append($0) }
    }

    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] {
        if !isOpen, heldDay == nil || heldDay == day {
            watchers.forEach { $0.resume() }
            watchers = []
            await withCheckedContinuation { parked.append($0) }
        }
        return []
    }

    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot { .empty }
    func lineNotices(for line: Line) async throws -> [LineNotice] { [] }
}
