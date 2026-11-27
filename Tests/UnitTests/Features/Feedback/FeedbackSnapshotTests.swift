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

    /// The button as it asks (TT-228, D112; drawn since TT-252, D128), frozen about 1000 ms in: solid fill, the drawn
    /// question mark in the bubble, tilted and grown.
    @MainActor func testPillAsksLight() async throws { try await snapSchedule(.loadedFixture(), .light, asks: true) }
    @MainActor func testPillAsksDark() async throws { try await snapSchedule(.loadedFixture(), .dark, asks: true) }
    @MainActor func testRoundButtonAsksLight() async throws { try await snapSchedule(.loadedFixture(.delayed), .light, asks: true) }
    @MainActor func testRoundButtonAsksDark() async throws { try await snapSchedule(.loadedFixture(.delayed), .dark, asks: true) }

    /// The Feedback button at the end of the Alerts and Settings titles (TT-252, D128), at rest.
    @MainActor func testAlertsTabButtonLight() async throws { try await snapSchedule(.loadedFixture(), .light, tab: .alerts) }
    @MainActor func testAlertsTabButtonDark() async throws { try await snapSchedule(.loadedFixture(), .dark, tab: .alerts) }
    @MainActor func testSettingsTabButtonLight() async throws { try await snapSchedule(.loadedFixture(), .light, tab: .settings) }
    @MainActor func testSettingsTabButtonDark() async throws { try await snapSchedule(.loadedFixture(), .dark, tab: .settings) }

    /// The labelled pill, which a short line name leaves room for, at rest and as it asks (label on accent).
    @MainActor func testLabelledPillAsksLight() { snapPill(.light) }
    @MainActor func testLabelledPillAsksDark() { snapPill(.dark) }

    /// The play frame by frame (TT-252, D128), from the keyframes themselves: the lines pull back, the hook is drawn, the
    /// dot pops, the bounce, the mark erased and the lines written again, back at rest.
    @MainActor func testMotionFramesLight() { snapFrames(.light) }
    @MainActor func testMotionFramesDark() { snapFrames(.dark) }

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

    /// Times in the play, in seconds, for `snapFrames`.
    static let frameTimes: [Double] = [0, 0.1, 0.2, 0.3, 0.4, 0.55, 0.75, 1.0, 1.12, 1.4, 1.9, 2.0, 2.1, 2.25, 2.4, 2.6]

    @MainActor
    private func snapFrames(_ style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let rows = stride(from: 0, to: Self.frameTimes.count, by: 4).map { Array(Self.frameTimes[$0..<min($0 + 4, Self.frameTimes.count)]) }
        let view = VStack(spacing: 10) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { time in
                        VStack(spacing: 6) {
                            FeedbackPill(compact: true, pose: FeedbackNudgeMotion.frame(at: time)) {}
                                .frame(height: 44)
                            Text(String(format: "%.2f s", time))
                                .font(TTFont.footnote)
                                .foregroundStyle(TTColor.inkSecondary)
                        }
                        .frame(width: 70)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TTColor.canvas)
        assertSnapshot(
            of: view,
            as: .image(perceptualPrecision: 0.98, layout: .fixed(width: 330, height: 330), traits: UITraitCollection(userInterfaceStyle: style)),
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
        _ schedule: ScheduleViewModel, _ style: UIUserInterfaceStyle, asks: Bool = false, tab: AppTab = .schedule,
        testName: String = #function, line: UInt = #line
    ) {
        let router = AppRouter()
        router.selectedTab = tab
        let view = RootView(router: router, schedule: schedule, settings: AppSettings(defaults: .ephemeral()))
            .environment(\.showsFeedbackPill, true)
            .environment(\.rendersGlass, false)
            .environment(\.playsSettingsMotion, false)
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
            ).keepingTop(Self.headerHeight).comparedAsRecorded,
            testName: testName,
            line: line
        )
    }

    /// Schedule's header (title row, route card, day strip) and the Alerts and Settings titles, where the button is. The
    /// system glass tab bar at the bottom is left out: in dark it settles in one of two looks from run to run (main's run
    /// on 22f362d drew the other one, the same 0.9970913 / 0.92964846 in two tests), and it is not what these test.
    private static let headerHeight: CGFloat = 300
}
