import SnapshotTesting
import UIKit

extension ViewImageConfig {
    /// The one device every snapshot targets (Grigor, 2026-11-07): iPhone 17 Pro, portrait, 402 × 874 pt at 3x.
    @MainActor static var iPhone17Pro: ViewImageConfig {
        ViewImageConfig(
            safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
            size: CGSize(width: 402, height: 874),
            traits: UITraitCollection { traits in
                traits.displayScale = 3
                traits.userInterfaceIdiom = .phone
                traits.horizontalSizeClass = .compact
                traits.verticalSizeClass = .regular
            }
        )
    }
}
