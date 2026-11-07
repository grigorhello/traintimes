import Foundation

/// What the Schedule tab and the route form read: GO Transit's GTFS feed and the device clock in the app (TT-130, D35);
/// the fixture repository and clock from `Fixtures.json` in previews and tests (D20).
struct ScheduleDependencies {
    let repository: any ScheduleRepository
    let stations: any StationRepository
    let clock: any AppClock

    /// The app's schedule. Debug builds keep the fixtures for Xcode previews, the unit test host and UI tests, which set
    /// `TT_FIXTURES` in the launch environment so they never download the feed.
    static func app(environment: [String: String] = ProcessInfo.processInfo.environment) -> ScheduleDependencies {
        #if DEBUG
        if ["TT_FIXTURES", "XCTestConfigurationFilePath", "XCODE_RUNNING_FOR_PREVIEWS"].contains(where: { environment[$0] != nil }) {
            return .fixtures()
        }
        #endif
        let repository = GTFSScheduleRepository(store: .shared)
        return ScheduleDependencies(repository: repository, stations: repository, clock: SystemClock())
    }

    /// `Fixtures.json` ships in Debug builds and the unit test bundle only, so Release gets an empty schedule here.
    static func fixtures(bundle: Bundle = .main) -> ScheduleDependencies {
        guard let repository = try? FixtureScheduleRepository(bundle: bundle) else {
            return ScheduleDependencies(repository: NoScheduleRepository(), stations: NoScheduleRepository(), clock: SystemClock())
        }
        return ScheduleDependencies(repository: repository, stations: repository, clock: FixedClock(now: repository.now))
    }
}

extension ScheduleViewModel {
    /// Previews: the canvas route on the canvas clock (Thu Nov 5, 7:21 AM) from `Fixtures.json`.
    static func fixtures(bundle: Bundle = .main) -> ScheduleViewModel {
        guard let repository = try? FixtureScheduleRepository(bundle: bundle) else {
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
