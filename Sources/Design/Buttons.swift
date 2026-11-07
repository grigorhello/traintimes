import SwiftUI

/// Filled pill, the one main action on a screen. Disabled shows a grey pill.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TTFont.headline)
            .foregroundStyle(isEnabled ? TTColor.onAccent : TTColor.inkSecondary)
            .padding(.horizontal, TTSpace.s5)
            .frame(minHeight: TTSize.targetMin + TTSpace.s1)
            .background(isEnabled ? (configuration.isPressed ? TTColor.accentPressed : TTColor.accent) : TTColor.surfaceRaised, in: Capsule())
            .pressScale(configuration.isPressed)
    }
}

/// Outlined pill.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TTFont.headline)
            .foregroundStyle(TTColor.accent)
            .padding(.horizontal, TTSpace.s5)
            .frame(minHeight: TTSize.targetMin + TTSpace.s1)
            .overlay(Capsule().strokeBorder(TTColor.controlBorder, lineWidth: 1))
            .contentShape(Capsule())
            .pressScale(configuration.isPressed)
    }
}

/// Accent text with a 44 pt target.
struct TextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TTFont.body)
            .foregroundStyle(TTColor.accent)
            .padding(.horizontal, TTSpace.s2)
            .frame(minHeight: TTSize.targetMin)
            .contentShape(Rectangle())
            .pressScale(configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle { static var ttPrimary: Self { .init() } }
extension ButtonStyle where Self == SecondaryButtonStyle { static var ttSecondary: Self { .init() } }
extension ButtonStyle where Self == TextButtonStyle { static var ttText: Self { .init() } }

/// 44 pt target, 22 pt glyph. Filled glyphs (bell.fill, star.fill) and `isSelected` use the accent; disabled is ink-tertiary.
struct IconButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let systemName: String
    let label: LocalizedStringKey
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: TTSize.iconMD))
                .foregroundStyle(!isEnabled ? TTColor.inkTertiary : systemName.hasSuffix(".fill") || isSelected ? TTColor.accent : TTColor.ink)
                .frame(width: TTSize.targetMin, height: TTSize.targetMin)
                .background(isSelected ? TTColor.surfaceRaised : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(Text(label))
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.pressScale(configuration.isPressed)
    }
}

extension View {
    /// Buttons scale to 0.97 on press, 0.2 s ease-out.
    func pressScale(_ isPressed: Bool) -> some View {
        scaleEffect(isPressed ? 0.97 : 1).animation(.easeOut(duration: 0.2), value: isPressed)
    }
}

#Preview("Buttons") { ButtonsGallery() }
#Preview("Buttons dark") { ButtonsGallery().preferredColorScheme(.dark) }
