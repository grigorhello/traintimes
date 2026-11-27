import SwiftUI

/// The wrong train warning in the app (TT-250, D127; the Live view canvas's boards 54 to 56): "Wrong train?" in the Delay
/// ink on the Delay fill, why in one line, X's next stop and its time, then "Trains from Oakville" and "I’m fine". On the
/// ride screen it stands in the hero's place at the ride's sizes (26 and 17 pt, D87); on Schedule in the strip's place at
/// the strips' (20 and 15 pt). Plain capsules: the sheet redraws each second.
struct WrongTrainCard: View {
    enum Size {
        /// The ride screen.
        case ride
        /// Schedule's strip.
        case strip
    }

    let display: WrongTrainDisplay
    var size: Size = .ride
    /// "trip.wrongTrain" or "schedule.wrongTrain"; the buttons add `.trains` and `.fine`.
    var id: String = "trip.wrongTrain"
    var onTrains: () -> Void = {}
    var onFine: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("wrong.title")
                .font(size == .ride ? TTFont.wrongTitle : TTFont.question)
                .tracking(size == .ride ? -0.6 : -0.45)
                .foregroundStyle(TTColor.delayInk)
                .lineLimit(1)
            Text(verbatim: display.reason)
                .font(size == .ride ? TTFont.headline : TTFont.badgeLarge)
                .tracking(size == .ride ? -0.4 : -0.2)
                .foregroundStyle(TTColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, size == .ride ? 6 : 4)
            next
                .font(size == .ride ? TTFont.body : TTFont.subhead)
                .tracking(size == .ride ? -0.4 : -0.2)
                .foregroundStyle(TTColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, size == .ride ? 2 : 0)
            HStack(spacing: 10) {
                Button(action: onTrains) {
                    Text(verbatim: display.trains)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WrongTrainButtonStyle(isPrimary: true))
                .accessibilityIdentifier("\(id).trains")
                Button(action: onFine) {
                    Text("wrong.fine").frame(width: Self.fineWidth)
                }
                .buttonStyle(WrongTrainButtonStyle(isPrimary: false))
                .accessibilityIdentifier("\(id).fine")
            }
            .padding(.top, 14)
        }
        .padding(size == .ride
            ? EdgeInsets(top: 16, leading: TTSpace.s5, bottom: 18, trailing: TTSpace.s5)
            : EdgeInsets(top: 14, leading: TTSpace.s4, bottom: TTSpace.s4, trailing: TTSpace.s4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: size == .ride ? TTRadius.xl : TTRadius.question, style: .continuous)
                .fill(TTColor.delayFill)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }

    /// "Next stop Oakville · 5:38 PM" with the station's name semibold.
    private var next: Text {
        var line = AttributedString(display.next)
        if let range = line.range(of: display.nextStop) {
            line[range].font = size == .ride ? TTFont.headline : TTFont.badgeLarge
        }
        return Text(line)
    }

    /// The boards' 104 pt "I’m fine", less the style's padding.
    private static let fineWidth: CGFloat = 104 - 2 * TTSpace.s4
}

/// The warning's buttons, 48 pt: "Trains from …" filled in the accent, "I’m fine" outlined in ink.
private struct WrongTrainButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TTFont.headline)
            .tracking(-0.4)
            .foregroundStyle(isPrimary ? TTColor.onAccent : TTColor.ink)
            .lineLimit(1)
            .padding(.horizontal, TTSpace.s4)
            .frame(height: 48)
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
