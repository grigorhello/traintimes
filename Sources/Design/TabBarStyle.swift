import SwiftUI
import UIKit

/// The tab bar (D49, reversing D25). iOS 26 and later draw the floating Liquid Glass bar themselves, so the app only gives
/// it icons: `tram.fill`, `bell.fill` and `gearshape.fill`, no titles, accent for the selected tab. Earlier systems keep the
/// classic bar from design/frames/schedule-timeline.png: surface background, hairline top edge, accent for the selected tab.
enum TabBarStyle {
    @MainActor
    static func apply() {
        if #available(iOS 26, *) { return }
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(named: "Surface")
        appearance.shadowColor = UIColor(named: "Hairline")
        // 1 pt line as in the frame; UIKit's default shadow is one device pixel. The template image takes shadowColor.
        appearance.shadowImage = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: .preferred())
            .image { $0.fill(CGRect(x: 0, y: 0, width: 1, height: 1)) }
            .withRenderingMode(.alwaysTemplate)
        let normal = UIColor(named: "InkSecondary") ?? .secondaryLabel
        let selected = UIColor(named: "Accent") ?? .tintColor
        for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            item.normal.iconColor = normal
            item.normal.titleTextAttributes = [.foregroundColor: normal]
            item.selected.iconColor = selected
            item.selected.titleTextAttributes = [.foregroundColor: selected]
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    /// The dot at a tab icon's top trailing corner: accent says something new (TT-143), red says notifications are off
    /// while an alert is switched on (TT-169, bigger, in the cancel ink).
    enum Dot: Hashable {
        case accent, warning

        fileprivate var diameter: CGFloat { self == .warning ? 9 : 7 }
        fileprivate var ring: CGFloat { self == .warning ? 2 : 1.5 }
        fileprivate var colorName: String { self == .warning ? "CancelInk" : "Accent" }
    }

    /// A tab icon drawn in the token colours, with no title. It is a plain image rather than a symbol, so the tab bar
    /// cannot restyle it: the Alerts dot keeps its own colour (the system draws `bell.badge` red) and never shows a number,
    /// and the tab icons keep one size whether or not the dot is on. The dot is cut out of the glyph, so the bar shows
    /// through whatever it is made of. `label` is the name VoiceOver reads.
    @MainActor
    static func icon(
        _ systemName: String, label: String, isSelected: Bool, dot: Dot? = nil, colorScheme: ColorScheme
    ) -> Image {
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        func color(_ name: String) -> UIColor { (UIColor(named: name) ?? .label).resolvedColor(with: traits) }
        let configuration = UIImage.SymbolConfiguration(pointSize: iconPointSize, weight: .medium)
        guard let symbol = UIImage(systemName: systemName, withConfiguration: configuration) else {
            return Image(systemName: systemName)
        }
        let glyph = symbol.withTintColor(color(isSelected ? "Accent" : idleColorName), renderingMode: .alwaysOriginal)
        let image = UIGraphicsImageRenderer(size: symbol.size, format: .preferred()).image { _ in
            glyph.draw(at: .zero)
            guard let dot else { return }
            // The dot at the top trailing corner, with a clear ring cut out of the glyph around it.
            let size = dot.diameter + dot.ring * 2
            let ring = CGRect(x: symbol.size.width - size, y: 0, width: size, height: size)
            UIBezierPath(ovalIn: ring).fill(with: .clear, alpha: 1)
            color(dot.colorName).setFill()
            UIBezierPath(ovalIn: ring.insetBy(dx: dot.ring, dy: dot.ring)).fill()
        }
        let original = image.withRenderingMode(.alwaysOriginal)
        original.accessibilityLabel = label
        return Image(uiImage: original).renderingMode(.original)
    }

    /// Idle glyphs: ink on the glass bar, ink-secondary on the classic one.
    private static var idleColorName: String {
        if #available(iOS 26, *) { return "Ink" }
        return "InkSecondary"
    }

    private static let iconPointSize: CGFloat = 24   // glyphs about 27 pt wide, as in the frame
}
