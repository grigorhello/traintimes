import CoreLocation
import UIKit

/// "Detect my train"'s location in the app (TT-176): the Always permission and the significant-change wake-ups. The
/// location manager is made on first use; `BackgroundDetection.resume()` makes it at launch while the switch is on, which
/// is what lets a relaunch for a wake-up deliver it. On iOS 18 a `CLServiceSession` asking for Always is held while the
/// wake-ups run, as iOS 18 expects of an app that uses location in the background.
@MainActor
final class SystemWakeLocation: NSObject, WakeLocationProviding, CLLocationManagerDelegate {
    /// After the Always request, a dialog shows within this long or not at all (iOS shows it once).
    static let dialogWait: Duration = .seconds(1)

    private var manager: CLLocationManager?
    private var onWake: (@MainActor (WakeFix) async -> Void)?
    /// The iOS 18 `CLServiceSession`, kept as `Any` so iOS 17 builds.
    private var serviceSession: Any?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// The status when Always was asked for: the delegate also hears the current status when the manager is made, which
    /// is no answer.
    private var askedFrom: CLAuthorizationStatus?
    /// The app went inactive after the request: the dialog is up, so the wait ends when the app is active again.
    private var resignedForDialog = false
    private var observers: [NSObjectProtocol] = []

    var allowsAlways: Bool {
        locationManager().authorizationStatus == .authorizedAlways
    }

    func requestAlways() async -> Bool {
        let manager = locationManager()
        switch manager.authorizationStatus {
        case .authorizedAlways: return true
        case .denied, .restricted: return false
        default: break
        }
        // iOS answers through the delegate when the status changes, but "Keep Only While Using" changes nothing and a
        // dialog iOS has shown before does not show again: the wait also ends when the app is active again after the
        // dialog, or when no dialog took the app away within a second.
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            resignedForDialog = false
            askedFrom = manager.authorizationStatus
            watchDialog()
            manager.requestAlwaysAuthorization()
            Task { [weak self] in
                try? await Task.sleep(for: Self.dialogWait)
                guard let self, !self.resignedForDialog else { return }
                self.finishWaiting()
            }
        }
        return allowsAlways
    }

    func startWakes(_ onWake: @escaping @MainActor (WakeFix) async -> Void) {
        self.onWake = onWake
        if #available(iOS 18, *), serviceSession == nil {
            serviceSession = CLServiceSession(authorization: .always)
        }
        locationManager().startMonitoringSignificantLocationChanges()
    }

    func stopWakes() {
        onWake = nil
        manager?.stopMonitoringSignificantLocationChanges()
        if #available(iOS 18, *) { (serviceSession as? CLServiceSession)?.invalidate() }
        serviceSession = nil
    }

    // MARK: Delegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let fix = WakeFix(
            coordinate: GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            horizontalAccuracy: location.horizontalAccuracy,
            speed: location.speed
        )
        Task { @MainActor in self.deliver(fix) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // A failed wake-up is skipped; the next one comes with the next significant change.
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            // The delegate also hears the current status when the manager is made; only a change, an answer, ends the wait.
            guard status != .notDetermined, status != self.askedFrom else { return }
            self.finishWaiting()
        }
    }

    // MARK: Private

    /// A wake-up in the background gets about 10 s: a background task covers the decision and the check's start (loading
    /// the trains), after which the check's GPS keeps the app running.
    private func deliver(_ fix: WakeFix) {
        guard let onWake else { return }
        let time = WakeTime()
        time.begin()
        Task {
            await onWake(fix)
            time.end()
        }
    }

    private func watchDialog() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.resignedForDialog = true }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard self.resignedForDialog else { return }
                self.finishWaiting()
            }
        })
    }

    private func finishWaiting() {
        let waiting = waiters
        waiters = []
        askedFrom = nil
        for waiter in waiting { waiter.resume() }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    private func locationManager() -> CLLocationManager {
        if let manager { return manager }
        let manager = CLLocationManager()
        manager.delegate = self
        self.manager = manager
        return manager
    }
}

/// The background time a wake-up's decision runs in.
@MainActor
private final class WakeTime {
    private var id = UIBackgroundTaskIdentifier.invalid

    func begin() {
        id = UIApplication.shared.beginBackgroundTask(withName: "detect.wake") { [weak self] in
            // iOS calls this on the main thread when the time runs out.
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

/// GPS for a background check (TT-176): with Always and the `location` background mode, standard updates can start in the
/// background after a wake-up and keep the app running while the matcher checks, for up to 12 minutes. It never asks.
@MainActor
final class BackgroundFixes: NSObject, LocationProviding, CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private var onFix: (@MainActor @Sendable (LocationFix) -> Void)?

    var isAuthorized: Bool {
        locationManager().authorizationStatus == .authorizedAlways
    }

    var canAsk: Bool { false }

    func requestWhenInUse() async -> Bool { isAuthorized }

    func startUpdates(_ onFix: @escaping @MainActor @Sendable (LocationFix) -> Void) {
        self.onFix = onFix
        let manager = locationManager()
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }

    func stopUpdates() {
        onFix = nil
        guard let manager else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.map { location in
            LocationFix(
                coordinate: GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                horizontalAccuracy: location.horizontalAccuracy
            )
        }
        Task { @MainActor in
            for fix in fixes { self.onFix?(fix) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // No fix this time; the matcher carries on with the next one, and the check ends at its time anyway.
    }

    private func locationManager() -> CLLocationManager {
        if let manager { return manager }
        let manager = CLLocationManager()
        manager.delegate = self
        self.manager = manager
        return manager
    }
}
