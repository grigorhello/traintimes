import CoreLocation

/// The phone's location for a ride (TT-171) and the automatic ride's watch (TT-242, D120). The location manager is made on
/// first use, and through this type When In Use is asked only by `RideEngine.start` and the Settings switches. During a
/// ride, `CLLocationUpdate.liveUpdates` gives about one fix a second, and a `CLBackgroundActivitySession`, created while
/// the app is in front, keeps them coming in the background (the blue mark); iOS relaunches the app to continue if it
/// stops it, and `RideEngine.restore` creates both again at launch.
///
/// Where location is used (D60 rule 4 as revised by D116 and D120): during a ride, by the automatic ride's watch around an
/// alerted train, and for one look when the app opens to set the route's direction. No reading is kept past its use and
/// none is uploaded. When In Use is asked when a ride starts, or when the rider turns on Automatic direction or Automatic
/// ride, never at launch. Automatic direction's look has its own reader, `SystemDirectionLocation`, which never asks by
/// itself.
@MainActor
final class SystemLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private var session: CLBackgroundActivitySession?
    private var updates: Task<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        super.init()
    }

    var isAuthorized: Bool {
        Self.allows(locationManager().authorizationStatus)
    }

    var canAsk: Bool {
        locationManager().authorizationStatus == .notDetermined
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

    var isPrecise: Bool {
        locationManager().accuracyAuthorization == .fullAccuracy
    }

    /// While updates run, `startUpdates(_:)` only swaps this: the automatic ride's watch hands its session over to the ride
    /// engine (TT-242, D120), and a session created again from the background would not start.
    private var onFix: (@MainActor @Sendable (LocationFix) -> Void)?
    /// Tells a finished updates task from the one that replaced it.
    private var generation = 0

    func startUpdates(_ onFix: @escaping @MainActor @Sendable (LocationFix) -> Void) {
        self.onFix = onFix
        guard updates == nil else { return }
        session = CLBackgroundActivitySession()
        spawnUpdates()
    }

    /// A new `liveUpdates` task under a new generation, with the same session and callback (TT-251, D127): the wrong train
    /// check's try at waking updates iOS paused for a phone it took to be at rest. Nothing while no updates run.
    func restartUpdates() {
        guard let running = updates else { return }
        running.cancel()
        spawnUpdates()
    }

    private func spawnUpdates() {
        generation += 1
        let generation = generation
        // Read off the main actor; each fix is copied into a `LocationFix` before it goes back to the ride.
        updates = Task.detached { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                    guard !Task.isCancelled else { break }
                    guard let location = update.location else { continue }
                    // `isStationary` (iOS 17) is deprecated in the SDK and warnings are errors, so iOS 17 reports no
                    // stationary fixes: a phone at rest there falls back to the timetable after 60 s.
                    let isStationary: Bool
                    if #available(iOS 18, *) { isStationary = update.stationary } else { isStationary = false }
                    let fix = LocationFix(
                        coordinate: GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                        horizontalAccuracy: location.horizontalAccuracy,
                        isStationary: isStationary,
                        age: max(0, Date().timeIntervalSince(location.timestamp))
                    )
                    await self?.deliver(fix, generation: generation)
                }
            } catch {
                // The updates stopped (the ride ended or location was turned off): the ride falls back to the timetable.
            }
            await self?.finished(generation)
        }
    }

    func stopUpdates() {
        updates?.cancel()
        updates = nil
        session?.invalidate()
        session = nil
        onFix = nil
    }

    /// Only the current task's fixes: one that was restarted may still hand over a fix it had read.
    private func deliver(_ fix: LocationFix, generation: Int) {
        guard generation == self.generation else { return }
        onFix?(fix)
    }

    /// The stream ended by itself (location turned off): the next start creates the session again.
    private func finished(_ ended: Int) {
        guard ended == generation, updates != nil else { return }
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
