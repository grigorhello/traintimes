import SnapshotTesting
import SwiftUI
import UIKit

/// Snapshots that draw the floating Liquid Glass tab bar (D49) let 0.01% of pixels (about 310) differ: the bar's blur draws
/// about 80 pixels a shade (up to 3/255) differently from one run to the next. A card moved by even 1 px changes thousands.
let glassSnapshotPrecision: Float = 0.9999

/// Lays `view` out once in an iPhone 17 Pro sized window and lets the main run loop turn, so what the view reports back to
/// its view model (the timeline cards' measured sizes, TT-113) is already in the layout when a snapshot draws it.
@MainActor
func layOutOnce(_ view: some View) {
    // The glass bar and sheets animate in; a snapshot takes the settled look, so no UIKit animation runs in tests.
    UIView.setAnimationsEnabled(false)
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
    window.frame = CGRect(origin: .zero, size: ViewImageConfig.iPhone17Pro.size ?? .zero)
    window.rootViewController = UIHostingController(rootView: view)
    window.isHidden = false
    window.layoutIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
    window.isHidden = true
}
