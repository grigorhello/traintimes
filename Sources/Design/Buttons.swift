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

/// "Show trains" on the route form (TT-161, D53): a tinted Liquid Glass capsule on iOS 26 and later, the filled pill before
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
    /// The surface of the station picker's suggestions (TT-161, D54): the route card's own surface continued below it, flat
    /// at the top where it meets the card and rounded at the bottom. One soft shadow wraps the card and the panel together
    /// (`StackShadow`). The content is clipped to the same shape first, so rows keep the rounded corners.
    func ttAttachedPanel(cornerRadius: CGFloat) -> some View {
        modifier(AttachedPanelSurface(cornerRadius: cornerRadius))
    }
}

private struct AttachedPanelSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: cornerRadius, bottomTrailingRadius: cornerRadius, topTrailingRadius: 0
        )
        content
            .clipShape(shape)
            .background(TTColor.surface, in: shape)
            .background { StackShadow(cornerRadius: cornerRadius) }
    }
}

/// The shadow of the whole stack, the route card above and the panel below it: canvas `0 16 22`, the ink at 14 % in light
/// and black at 55 % in dark. The card is drawn under the panel's layer, so the shadow is cast by the stack's outline and
/// then cut away inside it (an even-odd mask), leaving only what falls outside the card and the panel.
private struct StackShadow: View {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    /// How far the card reaches above the panel's top edge: two 48 pt rows, less the 1 pt the panel overlaps the card by.
    private static let cardReach = 2 * RouteCard.rowHeight - 1
    /// The mask is this much larger than the panel on every side, which is room for the blur and the 16 pt drop.
    private static let margin: CGFloat = 96

    var body: some View {
        let colour = colorScheme == .dark ? Color.black.opacity(0.55) : TTColor.ink.opacity(0.14)
        // Half a point inside the cut-out, so the antialiased edge of the fill never shows outside the stack.
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.black)
            .padding(EdgeInsets(top: -Self.cardReach + 0.5, leading: 0.5, bottom: 0.5, trailing: 0.5))
            .shadow(color: colour, radius: 22, x: 0, y: 16)
            .mask {
                Outside(cornerRadius: cornerRadius, reach: Self.cardReach, margin: Self.margin)
                    .fill(.black, style: FillStyle(eoFill: true))
                    .padding(-Self.margin)
            }
            .allowsHitTesting(false)
    }

    /// Everything inside the rectangle `margin` past the panel on every side, except the stack's outline (the panel plus the
    /// card above it, `reach` tall, with one point more of room along the top).
    private struct Outside: Shape {
        let cornerRadius: CGFloat
        let reach: CGFloat
        let margin: CGFloat

        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.addRect(rect)
            let stack = CGRect(
                x: rect.minX + margin, y: rect.minY + margin - reach - 1,
                width: rect.width - 2 * margin, height: rect.height - 2 * margin + reach + 1
            )
            path.addPath(Path(roundedRect: stack, cornerRadius: cornerRadius, style: .continuous))
            return path
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
