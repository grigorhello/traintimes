import SwiftUI

/// The early-stage "Feedback" pill at the end of Schedule's line row (TT-202, D85): accent on the soft accent fill, 30 pt
/// tall like the Notice chip (solid, as text never sits on glass), icon only while the Notice chip shares the row. It opens the feedback sheet. To remove it after the early
/// stage, set `isEarlyStage` to false; Settings › Support stays.
struct FeedbackPill: View {
    nonisolated static let isEarlyStage = true

    /// Icon only, so the line's name keeps its room next to the Notice chip.
    var compact = false
    /// Where it is in asking (TT-228, D112; TT-252, D128); nil reads `\.feedbackNudgeFrame`, at rest unless the nudge plays.
    var pose: FeedbackNudgeMotion.Frame?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.feedbackNudgeFrame) private var playedFrame

    private var frame: FeedbackNudgeMotion.Frame { pose ?? playedFrame }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                glyph
                if !compact {
                    Text("schedule.feedback")
                        .font(TTFont.badgeLarge)
                        .tracking(-0.2)
                }
            }
            .foregroundStyle(frame.ink >= 0.5 ? TTColor.onAccent : TTColor.accent)
            .padding(.leading, compact ? 0 : 8)
            .padding(.trailing, compact ? 0 : TTSpace.s3)
            .frame(width: compact ? 30 : nil, height: 30)
            .background {
                ZStack {
                    Capsule().fill(TTColor.accentSoft)
                    Capsule().fill(TTColor.accent).opacity(frame.fill)
                }
            }
            .scaleEffect(scale)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .padding(.vertical, -7)
        .fixedSize()
        .accessibilityLabel(Text("schedule.feedback"))
        .accessibilityIdentifier("schedule.feedback")
    }

    /// The bounce; the labelled pill moves less. None with Reduce Motion.
    private var scale: CGFloat {
        guard !reduceMotion else { return 1 }
        return compact ? frame.scale : FeedbackNudgeMotion.pillScale(frame.scale)
    }

    /// The drawn bubble: the outline stays, the lines give way to the question mark, tilted like a head asking. Reduce
    /// Motion cross-fades them, with no tilt or growth.
    private var glyph: some View {
        FeedbackGlyph(frame: frame, crossFades: reduceMotion)
            .rotationEffect(.degrees(reduceMotion ? 0 : frame.tilt))
            .scaleEffect(reduceMotion ? 1 : frame.glyphScale)
    }
}

/// The pill with the sheet it opens, so Schedule only places it. Icon only while the Notice chip shows, and whenever the
/// labelled pill would cut the line's name short (Lakeshore West): the name is laid out first (`layoutPriority`). It asks
/// each time the app's `FeedbackNudge` says so (TT-228, D112; TT-252, D128), played by `KeyframeAnimator` on the render
/// clock from `FeedbackNudgeMotion.keyframes()`.
struct ScheduleFeedbackEntry: View {
    var compact = false
    /// The sheet opened or closed, for Schedule, which counts it as something over it (TT-234).
    var onSheet: (Bool) -> Void = { _ in }
    @State private var showsSheet = false
    @Environment(\.feedbackSender) private var sender
    @Environment(\.feedbackNudge) private var nudge
    @Environment(\.feedbackNudgeFrozen) private var frozen

    var body: some View {
        // Plain values, so the keyframe closures capture these and not the view (TT-252: the frame reaches the pill through
        // the environment, `\.feedbackNudgeFrame`).
        let frozen = self.frozen
        Group {
            if compact {
                FeedbackPill(compact: true) { open() }
            } else {
                ViewThatFits(in: .horizontal) {
                    FeedbackPill { open() }
                    FeedbackPill(compact: true) { open() }
                }
            }
        }
        .keyframeAnimator(initialValue: FeedbackNudgeMotion.Frame.rest, trigger: nudge?.playRequest ?? 0) { view, frame in
            view.environment(\.feedbackNudgeFrame, frozen ? .asking : frame)
        } keyframes: { _ in
            FeedbackNudgeMotion.keyframes()
        }
        .sheet(isPresented: $showsSheet) { FeedbackSheet(viewModel: FeedbackViewModel(sender: sender)) }
        .onChange(of: showsSheet) { _, shows in onSheet(shows) }
    }

    private func open() {
        nudge?.sheetOpened(from: .schedule)
        showsSheet = true
    }
}

/// Where feedback goes: the alert server in the app; the fixture sender in previews, the unit test host and UI tests, so no
/// test ever posts a message.
enum FeedbackDependencies {
    static func sender(environment: [String: String] = ProcessInfo.processInfo.environment) -> any FeedbackSending {
        #if DEBUG
        if ScheduleDependencies.isFixtureRun(environment) { return FixtureFeedbackSender() }
        #endif
        return HTTPFeedbackSender()
    }
}

extension EnvironmentValues {
    /// Schedule's Feedback pill: on in the early stage, off in the unit test host so other snapshots keep their header.
    @Entry var showsFeedbackPill: Bool = FeedbackPill.isEarlyStage && !UnitTestHost.isRunning
    @Entry var feedbackSender: any FeedbackSending = FeedbackDependencies.sender()
    /// The app's feedback nudge (TT-228), from `RootView`; nil plays nothing.
    @Entry var feedbackNudge: FeedbackNudge? = nil
    /// Snapshots draw the button as it asks, about 1000 ms in (`FeedbackNudgeMotion.Frame.asking`), as the swap is frozen
    /// with `\.swapFrozenAt`.
    @Entry var feedbackNudgeFrozen = false
    /// The frame of the play, from `ScheduleFeedbackEntry`'s keyframes to its pills.
    @Entry var feedbackNudgeFrame = FeedbackNudgeMotion.Frame.rest
    /// A sheet is up over Schedule or another tab is selected (`RootView`), so the Feedback button does not ask.
    @Entry var scheduleCovered = false
}

extension FeedbackNudge {
    /// The app's rule: it plays by itself in TestFlight and App Store builds while the Feedback pill is early stage, never
    /// in fixture runs, previews or the unit test host (only when forced from Settings › Testing or the launch argument).
    static func app(environment: [String: String] = ProcessInfo.processInfo.environment) -> FeedbackNudge {
        FeedbackNudge(playsByItself: FeedbackPill.isEarlyStage && !ScheduleDependencies.isFixtureRun(environment))
    }
}
