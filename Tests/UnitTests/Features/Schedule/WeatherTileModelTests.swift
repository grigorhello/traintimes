import XCTest
@testable import TrainTimes

/// TT-226: the one-hour cache, the offline fallback, a route change and the two events.
@MainActor
final class WeatherTileModelTests: XCTestCase {
    private let start = ServiceDay(year: 2026, month: 11, day: 5).date(hour: 7, minute: 21)
    private let oakville = Station(id: "OA", name: "Oakville GO", place: GeoPoint(latitude: 43.45, longitude: -79.68))
    private let union = Station(id: "UN", name: "Union Station GO", place: GeoPoint(latitude: 43.645, longitude: -79.38))

    override func tearDown() {
        Analytics.tracker = nil
        super.tearDown()
    }

    func testKeepsTheForecastForAnHour() async throws {
        let clock = TestClock(now: start)
        let provider = FakeWeather()
        let store = WeatherStore(provider: provider, clock: clock, defaults: .ephemeral())
        _ = try await store.forecast(for: oakville)
        clock.advance(minutes: 59)
        _ = try await store.forecast(for: oakville)
        XCTAssertEqual(provider.requests, 1)
        clock.advance(minutes: 2)
        _ = try await store.forecast(for: oakville)
        XCTAssertEqual(provider.requests, 2)
    }

    func testKeptOnDiskPerStation() async throws {
        let clock = TestClock(now: start)
        let defaults = UserDefaults.ephemeral()
        let provider = FakeWeather()
        _ = try await WeatherStore(provider: provider, clock: clock, defaults: defaults).forecast(for: oakville)
        let relaunched = WeatherStore(provider: provider, clock: clock, defaults: defaults)
        XCTAssertNotNil(relaunched.immediate(for: oakville))
        XCTAssertNil(relaunched.immediate(for: union))
        _ = try await relaunched.forecast(for: oakville)
        XCTAssertEqual(provider.requests, 1)
    }

    func testOfflineKeepsTodaysForecast() async throws {
        let clock = TestClock(now: start)
        let provider = FakeWeather()
        let model = WeatherTileModel(store: WeatherStore(provider: provider, clock: clock, defaults: nil), clock: clock)
        await model.refresh(for: oakville)
        provider.failure = .offline
        clock.advance(minutes: 90)
        await model.refresh(for: oakville)
        XCTAssertEqual(provider.requests, 2)
        XCTAssertEqual(model.tile(on: ServiceDay(calendarDayContaining: clock.now)), .shows(icon: .cloud, temperature: "4°"))
    }

    func testOfflineWithNothingSavedTodayIsGrey() async throws {
        let clock = TestClock(now: start)
        let provider = FakeWeather()
        let model = WeatherTileModel(store: WeatherStore(provider: provider, clock: clock, defaults: nil), clock: clock)
        await model.refresh(for: oakville)
        provider.failure = .offline
        clock.advance(minutes: 24 * 60)
        await model.refresh(for: oakville)
        XCTAssertEqual(model.tile(on: ServiceDay(calendarDayContaining: clock.now)), .unavailable(.offline))
        XCTAssertNil(model.sheet(on: ServiceDay(calendarDayContaining: clock.now), formatter: TimeFormatter(format: .twelveHour)))
    }

    func testFirstLoadIsTheSkeleton() {
        let clock = TestClock(now: start)
        let model = WeatherTileModel(store: WeatherStore(provider: FakeWeather(), clock: clock, defaults: nil), clock: clock, station: oakville)
        XCTAssertEqual(model.tile(on: ServiceDay(calendarDayContaining: start)), .loading)
    }

    func testANewFromStationAsksForItsWeather() async throws {
        let clock = TestClock(now: start)
        let provider = FakeWeather()
        let model = WeatherTileModel(store: WeatherStore(provider: provider, clock: clock, defaults: nil), clock: clock)
        await model.refresh(for: oakville)
        await model.refresh(for: union)
        XCTAssertEqual(provider.stations, ["OA", "UN"])
        XCTAssertEqual(model.station, union)
        XCTAssertEqual(model.sheet(on: ServiceDay(calendarDayContaining: start), formatter: TimeFormatter(format: .twelveHour))?.station, "Union Station GO")
    }

    func testScheduleSwapChangesTheStation() async throws {
        let schedule = try await ScheduleViewModel.loadedFixture()
        let from = try XCTUnwrap(schedule.route?.from)
        XCTAssertEqual(schedule.weather.station, from)
        await schedule.swap()
        await schedule.weather.refresh(for: schedule.route?.from)
        XCTAssertEqual(schedule.weather.station, schedule.route?.from)
        XCTAssertNotEqual(schedule.weather.station, from)
    }

    func testOpenedAndUnavailableEvents() async throws {
        let analytics = RecordingAnalytics.install()
        let clock = TestClock(now: start)
        let model = WeatherTileModel(store: WeatherStore(provider: FixtureWeather(), clock: clock, defaults: nil), clock: clock, station: oakville)
        let today = ServiceDay(calendarDayContaining: start)
        let sheet = try XCTUnwrap(model.sheet(on: today.adding(days: 2), formatter: TimeFormatter(format: .twelveHour)))
        model.opened(sheet, on: today.adding(days: 2))
        model.showedUnavailable(nil)
        model.showedUnavailable(model.tile(on: today.adding(days: -1)).unavailableReason)
        model.showedUnavailable(.range)
        model.visitStarted()
        model.showedUnavailable(.range)
        XCTAssertEqual(analytics.events, [
            AnalyticsEvent("weather_opened", ["day_offset": .int(2), "cue": .string("snow")]),
            AnalyticsEvent("weather_unavailable", ["reason": .string("past")]),
            AnalyticsEvent("weather_unavailable", ["reason": .string("range")])
        ])
    }
}

/// Answers with dry cloudy weather (4° now), or fails, and counts the requests.
final class FakeWeather: WeatherProviding, @unchecked Sendable {
    // Unchecked: only touched from the main actor in these tests.
    var requests = 0
    var stations: [String] = []
    var failure: WeatherFailure?

    func forecast(for station: Station, now: Date) async throws -> WeatherForecast {
        requests += 1
        stations.append(station.id)
        if let failure { throw failure }
        return WeatherRulesTests.forecast(now: now)
    }

    func attribution() async -> WeatherCredit? { .fixture }
}
