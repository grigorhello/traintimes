import SwiftUI
import UIKit

/// Tab bar look from design/frames/schedule-timeline.png: surface background, hairline top edge,
/// accent for the selected tab, ink-secondary for the others. The Alerts icon can carry an accent dot, never a number.
enum TabBarStyle {
    @MainActor
    static func apply() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(named: "Surface")
        appearance.shadowColor = UIColor(named: "Hairline")
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

    static var scheduleIcon: Image { Image(systemName: "text.alignleft") }

    static func alertsIcon(showsDot: Bool, isSelected: Bool) -> Image {
        guard showsDot,
              let accent = UIColor(named: "Accent"),
              let bell = UIColor(named: isSelected ? "Accent" : "InkSecondary"),
              let image = UIImage(systemName: "bell.badge", withConfiguration: UIImage.SymbolConfiguration(paletteColors: [accent, bell]))
        else { return Image(systemName: "bell") }
        return Image(uiImage: image.withRenderingMode(.alwaysOriginal))
    }
}
