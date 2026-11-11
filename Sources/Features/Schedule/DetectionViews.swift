import SwiftUI

/// Train detection's checking strip on Schedule (TT-175, *Live-Detect*): "Moving along Lakeshore West" with the grey dot,
/// then "Matching your train…" and where from, or "Looks like the 5:13 PM train" and how many of the two stops it shared.
/// Every time is formatted by the one formatter (D17).
struct DetectionStrip: Equatable {
    let title: String
    let detail: String
    let trailing: String
}

extension DetectionStrip {
    /// Nil when the line has no name to show.
    init?(_ progress: TrainMatcher.Progress, formatter: some TimeFormatting) {
        guard let line = progress.line else { return nil }
        title = String(format: String(localized: "detect.checking"), line.name)
        if let train = progress.train, progress.stops > 0 {
            detail = String(format: String(localized: "detect.looksLike"), formatter.time(train.departure))
            trailing = String(format: String(localized: "detect.stops"), min(progress.stops, 2))
        } else {
            detail = String(localized: "detect.matching")
            trailing = progress.since.map { String(format: String(localized: "detect.since"), TrainQuestion.shortName($0.name)) } ?? ""
        }
    }
}

/// Train detection's question (TT-175, *Live-Detect*): "On the 5:13 PM train?", why the app thinks so, and the answers:
/// "Yes, on board" for one train, each train's time when the timetable cannot tell two apart, and No.
struct TrainQuestion: Equatable {
    struct Answer: Equatable, Identifiable {
        let train: TrainCandidate
        /// "Yes, on board", or the train's time.
        let label: String
        var id: TripKey { train.trip }
    }

    let title: String
    /// "Your phone has moved with it since Union Station and stopped with it at Exhibition and Mimico."
    let why: String
    /// The station names in `why` drawn in ink, semibold: the stops it shared.
    let emphasized: [String]
    let answers: [Answer]
}

extension TrainQuestion {
    init(_ question: TrainMatcher.Question, formatter: some TimeFormatting) {
        let times: [String] = question.trains.map { formatter.time($0.departure) }
        var named = times.first ?? ""
        if times.count >= 2 {
            named = String(format: String(localized: "detect.either"), times[0], times[1])
        }
        title = String(format: String(localized: "detect.question"), named)
        let origin: String = question.since?.name ?? question.trains.first?.plan.stops.first?.station.name ?? ""
        let since = Self.shortName(origin)
        let stops: [String] = question.stops.map { Self.shortName($0.name) }
        if stops.count >= 2 {
            why = String(format: String(localized: "detect.why"), since, stops[0], stops[1])
        } else {
            why = String(format: String(localized: "detect.whyOne"), since, stops.first ?? since)
        }
        emphasized = Array(stops.prefix(2))
        if question.trains.count == 1 {
            answers = [Answer(train: question.trains[0], label: String(localized: "detect.yes"))]
        } else {
            answers = zip(question.trains, times).map { pair in Answer(train: pair.0, label: pair.1) }
        }
    }

    /// "Union", "Mimico": the station's name without " GO" and " Station", as the canvas words the strip and the question.
    static func shortName(_ name: String) -> String {
        let short = RideDetails.shortName(name)
        return short.hasSuffix(" Station") ? String(short.dropLast(8)) : short
    }
}

/// The checking strip: the ride strip's shape on a plain surface, not tappable (`.ride-strip.checking`).
struct DetectionStripView: View {
    let strip: DetectionStrip

    var body: some View {
        HStack(spacing: TTSpace.s3) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    LiveDot(isLive: false, isChecking: true)
                    Text(verbatim: strip.title)
                        .font(TTFont.badge)
                        .tracking(-0.1)
                        .foregroundStyle(TTColor.inkSecondary)
                }
                Text(verbatim: strip.detail)
                    .font(TTFont.headline)
                    .tracking(-0.4)
                    .foregroundStyle(TTColor.ink)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            Text(verbatim: strip.trailing)
                .font(TTFont.footnote)
                .tracking(-0.1)
                .foregroundStyle(TTColor.inkSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .monospacedDigit()
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 12))
        .ttSheetCard(cornerRadius: TTRadius.lg)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("schedule.detect")
    }
}

/// The question card under the day strip (`.sug`): the rippling dot and the question, the why line with the shared stops
/// in ink, and the answers. Nothing starts until the rider taps one.
struct TrainQuestionCard: View {
    let question: TrainQuestion
    var onYes: (TrainCandidate) -> Void = { _ in }
    var onNo: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: TTSpace.s2) {
            HStack(spacing: 10) {
                LiveDot()
                Text(verbatim: question.title)
                    .font(TTFont.question)
                    .tracking(-0.5)
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(2)
            }
            Text(why)
                .font(TTFont.subhead)
                .tracking(-0.2)
                .foregroundStyle(TTColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                ForEach(Array(question.answers.enumerated()), id: \.element.id) { index, answer in
                    Button { onYes(answer.train) } label: {
                        Text(verbatim: answer.label).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(QuestionButtonStyle(isPrimary: true))
                    .accessibilityIdentifier(index == 0 ? "schedule.question.yes" : "schedule.question.yes2")
                }
                Button(action: onNo) {
                    Text("detect.no").frame(width: Self.noWidth)
                }
                .buttonStyle(QuestionButtonStyle(isPrimary: false))
                .accessibilityIdentifier("schedule.question.no")
            }
            .monospacedDigit()
            .padding(.top, TTSpace.s1)
        }
        .padding(EdgeInsets(top: 14, leading: TTSpace.s4, bottom: 14, trailing: TTSpace.s4))
        .ttSheetCard(cornerRadius: TTRadius.question)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule.question")
    }

    /// The canvas's 88 pt No, less the style's padding.
    private static let noWidth: CGFloat = 88 - 2 * TTSpace.s4

    /// The why line with the shared stops semibold in ink.
    private var why: AttributedString {
        var text = AttributedString(question.why)
        var searchEnd = text.endIndex
        for name in question.emphasized.reversed() {
            guard let range = text[text.startIndex..<searchEnd].range(of: name, options: .backwards) else { continue }
            text[range].font = TTFont.subhead.weight(.semibold)
            text[range].foregroundColor = TTColor.ink
            searchEnd = range.lowerBound
        }
        return text
    }
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
