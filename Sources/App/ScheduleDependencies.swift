import Foundation

/// What the Schedule tab and the route form read: GO Transit's GTFS feed, its GTFS-realtime TripUpdates and Alerts feeds
/// when the app is built with the Metrolinx key, and the device clock in the app (TT-130, TT-131, TT-132, D35 to D37);
/// the fixture repository and clock from `Fixtures.json` in previews and tests (D20).
struct ScheduleDependencies {
    let repository: any ScheduleRepository
    let stations: any StationRepository
    let clock: any AppClock
    /// On board's trips and tracks (TT-171): the GO feed in the app; none in fixture runs, so no ride starts or restores.
    var rides: (any RideDataProviding)?
    /// The trains train detection matches the phone against (TT-175): the GO feed in the app; none in fixture runs.
    var candidates: (any TrainCandidatesProviding)?

    /// The app's schedule. Debug builds keep the fixtures for Xcode previews, the unit test host and UI tests, which set
    /// `TT_FIXTURES` in the launch environment so they never download the feed; `TT_FIXTURES=delayed` picks that fixture
    /// scenario.
    static func app(environment: [String: String] = ProcessInfo.processInfo.environment) -> ScheduleDependencies {
        #if DEBUG
        if isFixtureRun(environment) {
            let scenario = environment["TT_FIXTURES"].flatMap { FixtureScheduleRepository.Scenario(rawValue: $0) } ?? .normal
            return fixtures(scenario: scenario).withTesting()
        }
        #endif
        let key = GTFSRealtimeStore.apiKey()
        let repository = GTFSScheduleRepository(
            store: .shared,
            live: key.map { GTFSRealtimeStore.metrolinx(apiKey: $0) },
            alerts: key.map { GTFSRealtimeStore.metrolinx(apiKey: $0, url: GTFSRealtimeStore.alertsURL) }
        )
        let live = ScheduleDependencies(
            repository: repository, stations: repository, clock: SystemClock(), rides: repository, candidates: repository
        )
        return BuildChannel.showsTesting ? live.withTesting() : live
    }

    /// The same schedule with Settings › Testing applied, in TestFlight and Debug builds only: Demo trains (D49) and Mock
    /// time (TT-158, D51). With both off it changes nothing. Every screen reads the returned clock, so Mock time reaches
    /// Schedule, Trip details and Alerts alike.
    func withTesting() -> ScheduleDependencies {
        let mocked = MockTimeClock(base: clock)
        return ScheduleDependencies(
            repository: DemoScheduleRepository(
                base: repository, clock: mocked, mode: { DemoTrains.stored }, isMockTime: { MockTime.stored != nil }
            ),
            stations: stations,
            clock: mocked,
            rides: rides,
            candidates: candidates
        )
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

extension RideEngine {
    /// The app's one ride engine (TT-171): the GO feed's trips and tracks, the phone's location and the schedule's clock, so
    /// Mock time reaches rides too. Fixture runs keep no ride on device.
    static func app(environment: [String: String] = ProcessInfo.processInfo.environment) -> RideEngine {
        let dependencies = ScheduleDependencies.app(environment: environment)
        return RideEngine(
            data: dependencies.rides,
            location: SystemLocationProvider(),
            clock: dependencies.clock,
            defaults: dependencies.rides == nil ? nil : .standard
        )
    }
}

extension TrainDetector {
    /// The app's train detector (TT-175): the GO feed's trains on the route, the phone's location only while Schedule is
    /// open (no background session, never asking), and the schedule's clock. None in fixture runs.
    static func app(_ dependencies: ScheduleDependencies) -> TrainDetector? {
        guard let candidates = dependencies.candidates else { return nil }
        return TrainDetector(
            candidates: candidates,
            location: SystemLocationProvider(keepsInBackground: false),
            clock: dependencies.clock,
            defaults: .standard
        )
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
