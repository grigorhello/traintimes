import SnapshotTesting
import SwiftUI
import XCTest
@testable import TrainTimes

/// The feedback sheet (TT-202, D85), light and dark: empty, a question that failed to send, and sent. And Schedule's
/// early-stage Feedback pill on the line row, which the unit test host hides from every other snapshot. Glass is drawn as
/// its solid fallback (`\.rendersGlass` off) so a dark glass control cannot differ between runs.
final class FeedbackSnapshotTests: XCTestCase {
    @MainActor func testEmptyLight() { snap(model(), .light) }
    @MainActor func testEmptyDark() { snap(model(), .dark) }
    @MainActor func testFailedLight() async { snap(await failed(), .light) }
    @MainActor func testFailedDark() async { snap(await failed(), .dark) }
    @MainActor func testSentLight() async { snap(await sent(), .light) }
    @MainActor func testSentDark() async { snap(await sent(), .dark) }

    @MainActor func testSchedulePillLight() async throws { try await snapSchedule(.loadedFixture(), .light) }
    /// With the Notice chip, the pill is icon only.
    @MainActor func testSchedulePillWithNoticeDark() async throws { try await snapSchedule(.loadedFixture(.delayed), .dark) }

    // MARK: Helpers

    @MainActor
    private func model(_ sender: any FeedbackSending = RecordingFeedbackSender()) -> FeedbackViewModel {
        FeedbackViewModel(sender: sender, context: FeedbackContext(appVersion: "1.0 (45)", device: "iPhone18,1", osVersion: "26.1.0"))
    }

    @MainActor
    private func failed() async -> FeedbackViewModel {
        let sender = RecordingFeedbackSender()
        sender.fails = true
        let model = model(sender)
        model.kind = .question
        model.message = "Does the app show Kitchener line trains on weekends?"
        model.email = "rider@example.com"
        await model.send()
        return model
    }

    @MainActor
    private func sent() async -> FeedbackViewModel {
        let model = model()
        model.message = "Love the timeline."
        await model.send()
        return model
    }

    @MainActor
    private func snap(_ model: FeedbackViewModel, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = FeedbackSheet(viewModel: model, focusesMessage: false)
            .environment(\.rendersGlass, false)
            .environment(\.playsSettingsMotion, false)
        assertSnapshot(
            of: view,
            as: .image(
                drawHierarchyInKeyWindow: true,
                perceptualPrecision: 0.98,
                layout: .device(config: .iPhone17Pro),
                traits: UITraitCollection(userInterfaceStyle: style)
            ).comparedAsRecorded,
            testName: testName,
            line: line
        )
    }

    @MainActor
    private func snapSchedule(_ schedule: ScheduleViewModel, _ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = RootView(schedule: schedule, settings: AppSettings(defaults: .ephemeral()))
            .environment(\.showsFeedbackPill, true)
        layOutOnce(view)
        assertSnapshot(
            of: view,
            as: .image(
                drawHierarchyInKeyWindow: true,
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
