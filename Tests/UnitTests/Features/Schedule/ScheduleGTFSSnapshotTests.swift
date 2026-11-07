import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The Schedule screen on real GO data (TT-130): Oakville GO to Union Station GO on Mon Nov 9 at 7:21 AM from the feed
/// sample, scheduled times only, Express on the peak trains that run non-stop from Clarkson, "Platform pending" on every
/// card. Compare with design/frames/schedule-timeline.png and schedule-timeline-dark.png.
final class ScheduleGTFSSnapshotTests: XCTestCase {
    @MainActor func testRealScheduleLight() async throws { snap(try await model(), .light) }
    @MainActor func testRealScheduleDark() async throws { snap(try await model(), .dark) }

    @MainActor
    private func model() async throws -> ScheduleViewModel {
        let zip = try GTFSTimetableTests.sampleZip()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let monday = ServiceDay(year: 2026, month: 11, day: 9)
        let clock = FixedClock(now: monday.date(hour: 7, minute: 21))
        let repository = GTFSScheduleRepository(store: GTFSFeedStore(directory: directory, clock: clock, download: { zip }))
        let route = try await repository.route(
            from: Station(id: "OA", name: "Oakville GO"), to: Station(id: "UN", name: "Union Station GO")
        )
        let model = ScheduleViewModel(route: route, repository: repository, clock: clock, favourites: Favourites(defaults: .ephemeral()))
        await model.loadIfNeeded()
        return model
    }

    @MainActor
    private func snap(_ schedule: ScheduleViewModel, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = RootView(schedule: schedule, settings: AppSettings(defaults: .ephemeral()))
        layOutOnce(view)
        assertSnapshot(
            of: view,
            as: .image(
                drawHierarchyInKeyWindow: true,
                perceptualPrecision: 0.98,
                layout: .device(config: .iPhone17Pro),
                traits: UITraitCollection(userInterfaceStyle: style)
            ),
            testName: testName,
            line: line
        )
    }
}
