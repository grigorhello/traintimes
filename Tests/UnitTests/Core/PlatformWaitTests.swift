import XCTest
@testable import TrainTimes

/// TT-162 (D55): when the next train's card shows the pulsing pill in place of the dash, and the Awaiting platform demo
/// mode that makes it visible.
@MainActor
final class PlatformWaitTests: XCTestCase {
    private let day = ServiceDay(year: 2026, month: 11, day: 5)
    private let formatter = TimeFormatter(format: .twelveHour)
    private var departure: Date { day.date(hour: 7, minute: 32) }
    private var fresh: Freshness { .live(updatedAt: departure.addingTimeInterval(-600)) }

    private func train(platform: Platform = .pending, status: TrainStatus = .onTime) -> Departure {
        let trip = Trip(
            key: TripKey(serviceDay: day, tripId: "LW-0732"), scheduledDeparture: departure,
            scheduledArrival: departure.addingTimeInterval(40 * 60), platform: platform, tags: []
        )
        return Departure(trip: trip, status: status, expectedDeparture: nil, expectedArrival: nil)
    }

    private func waits(
        _ departure: Departure? = nil, isNext: Bool = true, minutesBefore: Double = 11, freshness: Freshness? = nil,
        source: Bool = true
    ) -> Bool {
        (departure ?? train()).awaitsPlatform(
            isNext: isNext, now: self.departure.addingTimeInterval(-minutesBefore * 60), freshness: freshness ?? fresh,
            hasPlatformSource: source
        )
    }

    func testNextTrainInTheWindowWaits() {
        XCTAssertTrue(waits())
        XCTAssertTrue(waits(minutesBefore: 15), "\"in 15 min\" is still inside")
        XCTAssertTrue(waits(minutesBefore: 1), "\"in 1 min\" is the last minute")
        XCTAssertTrue(waits(train(status: .delayed(minutes: 9, reportedAt: departure)), minutesBefore: 11))
    }

    func testEveryOtherCardKeepsTheDash() {
        XCTAssertFalse(waits(isNext: false), "A later train")
        XCTAssertFalse(waits(minutesBefore: 16), "Over 15 min out")
        XCTAssertFalse(waits(minutesBefore: 0.5), "Under a minute: Departing")
        XCTAssertFalse(waits(minutesBefore: -2), "Already left")
        XCTAssertFalse(waits(freshness: .offline(lastUpdated: departure)), "Offline")
        XCTAssertFalse(waits(freshness: .stale(lastReported: departure)), "Stale")
        XCTAssertFalse(waits(freshness: .scheduledOnly), "No live data, as on another day")
        XCTAssertFalse(waits(source: false), "No platform source: the real feeds, D35 and D36")
        XCTAssertFalse(waits(train(status: .cancelled(reportedAt: departure))), "Cancelled")
        XCTAssertFalse(waits(train(status: .stopSkipped)), "Stop skipped")
        XCTAssertFalse(waits(train(platform: .published("2"))), "The platform is published")
    }

    func testTheCardCarriesTheRule() {
        let card = DepartureCard(train(), isNext: true, awaitsPlatform: true, now: departure, formatter: formatter)
        XCTAssertTrue(card.awaitsPlatform)
        XCTAssertEqual(card.platformLabel, "Plat")
        XCTAssertEqual(card.platform, "Plat —", "The dash text stays for the card's label and the other states")
        XCTAssertFalse(DepartureCard(train(), isNext: true, now: departure, formatter: formatter).awaitsPlatform)
    }

    // MARK: Awaiting platform

    private func awaitingModel(minutesLater: Int = 0) async throws -> ScheduleViewModel {
        let base = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let clock = FixedClock(now: base.now.addingTimeInterval(TimeInterval(minutesLater * 60)))
        let repository = DemoScheduleRepository(base: base, clock: clock, mode: { .awaitingPlatform })
        let model = ScheduleViewModel(route: base.route, repository: repository, clock: clock)
        await model.loadIfNeeded()
        return model
    }

    /// The fixture's 7:32 train leaves in 11 min with platform 2; the demo takes the platform away and has it leave in 8.
    func testAwaitingPlatformPutsThePillOnTheNextTrainOnly() async throws {
        let model = try await awaitingModel()
        let cards = model.cards(formatter)
        XCTAssertEqual(cards.map(\.awaitsPlatform), [true, false, false, false])
        XCTAssertEqual(cards.map(\.hasPlatform), [false, false, false, false])
        XCTAssertEqual(cards[0].relativeTime, "in 8 min")
        XCTAssertEqual(cards[0].time, "7:29 AM")
        XCTAssertEqual(cards[0].arrivalTime, "8:09 AM", "The arrival moves with the departure")
        XCTAssertEqual(cards[0].status, .onTime)
        XCTAssertEqual(Array(cards.map(\.time).dropFirst()), ["7:58 AM", "8:21 AM", "8:50 AM"], "The others keep their times")
    }

    /// A train nearer than 8 min stays where it is; it still waits while its countdown shows.
    func testAwaitingPlatformLeavesANearTrainAlone() async throws {
        let model = try await awaitingModel(minutesLater: 6) // 7:27 AM, the 7:32 train is 5 min away
        let cards = model.cards(formatter)
        XCTAssertEqual(cards[0].time, "7:32 AM")
        XCTAssertEqual(cards[0].relativeTime, "in 5 min")
        XCTAssertTrue(cards[0].awaitsPlatform)
    }

    func testAnotherDayKeepsItsTimesAndTheDash() async throws {
        let base = try FixtureScheduleRepository(bundle: Bundle(for: Self.self))
        let clock = FixedClock(now: base.now)
        func tomorrow(_ mode: DemoTrains) async -> [DepartureCard] {
            let repository = DemoScheduleRepository(base: base, clock: clock, mode: { mode })
            let model = ScheduleViewModel(route: base.route, repository: repository, clock: clock)
            await model.loadIfNeeded()
            await model.select(model.days[1])
            return model.cards(formatter)
        }
        let waiting = await tomorrow(.awaitingPlatform)
        let real = await tomorrow(.off)
        XCTAssertFalse(waiting.isEmpty)
        XCTAssertFalse(waiting.contains { $0.awaitsPlatform })
        XCTAssertEqual(waiting.map(\.time), real.map(\.time), "No train is moved on another day")
    }

    func testRealFeedsNeverWait() async throws {
        let model = try await ScheduleViewModel.loadedFixture()
        XCTAssertFalse(model.hasPlatformSource)
        XCTAssertFalse(model.cards(formatter).contains { $0.awaitsPlatform })
    }

    func testAwaitingPlatformIsStoredLikeTheOtherModes() {
        XCTAssertEqual(DemoTrains(rawValue: "awaitingPlatform"), .awaitingPlatform)
        let defaults = UserDefaults.ephemeral()
        let settings = AppSettings(defaults: defaults)
        settings.demoTrains = .awaitingPlatform
        XCTAssertEqual(AppSettings(defaults: defaults).demoTrains, .awaitingPlatform)
    }
}
