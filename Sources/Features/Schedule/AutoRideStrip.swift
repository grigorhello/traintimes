import SwiftUI

/// The automatic ride's one-time strip (TT-243, D120): "Rides start by themselves", due at the first ride that started by
/// itself (the demo's too, so it can be checked at a desk), shown on Schedule in the ride strip's slot once that ride is over
/// (`RideStripContent` puts riding and the departure question first), while Automatic ride reads on, until answered. OK
/// closes it for good; Turn off stores the "off" and sends `setting_changed` `auto_ride` `off`. Both play `undo`, as D116's
/// strip does. One per app, made by `RootView`.
@Observable @MainActor
final class AutoRideStrip {
    private let store: AutoRideStore?
    private let readsOn: @MainActor () -> Bool
    private let haptics: any HapticPlaying
    /// Bumped on every change, so the strip is drawn again: the store itself is not observed.
    private var version = 0
    /// Answered in this run: closed at once, whatever the store reads back (a UI test's launch arguments keep the stored
    /// answer cleared for the whole run).
    private var answered = false

    /// `store` nil (previews, the unit test host's screens) never shows it. `readsOn`: Automatic ride reads on.
    init(store: AutoRideStore?, readsOn: @escaping @MainActor () -> Bool, haptics: any HapticPlaying = TTHaptics.shared) {
        self.store = store
        self.readsOn = readsOn
        self.haptics = haptics
    }

    /// Due and not answered, while Automatic ride reads on. Riding comes first in the slot.
    var isShown: Bool {
        _ = version
        guard let store, !answered else { return false }
        return store.stripDue && !store.stripAnswered && readsOn()
    }

    /// OK: closed for good.
    func ok() {
        haptics.play(.undo)
        answered = true
        store?.stripAnswered = true
        version += 1
    }

    /// Turn off: Automatic ride off, as the Settings switch turns it off.
    func turnOff() {
        haptics.play(.undo)
        answered = true
        store?.stripAnswered = true
        if store?.isOff == false {
            store?.isOff = true
            Analytics.track(.settingChanged("auto_ride", value: "off"))
        }
        version += 1
    }

    /// The store or the setting may have changed elsewhere (a ride started by itself, Settings): looked at again.
    func refresh() {
        version += 1
    }
}

extension EnvironmentValues {
    /// The automatic ride's one-time strip (TT-243, D120), from `RootView`; nil in previews and snapshots of Schedule alone.
    @Entry var autoRideStrip: AutoRideStrip? = nil
}
