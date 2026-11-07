import Foundation

/// What the Schedule tab and the route form read in M1 (D20, D26, D28): the fixture repository and clock from
/// `Fixtures.json` in Debug builds. The file ships in Debug only, so Release has no schedule or stations until TT-130.
struct ScheduleDependencies {
    let repository: any ScheduleRepository
    let stations: any StationRepository
    let clock: any AppClock

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

/// Stands in where there is no schedule source yet; the live GTFS repository arrives in TT-130.
private struct NoScheduleRepository: ScheduleRepository, StationRepository {
    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] { [] }
    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot { .empty }
    func lineNotices(for line: Line) async throws -> [LineNotice] { [] }
    func stations() async throws -> [Station] { [] }
    func route(from: Station, to: Station) async throws -> Route { Route(from: from, to: to, line: nil) }
}
