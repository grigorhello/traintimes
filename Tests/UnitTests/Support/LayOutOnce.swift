import SnapshotTesting
import SwiftUI
import UIKit

/// Lays `view` out once in an iPhone 17 Pro sized window and lets the main run loop turn, so what the view reports back to
/// its view model (the timeline cards' measured sizes, TT-113) is already in the layout when a snapshot draws it.
@MainActor
func layOutOnce(_ view: some View) {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
    window.frame = CGRect(origin: .zero, size: ViewImageConfig.iPhone17Pro.size ?? .zero)
    window.rootViewController = UIHostingController(rootView: view)
    window.isHidden = false
    window.layoutIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
    window.isHidden = true
}
