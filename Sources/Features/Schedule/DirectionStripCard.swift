import SwiftUI

/// Automatic direction's one-time strip (TT-236, D116; board 15 of the Route and stations canvas, `.adfirst`), under the day
/// strip in the ride strip's slot until it is answered: the location arrow and "Automatic direction is on", the line that
/// says what it does and that Settings turns it off, then OK, which fills the width, and Turn off, as wide as its words.
/// The train question's metrics (22 pt corners, 20 pt bold title, 44 pt buttons, 14/16 padding), not its card: that one
/// has no body line, fixed ids and a fixed 88 pt No.
struct DirectionStripCard: View {
    var onOK: () -> Void = {}
    var onTurnOff: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TTColor.accent)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text("direction.strip.title")
                    .font(TTFont.question)
                    .tracking(-0.5)
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .accessibilityAddTraits(.isHeader)
            }
            Text("direction.strip.body")
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
                .accessibilityIdentifier("direction.strip.ok")
                Button(action: onTurnOff) {
                    // The canvas's 20 pt each side, less the style's 16.
                    Text("direction.strip.off").padding(.horizontal, TTSpace.s5 - TTSpace.s4)
                }
                .buttonStyle(QuestionButtonStyle(isPrimary: false))
                .fixedSize()
                .accessibilityIdentifier("direction.strip.off")
            }
            .padding(.top, TTSpace.s3)
        }
        .padding(EdgeInsets(top: 14, leading: TTSpace.s4, bottom: 14, trailing: TTSpace.s4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .ttSheetCard(cornerRadius: TTRadius.question)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("direction.strip")
    }
}
