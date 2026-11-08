import Foundation

/// What the Schedule tab and the route form read: GO Transit's GTFS feed, its GTFS-realtime TripUpdates and Alerts feeds
/// when the app is built with the Metrolinx key, and the device clock in the app (TT-130, TT-131, TT-132, D35 to D37);
/// the fixture repository and clock from `Fixtures.json` in previews and tests (D20).
struct ScheduleDependencies {
    let repository: any ScheduleRepository
    let stations: any StationRepository
    let clock: any AppClock

    /// The app's schedule. Debug builds keep the fixtures for Xcode previews, the unit test host and UI tests, which set
    /// `TT_FIXTURES` in the launch environment so they never download the feed; `TT_FIXTURES=delayed` picks that fixture
    /// scenario.
    static func app(environment: [String: String] = ProcessInfo.processInfo.environment) -> ScheduleDependencies {
        #if DEBUG
        if isFixtureRun(environment) {
            return .fixtures(scenario: environment["TT_FIXTURES"].flatMap { FixtureScheduleRepository.Scenario(rawValue: $0) } ?? .normal)
        }
        #endif
        let key = GTFSRealtimeStore.apiKey()
        let repository = GTFSScheduleRepository(
            store: .shared,
            live: key.map { GTFSRealtimeStore.metrolinx(apiKey: $0) },
            alerts: key.map { GTFSRealtimeStore.metrolinx(apiKey: $0, url: GTFSRealtimeStore.alertsURL) }
        )
        return ScheduleDependencies(repository: repository, stations: repository, clock: SystemClock())
    }

    /// Xcode previews, the unit test host and UI tests run on the fixtures (Debug builds only).
    static func isFixtureRun(_ environment: [String: String]) -> Bool {
        ["TT_FIXTURES", "XCTestConfigurationFilePath", "XCODE_RUNNING_FOR_PREVIEWS"].contains { environment[$0] != nil }
    }

    /// `Fixtures.json` ships in Debug builds and the unit test bundle only, so Release gets an empty schedule here.
    static func fixtures(scenario: FixtureScheduleRepository.Scenario = .normal, bundle: Bundle = .main) -> ScheduleDependencies {
        guard let repository = try? FixtureScheduleRepository(scenario: scenario, bundle: bundle) else {
            return ScheduleDependencies(repository: NoScheduleRepository(), stations: NoScheduleRepository(), clock: SystemClock())
        }
        return ScheduleDependencies(repository: repository, stations: repository, clock: FixedClock(now: repository.now))
    }
}

extension ScheduleViewModel {
    /// Previews: the canvas route on the canvas clock (Thu Nov 5, 7:21 AM) from `Fixtures.json`.
    static func fixtures(scenario: FixtureScheduleRepository.Scenario = .normal, bundle: Bundle = .main) -> ScheduleViewModel {
        guard let repository = try? FixtureScheduleRepository(scenario: scenario, bundle: bundle) else {
            return ScheduleViewModel(route: nil, repository: NoScheduleRepository(), clock: SystemClock())
        }
        return ScheduleViewModel(route: repository.route, repository: repository, clock: FixedClock(now: repository.now))
    }
}

/// Stands in where `Fixtures.json` is missing.
private struct NoScheduleRepository: ScheduleRepository, StationRepository {
    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] { [] }
    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot { .empty }
    func lineNotices(for line: Line) async throws -> [LineNotice] { [] }
    func stations() async throws -> [Station] { [] }
    func route(from: Station, to: Station) async throws -> Route { Route(from: from, to: to, line: nil) }
}
