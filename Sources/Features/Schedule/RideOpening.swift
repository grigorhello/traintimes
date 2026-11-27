import SwiftUI

/// The ride opens by itself (TT-256, D130, Card states board 13): with a ride running, each time the app opens or comes back
/// from the background, ride mode opens over Schedule, as long as Schedule's tab is in front with nothing over it, also after
/// the rider closed it. One per app in `RootView`, which says when the app arrived (`arrived()`) and asks once the ride and
/// the launch splash allow (`decide(rideRuns:inFront:)`); Schedule reports what of its own is up (`scheduleBusy`) and its
/// touches (`touched()`), so the sheet never comes up under a finger or over the station picker. Revises D120, whose ride
/// that started by itself opened once only.
@MainActor
final class RideOpening {
    /// A beat after the app comes to the front before the sheet opens, so it rises over Schedule rather than with the
    /// app's own arrival.
    static let beat: Duration = .milliseconds(300)
    /// How long an arrival waits for a ride restored at launch to be back, after the launch splash has lifted. A ride
    /// still not back by then is not opened: a sheet that came up later would come up mid-reading.
    static let rideWait: Duration = .seconds(3)

    /// Something of Schedule's own is up: the station picker, the weather sheet or the Feedback sheet.
    var scheduleBusy = false
    /// An arrival waits to be decided.
    private(set) var isWaiting = false
    /// Schedule was touched since the arrival.
    private var wasTouched = false

    /// The app opened, or came back from the background: the next `decide(rideRuns:inFront:)` says whether the ride opens.
    func arrived() {
        isWaiting = true
        wasTouched = false
    }

    /// A touch on Schedule (a tap or a drag) while an arrival waits: the rider is reading, so the ride stays closed.
    func touched() {
        if isWaiting { wasTouched = true }
    }

    /// Ends the wait: true when the ride opens. `rideRuns`: a ride runs, started and not ended. `inFront`: Schedule's tab is
    /// in front with no sheet of the app's over it, the launch splash has lifted and a route is saved.
    func decide(rideRuns: Bool, inFront: Bool) -> Bool {
        guard isWaiting else { return false }
        isWaiting = false
        return rideRuns && inFront && !scheduleBusy && !wasTouched
    }
}

extension EnvironmentValues {
    /// The ride opening by itself (TT-256, D130), from `RootView`: Schedule reports to it. Nil in previews and snapshots of
    /// Schedule alone.
    @Entry var rideOpening: RideOpening? = nil
}
