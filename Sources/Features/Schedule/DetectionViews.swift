import SwiftUI

/// Train detection's question (TT-175; one question since TT-205, D92, *Live-Detect*): "On the train to Clarkson?", asked by
/// the rider's stop, Yes or No. When two trains fit, it is still one question and Yes starts the matcher's first.
struct TrainQuestion: Equatable {
    /// "On the train to Clarkson?".
    let title: String
    /// The train Yes starts: the matcher's first candidate.
    let train: TrainCandidate
}

extension TrainQuestion {
    /// Nil for a question with no train.
    init?(_ question: TrainMatcher.Question) {
        guard let train = question.trains.first, let stop = train.plan.stops.last else { return nil }
        title = String(format: String(localized: "detect.question"), Self.shortName(stop.station.name))
        self.train = train
    }

    /// "Union", "Clarkson": the station's name without " GO" and " Station", as the live surfaces say it.
    static func shortName(_ name: String) -> String {
        let short = RideDetails.shortName(name)
        return short.hasSuffix(" Station") ? String(short.dropLast(8)) : short
    }
}

/// The question card under the day strip (`.sug`): the rippling dot and the question, Yes and No. Nothing starts until the
/// rider taps one.
struct TrainQuestionCard: View {
    let question: TrainQuestion
    var onYes: (TrainCandidate) -> Void = { _ in }
    var onNo: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: TTSpace.s3) {
            HStack(spacing: 10) {
                LiveDot()
                Text(verbatim: question.title)
                    .font(TTFont.question)
                    .tracking(-0.5)
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(2)
            }
            HStack(spacing: 10) {
                Button { onYes(question.train) } label: {
                    Text("detect.yes").frame(maxWidth: .infinity)
                }
                .buttonStyle(QuestionButtonStyle(isPrimary: true))
                .accessibilityIdentifier("schedule.question.yes")
                Button(action: onNo) {
                    Text("detect.no").frame(width: Self.noWidth)
                }
                .buttonStyle(QuestionButtonStyle(isPrimary: false))
                .accessibilityIdentifier("schedule.question.no")
            }
        }
        .padding(EdgeInsets(top: 14, leading: TTSpace.s4, bottom: 14, trailing: TTSpace.s4))
        .ttSheetCard(cornerRadius: TTRadius.question)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule.question")
    }

    /// The canvas's 88 pt No, less the style's padding.
    private static let noWidth: CGFloat = 88 - 2 * TTSpace.s4
}

/// The question's buttons, 44 pt (`.sug .acts .btn`): Yes filled in the accent, No outlined in ink.
private struct QuestionButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TTFont.headline)
            .tracking(-0.4)
            .foregroundStyle(isPrimary ? TTColor.onAccent : TTColor.ink)
            .lineLimit(1)
            .padding(.horizontal, TTSpace.s4)
            .frame(height: TTSize.targetMin)
            .background {
                if isPrimary {
                    Capsule().fill(configuration.isPressed ? TTColor.accentPressed : TTColor.accent)
                } else {
                    Capsule().strokeBorder(TTColor.controlBorder, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            .pressScale(configuration.isPressed)
    }
}
