import Foundation
@testable import TrainTimes

private final class BundleToken {}

extension ScheduleViewModel {
    /// The canvas route on the fixture clock (Thu Nov 5, 7:21 AM), already loaded so a snapshot never races the first
    /// load. `dayIndex` picks a day strip cell (3 is Sun 8); the star is on, as in the frames.
    @MainActor
    static func loadedFixture(dayIndex: Int = 0, minutesLater: Int = 0, isFavourite: Bool = true) async throws -> ScheduleViewModel {
        let repository = try FixtureScheduleRepository(bundle: Bundle(for: BundleToken.self))
        let model = ScheduleViewModel(
            route: repository.route,
            repository: repository,
            clock: FixedClock(now: repository.now.addingTimeInterval(TimeInterval(minutesLater * 60))),
            isFavourite: isFavourite
        )
        await model.loadIfNeeded()
        if dayIndex > 0 { await model.select(model.days[dayIndex]) }
        return model
    }
}
