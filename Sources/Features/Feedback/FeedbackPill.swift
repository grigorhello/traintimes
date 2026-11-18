import SwiftUI

/// The early-stage "Feedback" pill at the end of Schedule's line row (TT-202, D85): accent on the soft accent fill, 30 pt
/// tall like the Notice chip (solid, as text never sits on glass), icon only while the Notice chip shares the row. It opens the feedback sheet. To remove it after the early
/// stage, set `isEarlyStage` to false; Settings › Support stays.
struct FeedbackPill: View {
    nonisolated static let isEarlyStage = true

    /// Icon only, so the line's name keeps its room next to the Notice chip.
    var compact = false
    /// Where it is in asking (TT-228, D106): at rest unless the nudge plays.
    var pose = FeedbackNudgeMotion.Pose.rest
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .foregroundStyle(pose.filled ? TTColor.onAccent : TTColor.accent)
            .padding(.leading, compact ? 0 : 10)
            .padding(.trailing, compact ? 0 : TTSpace.s3)
            .frame(width: compact ? 30 : nil, height: 30)
            .background(pose.filled ? TTColor.accent : TTColor.accentSoft, in: Capsule())
            .scaleEffect(grows ? (compact ? FeedbackNudgeMotion.buttonScale : FeedbackNudgeMotion.pillScale) : 1)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .padding(.vertical, -7)
        .fixedSize()
        .accessibilityLabel(Text("schedule.feedback"))
        .accessibilityIdentifier("schedule.feedback")
    }

    private var grows: Bool { pose.filled && !reduceMotion }

    /// The text bubble, or the question bubble while it asks: the bubble stays and only what is inside it changes (the
    /// symbols' replace), tilted like a head asking. Reduce Motion cross-fades them, with no tilt or growth.
    private var glyph: some View {
        let tilts = pose.tilted && !reduceMotion
        return Image(systemName: pose.asks ? "questionmark.bubble" : "text.bubble")
            .font(.system(size: TTSize.iconSM + 1, weight: .semibold))
            .modifier(BubbleReplace(crossFades: reduceMotion))
            .rotationEffect(.degrees(tilts ? FeedbackNudgeMotion.tilt : 0))
            .scaleEffect(tilts ? FeedbackNudgeMotion.glyphScale : 1)
    }
}

/// The symbols' magic replace where iOS has it (the shared bubble stays, the lines become the question mark), else their
/// replace; a cross-fade with Reduce Motion.
private struct BubbleReplace: ViewModifier {
    let crossFades: Bool

    func body(content: Content) -> some View {
        if crossFades {
            content.contentTransition(.opacity)
        } else if #available(iOS 18, *) {
            content.contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer)))
        } else {
            content.contentTransition(.symbolEffect(.replace.downUp.byLayer))
        }
    }
}

/// The pill with the sheet it opens, so Schedule only places it. Icon only while the Notice chip shows, and whenever the
/// labelled pill would cut the line's name short (Lakeshore West): the name is laid out first (`layoutPriority`). It asks
/// each time the app's `FeedbackNudge` says so (TT-228, D106).
struct ScheduleFeedbackEntry: View {
    var compact = false
    @State private var showsSheet = false
    @State private var pose = FeedbackNudgeMotion.Pose.rest
    @State private var playing: Task<Void, Never>?
    @Environment(\.feedbackSender) private var sender
    @Environment(\.feedbackNudge) private var nudge
    @Environment(\.feedbackNudgeFrozen) private var frozen

    var body: some View {
        let shown = frozen ? FeedbackNudgeMotion.Pose.asking : pose
        Group {
            if compact {
                FeedbackPill(compact: true, pose: shown) { open() }
            } else {
                ViewThatFits(in: .horizontal) {
                    FeedbackPill(pose: shown) { open() }
                    FeedbackPill(compact: true, pose: shown) { open() }
                }
            }
        }
        .sheet(isPresented: $showsSheet) { FeedbackSheet(viewModel: FeedbackViewModel(sender: sender)) }
        .onChange(of: nudge?.playRequest) { play() }
        // Back at rest when the sheet closes, even if it was opened mid-play.
        .onChange(of: showsSheet) { _, shows in
            guard !shows else { return }
            playing?.cancel()
            pose = .rest
        }
        .onDisappear { playing?.cancel() }
    }

    private func open() {
        nudge?.sheetOpened(from: .schedule)
        showsSheet = true
    }

    /// The steps of `FeedbackNudgeMotion`, each at its time from the start. No haptic (D95 rule 1).
    private func play() {
        playing?.cancel()
        playing = Task { @MainActor in
            var elapsed = 0.0
            for step in FeedbackNudgeMotion.steps {
                if step.at > elapsed {
                    try? await Task.sleep(for: .seconds(step.at - elapsed))
                    elapsed = step.at
                }
                guard !Task.isCancelled else { return }
                var next = pose
                step.apply(&next)
                withAnimation(step.animation) { pose = next }
            }
        }
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
    /// Snapshots draw the button as it asks, about 1000 ms in, as the swap is frozen with `\.swapFrozenAt`.
    @Entry var feedbackNudgeFrozen = false
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
