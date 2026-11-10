import Foundation
@testable import TrainTimes

private final class BundleToken {}

extension ScheduleViewModel {
    /// The canvas route on the fixture clock (Thu Nov 5, 7:21 AM), already loaded so a snapshot never races the first
    /// load. `dayIndex` picks a day strip cell counted from Today (3 is Sun 8, -1 is Wed 4). `minutesLater` moves the
    /// clock on from 7:21 AM; the feed stays at 7:21 AM, so more than 3 min later it is stale.
    @MainActor
    static func loadedFixture(
        _ scenario: FixtureScheduleRepository.Scenario = .normal, dayIndex: Int = 0, minutesLater: Int = 0
    ) async throws -> ScheduleViewModel {
        let repository = try FixtureScheduleRepository(scenario: scenario, bundle: Bundle(for: BundleToken.self))
        let model = ScheduleViewModel(
            route: repository.route,
            repository: repository,
            clock: FixedClock(now: repository.now.addingTimeInterval(TimeInterval(minutesLater * 60)))
        )
        await model.loadIfNeeded()
        if dayIndex > 0 { await model.select(model.days[dayIndex]) }
        if dayIndex < 0 { await model.select(model.pastDays[model.pastDays.count + dayIndex]) }
        return model
    }
}
