import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The Schedule screen on real GO data (TT-130): Oakville GO to Union Station GO on Mon Nov 9 at 5:10 AM from the feed
/// sample, just before the first train, so the top of the timeline is the present (a snapshot cannot scroll to Now):
/// scheduled times only and "Platform pending" on every card. Compare with design/frames/schedule-timeline.png and
/// schedule-timeline-dark.png.
final class ScheduleGTFSSnapshotTests: XCTestCase {
    @MainActor func testRealScheduleLight() async throws { snap(try await model(), .light) }
    @MainActor func testRealScheduleDark() async throws { snap(try await model(), .dark) }

    @MainActor
    private func model() async throws -> ScheduleViewModel {
        let zip = try GTFSTimetableTests.sampleZip()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let monday = ServiceDay(year: 2026, month: 11, day: 9)
        let clock = FixedClock(now: monday.date(hour: 5, minute: 10))
        let repository = GTFSScheduleRepository(store: GTFSFeedStore(directory: directory, clock: clock, download: { zip }))
        let route = try await repository.route(
            from: Station(id: "OA", name: "Oakville GO"), to: Station(id: "UN", name: "Union Station GO")
        )
        let model = ScheduleViewModel(route: route, repository: repository, clock: clock)
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
                // The 6:17 card sits under the tab bar's top edge, whose blur draws about 80 of its pixels a shade (up to
                // 3/255) differently from one run to the next; a card moved by even 1 px changes thousands.
                precision: glassSnapshotPrecision,
                perceptualPrecision: 0.98,
                layout: .device(config: .iPhone17Pro),
                traits: UITraitCollection(userInterfaceStyle: style)
            ).comparedAsRecorded,
            testName: testName,
            line: line
        )
    }
}
