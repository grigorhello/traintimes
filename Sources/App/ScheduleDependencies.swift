import Foundation

extension ScheduleViewModel {
    /// M1 runs on fixtures (D20): the canvas route on the canvas clock (Thu Nov 5, 7:21 AM) from `Fixtures.json`.
    /// The file ships in Debug builds only; without it the screen has no route until the route form lands (TT-120).
    static func fixtures(bundle: Bundle = .main) -> ScheduleViewModel {
        guard let repository = try? FixtureScheduleRepository(bundle: bundle) else {
            return ScheduleViewModel(route: nil, repository: NoScheduleRepository(), clock: SystemClock())
        }
        return ScheduleViewModel(route: repository.route, repository: repository, clock: FixedClock(now: repository.now))
    }
}

/// Stands in where there is no schedule source yet; the live GTFS repository arrives in TT-130.
private struct NoScheduleRepository: ScheduleRepository {
    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] { [] }
    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot { .empty }
    func lineNotices(for line: Line) async throws -> [LineNotice] { [] }
}
