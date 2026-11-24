import SwiftUI

/// The departure question's card under the day strip (TT-231, D110; `.sug`): the rippling dot and "On the train to
/// Clarkson?", asked by the rider's stop about the alerted train that has just left, Yes and No. Nothing starts until the
/// rider taps one. Train detection's question that shared it went with the any-train check (TT-243, D120).
struct TrainQuestionCard: View {
    /// "On the train to Clarkson?".
    let title: String
    var onYes: () -> Void = {}
    var onNo: () -> Void = {}

    init(departure ask: DepartureAsk, onYes: @escaping () -> Void, onNo: @escaping () -> Void) {
        self.init(title: Self.title(stop: ask.route.to.name), onYes: onYes, onNo: onNo)
    }

    init(title: String, onYes: @escaping () -> Void = {}, onNo: @escaping () -> Void = {}) {
        self.title = title
        self.onYes = onYes
        self.onNo = onNo
    }

    /// "On the train to Clarkson?" for the rider's stop.
    static func title(stop name: String) -> String {
        String(format: String(localized: "detect.question"), shortName(name))
    }

    /// "Union", "Clarkson": the station's name without " GO" and " Station", as the live surfaces say it.
    static func shortName(_ name: String) -> String {
        let short = RideDetails.shortName(name)
        return short.hasSuffix(" Station") ? String(short.dropLast(8)) : short
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TTSpace.s3) {
            HStack(spacing: 10) {
                LiveDot()
                Text(verbatim: title)
                    .font(TTFont.question)
                    .tracking(-0.5)
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(2)
            }
            HStack(spacing: 10) {
                Button(action: onYes) {
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

/// The question's buttons, 44 pt (`.sug .acts .btn`): Yes filled in the accent, No outlined in ink. The one-time strips use
/// them too (TT-236, TT-243).
struct QuestionButtonStyle: ButtonStyle {
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
