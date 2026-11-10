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
/// Accent glyph unless `tint` says otherwise (the Trip details close button is ink); dimmed when disabled.
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

extension EnvironmentValues {
    /// Off in the Trip details snapshot tests: dark Liquid Glass is drawn differently from one run to the next (the glass
    /// adapts to what is behind it, 5% of the image in one run), so the snapshots draw the fallback surface instead.
    @Entry var rendersGlass: Bool = true
}

/// `ttGlass`: the glass, or its solid fallback before iOS 26 and when `rendersGlass` is off.
private struct GlassBackground<S: Shape>: ViewModifier {
    @Environment(\.rendersGlass) private var rendersGlass
    let tint: Color?
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26, *), rendersGlass {
            content.glassEffect(glass, in: shape)
        } else {
            content.background(tint ?? TTColor.surfaceRaised, in: shape)
        }
    }

    @available(iOS 26, *)
    private var glass: Glass {
        if let tint { Glass.regular.tint(tint).interactive() } else { Glass.regular.interactive() }
    }
}

extension View {
    /// Liquid Glass in `shape` on iOS 26 and later; a raised surface on earlier systems (D49). Only for controls that
    /// float over content: cards and tiles stay solid.
    func ttGlass(in shape: some Shape) -> some View {
        modifier(GlassBackground(tint: nil, shape: shape))
    }

    /// The same glass tinted with `tint` (TT-163: the floating alert button); the solid tint colour before iOS 26.
    func ttGlass(tint: Color, in shape: some Shape) -> some View {
        modifier(GlassBackground(tint: tint, shape: shape))
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
