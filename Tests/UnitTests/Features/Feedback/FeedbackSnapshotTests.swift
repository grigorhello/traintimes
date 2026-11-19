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

    /// The button as it asks (TT-228, D107), frozen about 1000 ms in: solid fill, the question bubble, tilted and grown.
    @MainActor func testPillAsksLight() async throws { try await snapSchedule(.loadedFixture(), .light, asks: true) }
    @MainActor func testPillAsksDark() async throws { try await snapSchedule(.loadedFixture(), .dark, asks: true) }
    @MainActor func testRoundButtonAsksLight() async throws { try await snapSchedule(.loadedFixture(.delayed), .light, asks: true) }
    @MainActor func testRoundButtonAsksDark() async throws { try await snapSchedule(.loadedFixture(.delayed), .dark, asks: true) }

    /// The labelled pill, which a short line name leaves room for, at rest and as it asks (grown to 1.06, label on accent).
    @MainActor func testLabelledPillAsksLight() { snapPill(.light) }
    @MainActor func testLabelledPillAsksDark() { snapPill(.dark) }

    // MARK: Helpers

    @MainActor
    private func snapPill(_ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = HStack(spacing: TTSpace.s5) {
            FeedbackPill {}
            FeedbackPill(pose: .asking) {}
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TTColor.canvas)
        assertSnapshot(
            of: view,
            as: .image(perceptualPrecision: 0.98, layout: .fixed(width: 330, height: 80), traits: UITraitCollection(userInterfaceStyle: style)),
            testName: testName,
            line: line
        )
    }

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
    private func snapSchedule(
        _ schedule: ScheduleViewModel, _ style: UIUserInterfaceStyle, asks: Bool = false, testName: String = #function, line: UInt = #line
    ) {
        let view = RootView(schedule: schedule, settings: AppSettings(defaults: .ephemeral()))
            .environment(\.showsFeedbackPill, true)
            .environment(\.feedbackNudgeFrozen, asks)
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
