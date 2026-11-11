import CoreLocation

/// The phone's location for a ride (TT-171). The location manager is made on first use, so nothing touches location
/// before a ride: When In Use is asked only by `RideEngine.start`. During a ride, `CLLocationUpdate.liveUpdates` gives
/// about one fix a second, and a `CLBackgroundActivitySession`, created while the app is in front, keeps them coming in
/// the background (the blue mark); iOS relaunches the app to continue if it stops it, and `RideEngine.restore` creates
/// both again at launch. Fixes stay on the phone.
@MainActor
final class SystemLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private var session: CLBackgroundActivitySession?
    private var updates: Task<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var isAuthorized: Bool {
        Self.allows(locationManager().authorizationStatus)
    }

    func requestWhenInUse() async -> Bool {
        let manager = locationManager()
        guard manager.authorizationStatus == .notDetermined else { return isAuthorized }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
        return isAuthorized
    }

    func startUpdates(_ onFix: @escaping @MainActor @Sendable (LocationFix) -> Void) {
        stopUpdates()
        session = CLBackgroundActivitySession()
        // Read off the main actor; each fix is copied into a `LocationFix` before it goes back to the ride.
        updates = Task.detached {
            do {
                for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                    guard let location = update.location else { continue }
                    let fix = LocationFix(
                        coordinate: GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                        horizontalAccuracy: location.horizontalAccuracy,
                        isStationary: update.isStationary
                    )
                    await onFix(fix)
                }
            } catch {
                // The updates stopped (the ride ended or location was turned off): the ride falls back to the timetable.
            }
        }
    }

    func stopUpdates() {
        updates?.cancel()
        updates = nil
        session?.invalidate()
        session = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorizationChanged(to: status) }
    }

    private func authorizationChanged(to status: CLAuthorizationStatus) {
        // The delegate also hears the current status when it is set; only an answer ends the wait.
        guard status != .notDetermined else { return }
        let waiting = waiters
        waiters = []
        for waiter in waiting { waiter.resume() }
    }

    private func locationManager() -> CLLocationManager {
        if let manager { return manager }
        let manager = CLLocationManager()
        manager.delegate = self
        self.manager = manager
        return manager
    }

    private static func allows(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }
}
