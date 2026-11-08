import SwiftUI
import UIKit

/// Tab bar look from design/frames/schedule-timeline.png: surface background, hairline top edge,
/// accent for the selected tab, ink-secondary for the others. Needs the classic bars (D25).
enum TabBarStyle {
    @MainActor
    static func apply() {
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

    /// A tab icon drawn in the token colours. It is a plain image rather than a symbol, so the tab bar
    /// cannot restyle it: the Alerts dot stays accent (the system draws `bell.badge` red) and never shows a number,
    /// and the tab icons keep one size whether or not the dot is on.
    @MainActor
    static func icon(_ systemName: String, isSelected: Bool, showsDot: Bool = false, colorScheme: ColorScheme) -> Image {
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        func color(_ name: String) -> UIColor { (UIColor(named: name) ?? .label).resolvedColor(with: traits) }
        let configuration = UIImage.SymbolConfiguration(pointSize: iconPointSize, weight: .medium)
        guard let symbol = UIImage(systemName: systemName, withConfiguration: configuration) else {
            return Image(systemName: systemName)
        }
        let glyph = symbol.withTintColor(color(isSelected ? "Accent" : "InkSecondary"), renderingMode: .alwaysOriginal)
        let image = UIGraphicsImageRenderer(size: symbol.size, format: .preferred()).image { _ in
            glyph.draw(at: .zero)
            guard showsDot else { return }
            // Accent dot at the top trailing corner, cut out of the glyph by a ring in the tab bar colour.
            let ring = CGRect(x: symbol.size.width - dotDiameter - 3, y: 0, width: dotDiameter + 3, height: dotDiameter + 3)
            color("Surface").setFill()
            UIBezierPath(ovalIn: ring).fill()
            color("Accent").setFill()
            UIBezierPath(ovalIn: ring.insetBy(dx: 1.5, dy: 1.5)).fill()
        }
        return Image(uiImage: image.withRenderingMode(.alwaysOriginal)).renderingMode(.original)
    }

    private static let iconPointSize: CGFloat = 17   // glyphs about 17 pt, as in the frame
    private static let dotDiameter: CGFloat = 7
}
