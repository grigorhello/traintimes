import CoreLocation

/// Automatic direction's reader (TT-234, D116): its own `CLLocationManager` at hundred-metre accuracy, running
/// `startUpdatingLocation()` only while a look lasts (10 s at most, in the foreground). Not `requestLocation()`, which
/// answers once and late, and not the ride's or train detection's reader. It never asks by itself: the manager is made
/// on first use, and making one shows no prompt.
@MainActor
final class SystemDirectionLocation: NSObject, DirectionLocating, CLLocationManagerDelegate {
    private lazy var manager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        return manager
    }()
    private var onReading: (@MainActor (DirectionReading) -> Void)?
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    var permission: DirectionPermission {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: .allowed
        case .notDetermined: .notAsked
        default: .refused
        }
    }

    var isPrecise: Bool { manager.accuracyAuthorization == .fullAccuracy }

    func requestWhenInUse() async -> Bool {
        guard manager.authorizationStatus == .notDetermined else { return permission == .allowed }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    func start(_ onReading: @escaping @MainActor (DirectionReading) -> Void) {
        self.onReading = onReading
        manager.startUpdatingLocation()
    }

    func stop() {
        guard onReading != nil else { return }
        onReading = nil
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // A negative accuracy marks a reading that is not valid. The age is against the device clock, as the timestamp is.
        let now = Date()
        let readings = locations.filter { $0.horizontalAccuracy >= 0 }.map { location in
            DirectionReading(
                place: GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                radius: location.horizontalAccuracy, age: max(0, now.timeIntervalSince(location.timestamp))
            )
        }
        Task { @MainActor in
            for reading in readings { self.onReading?(reading) }
        }
    }

    /// Nothing to do: with no reading the look ends by itself after 10 s.
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.manager.authorizationStatus != .notDetermined else { return }
            let allowed = self.permission == .allowed
            let waiting = self.waiters
            self.waiters = []
            for waiter in waiting { waiter.resume(returning: allowed) }
        }
    }
}
