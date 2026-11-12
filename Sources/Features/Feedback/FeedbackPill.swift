import SwiftUI

/// The early-stage "Feedback" pill at the end of Schedule's line row (TT-202, D85): accent on the soft accent fill, 30 pt
/// tall like the Notice chip (solid, as text never sits on glass), icon only while the Notice chip shares the row. It opens the feedback sheet. To remove it after the early
/// stage, set `isEarlyStage` to false; Settings › Support stays.
struct FeedbackPill: View {
    static let isEarlyStage = true

    /// Icon only, so the line's name keeps its room next to the Notice chip.
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "text.bubble")
                    .font(.system(size: TTSize.iconSM + 1, weight: .semibold))
                if !compact {
                    Text("schedule.feedback")
                        .font(TTFont.badgeLarge)
                        .tracking(-0.2)
                }
            }
            .foregroundStyle(TTColor.accent)
            .padding(.leading, compact ? 0 : 10)
            .padding(.trailing, compact ? 0 : TTSpace.s3)
            .frame(width: compact ? 30 : nil, height: 30)
            .background(TTColor.accentSoft, in: Capsule())
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .padding(.vertical, -7)
        .fixedSize()
        .accessibilityLabel(Text("schedule.feedback"))
        .accessibilityIdentifier("schedule.feedback")
    }
}

/// The pill with the sheet it opens, so Schedule only places it.
struct ScheduleFeedbackEntry: View {
    var compact = false
    @State private var showsSheet = false
    @Environment(\.feedbackSender) private var sender

    var body: some View {
        FeedbackPill(compact: compact) { showsSheet = true }
            .sheet(isPresented: $showsSheet) { FeedbackSheet(viewModel: FeedbackViewModel(sender: sender)) }
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
}
