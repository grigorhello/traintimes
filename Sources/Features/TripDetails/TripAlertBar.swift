import SwiftUI

/// Trip details' alert bar (TT-192, D77; the canvas's *Alert-Trip*): "Alert me", a 52 pt tinted-glass capsule with the bell
/// before the word, for a train with no alert. One tap turns the alert on in place: the bell pops and the word becomes
/// "Alert on" while it saves; then the alert card arrives on top of the sheet and the bar goes (TT-254, D129: the days and
/// Remove live in the card, so the bar has no Repeat any more).
struct TripAlertBar: View {
    let face: BellFace
    let shakes: Int
    let onAlert: () -> Void

    static let height: CGFloat = 52

    private var isOn: Bool { face == .on || face == .waiting }

    var body: some View {
        Button(action: onAlert) {
            HStack(spacing: TTSpace.s2) {
                // The card's bell and its pop, in white (D62, D72); the bar takes the tap.
                AlertBellButton(
                    face: face, shakes: shakes, label: Text(verbatim: ""), glyph: 20, target: 22, weight: .semibold,
                    tint: TTColor.onAccent
                ) {}
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                ZStack(alignment: .leading) {
                    // The words trade places: the old one leaves in 70 ms, the new one arrives over 120 ms from 80 ms.
                    Text("button.alert_me")
                        .animation(isOn ? Self.leave : Self.arrive) { $0.opacity(isOn ? 0 : 1) }
                    Text("button.alert_on")
                        .animation(isOn ? Self.arrive : Self.leave) { $0.opacity(isOn ? 1 : 0) }
                }
                .font(TTFont.headline)
                .tracking(-0.4)
                .lineLimit(1)
                .fixedSize()
            }
            .foregroundStyle(TTColor.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .ttGlass(tint: TTColor.accent, in: Capsule())
            .contentShape(Capsule())
        }
        // Warms the haptic engine on touch-down, so Rail joint's first beat is not late (TT-214).
        .buttonStyle(WarmsHapticsPressStyle())
        .frame(height: Self.height)
        .accessibilityLabel(Text(isOn ? "button.alert_on" : "button.alert_me"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("trip.alert")
    }

    private static let leave = Animation.easeIn(duration: 0.07)
    private static let arrive = Animation.easeOut(duration: 0.12).delay(0.08)
}
