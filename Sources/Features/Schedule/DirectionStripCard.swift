import SwiftUI

/// A one-time strip under the day strip, in the ride strip's slot until it is answered: a glyph in the accent and a title,
/// the line that says what it does and that Settings turns it off, then OK, which fills the width, and Turn off, as wide as
/// its words. Automatic direction's (TT-236, D116; board 15 of the Route and stations canvas, `.adfirst`): the location
/// arrow and "Automatic direction is on". The automatic ride's (TT-243, D120): the train glyph and "Rides start by
/// themselves" (`autoRide(onOK:onTurnOff:)`). The train question's metrics (22 pt corners, 20 pt bold title, 44 pt buttons,
/// 14/16 padding), not its card: that one has no body line, fixed ids and a fixed 88 pt No.
struct DirectionStripCard: View {
    /// The glyph before the title.
    enum Glyph {
        case location
        case train
    }

    var glyph: Glyph = .location
    var title: LocalizedStringKey = "direction.strip.title"
    var line: LocalizedStringKey = "direction.strip.body"
    /// The card's identifier; its buttons are `<id>.ok` and `<id>.off`.
    var id = "direction.strip"
    var onOK: () -> Void = {}
    var onTurnOff: () -> Void = {}

    /// The automatic ride's strip (TT-243): once, after the first ride that started by itself.
    static func autoRide(onOK: @escaping () -> Void = {}, onTurnOff: @escaping () -> Void = {}) -> DirectionStripCard {
        DirectionStripCard(
            glyph: .train, title: "autoride.strip.title", line: "autoride.strip.body", id: "autoride.strip",
            onOK: onOK, onTurnOff: onTurnOff
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                glyphView
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text(title)
                    .font(TTFont.question)
                    .tracking(-0.5)
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(line)
                .font(TTFont.subhead)
                .tracking(-0.2)
                .foregroundStyle(TTColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            HStack(spacing: 10) {
                Button(action: onOK) {
                    Text("direction.strip.ok").frame(maxWidth: .infinity)
                }
                .buttonStyle(QuestionButtonStyle(isPrimary: true))
                .accessibilityIdentifier(id + ".ok")
                Button(action: onTurnOff) {
                    // The canvas's 20 pt each side, less the style's 16.
                    Text("direction.strip.off").padding(.horizontal, TTSpace.s5 - TTSpace.s4)
                }
                .buttonStyle(QuestionButtonStyle(isPrimary: false))
                .fixedSize()
                .accessibilityIdentifier(id + ".off")
            }
            .padding(.top, TTSpace.s3)
        }
        .padding(EdgeInsets(top: 14, leading: TTSpace.s4, bottom: 14, trailing: TTSpace.s4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .ttSheetCard(cornerRadius: TTRadius.question)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private var glyphView: some View {
        switch glyph {
        case .location:
            Image(systemName: "location.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(TTColor.accent)
        case .train:
            TrainGlyph()
                .fill(TTColor.accent, style: FillStyle(eoFill: true))
                .frame(width: 22, height: 22)
        }
    }
}
