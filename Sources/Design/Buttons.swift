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

/// "Show trains" on the route form (TT-161, D52): a tinted Liquid Glass capsule on iOS 26 and later, the filled pill before
/// it. Disabled is the same grey pill as `.ttPrimary`.
struct GlassPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: ButtonStyleConfiguration

        var body: some View {
            if #available(iOS 26, *), isEnabled {
                configuration.label
                    .font(TTFont.headline)
                    .foregroundStyle(TTColor.onAccent)
                    .padding(.horizontal, TTSpace.s5)
                    .frame(minHeight: TTSize.targetMin + TTSpace.s1)
                    .glassEffect(.regular.tint(TTColor.accent).interactive(), in: Capsule())
                    .contentShape(Capsule())
            } else {
                configuration.label
                    .font(TTFont.headline)
                    .foregroundStyle(isEnabled ? TTColor.onAccent : TTColor.inkSecondary)
                    .padding(.horizontal, TTSpace.s5)
                    .frame(minHeight: TTSize.targetMin + TTSpace.s1)
                    .background(
                        isEnabled ? (configuration.isPressed ? TTColor.accentPressed : TTColor.accent) : TTColor.surfaceRaised,
                        in: Capsule()
                    )
                    .pressScale(configuration.isPressed)
            }
        }
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
extension ButtonStyle where Self == GlassPrimaryButtonStyle { static var ttGlassPrimary: Self { .init() } }
extension ButtonStyle where Self == SecondaryButtonStyle { static var ttSecondary: Self { .init() } }
extension ButtonStyle where Self == TextButtonStyle { static var ttText: Self { .init() } }

/// 44 pt target, `TTSize.iconButtonGlyph` glyph in ink-secondary, as the canvas's `.icon-btn`. Filled glyphs (bell.fill,
/// star.fill) and `isSelected` use the accent; disabled is ink-tertiary.
struct IconButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let systemName: String
    let label: Text
    var isSelected = false
    let action: () -> Void

    init(systemName: String, label: LocalizedStringKey, isSelected: Bool = false, action: @escaping () -> Void) {
        self.init(systemName: systemName, label: Text(label), isSelected: isSelected, action: action)
    }

    /// A label formatted from `Localizable.strings`, such as "Alert for 7:32 AM train".
    init(systemName: String, label: Text, isSelected: Bool = false, action: @escaping () -> Void) {
        self.systemName = systemName
        self.label = label
        self.isSelected = isSelected
        self.action = action
    }

    /// The glyph and the tap target in points; the defaults are the canvas's `.icon-btn` (the timeline bell is 26 in 48, D49).
    private var glyph = TTSize.iconButtonGlyph
    private var target = TTSize.targetMin

    func sized(glyph: CGFloat, target: CGFloat) -> IconButton {
        var copy = self
        copy.glyph = glyph
        copy.target = target
        return copy
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: glyph))
                .foregroundStyle(!isEnabled ? TTColor.inkTertiary : systemName.hasSuffix(".fill") || isSelected ? TTColor.accent : TTColor.inkSecondary)
                .frame(width: target, height: target)
                .background(isSelected ? TTColor.surfaceRaised : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }
}

/// A round control floating over content, 44 pt (D49): Liquid Glass on iOS 26 and later, a raised surface before it.
/// Accent glyph (`tint`, ink for the picker's X); dimmed when disabled.
struct GlassIconButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let systemName: String
    let label: LocalizedStringKey
    var tint: Color = TTColor.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: TTSize.iconButtonGlyph, weight: .semibold))
                .foregroundStyle(isEnabled ? tint : TTColor.inkTertiary)
                .opacity(isEnabled ? 1 : 0.55)
                .frame(width: TTSize.targetMin, height: TTSize.targetMin)
                .ttGlass(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(Text(label))
    }
}

extension View {
    /// Liquid Glass in `shape` on iOS 26 and later; a raised surface on earlier systems (D49). Only for controls that
    /// float over content: cards and tiles stay solid.
    @ViewBuilder func ttGlass(in shape: some Shape) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(TTColor.surfaceRaised, in: shape)
        }
    }
}

extension View {
    /// The surface of the station picker's suggestions panel (TT-161, D52): Liquid Glass on iOS 26 and later, a material
    /// before it. The content is clipped to the same shape first, so rows and hairlines keep the rounded corners.
    @ViewBuilder func ttGlassPanel(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        if #available(iOS 26, *) {
            clipShape(shape).glassEffect(.regular, in: shape)
        } else {
            clipShape(shape).background(.regularMaterial, in: shape)
        }
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
