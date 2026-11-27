import CoreLocation
import UIKit

/// "When the app is closed"'s location in the app (TT-243, D120; "Detect my train"'s before it, TT-176): the Always
/// permission and the significant-change wake-ups. The location manager is made on first use; `AutoRideWake.resume()` makes
/// it at launch while the switch is on, which is what lets a relaunch for a wake-up deliver it. On iOS 18 a
/// `CLServiceSession` asking for Always is held while the wake-ups run, as iOS 18 expects of an app that uses location in
/// the background. It asks only from the rider's tap on the switch: When In Use first where location was never asked, so
/// the rider reads its sentence, then Always (TT-234, D116), which iOS shows once (`canAskAlways`).
@MainActor
final class SystemWakeLocation: NSObject, WakeLocationProviding, CLLocationManagerDelegate {
    /// After the Always request, a dialog shows within this long or not at all (iOS shows it once).
    static let dialogWait: Duration = .seconds(1)
    /// The Always dialog was asked for while When In Use was allowed: iOS shows it once, so a second tap opens Settings.
    static let alwaysAskedKey = "location.alwaysAsked"

    private var manager: CLLocationManager?
    private var onWake: (@MainActor (WakeFix) async -> Void)?
    /// The iOS 18 `CLServiceSession`, kept as `Any` so iOS 17 builds.
    private var serviceSession: Any?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Waiting for the answer to the When In Use prompt.
    private var whenInUseWaiters: [CheckedContinuation<Void, Never>] = []
    /// The status when Always was asked for: the delegate also hears the current status when the manager is made, which
    /// is no answer.
    private var askedFrom: CLAuthorizationStatus?
    /// The app went inactive after the request: the dialog is up, so the wait ends when the app is active again.
    private var resignedForDialog = false
    private var observers: [NSObjectProtocol] = []

    var allowsAlways: Bool {
        locationManager().authorizationStatus == .authorizedAlways
    }

    var canAskWhenInUse: Bool {
        locationManager().authorizationStatus == .notDetermined
    }

    var canAskAlways: Bool {
        switch locationManager().authorizationStatus {
        case .notDetermined: true
        case .authorizedWhenInUse: !UserDefaults.standard.bool(forKey: Self.alwaysAskedKey)
        default: false
        }
    }

    func requestWhenInUse() async -> Bool {
        let manager = locationManager()
        guard manager.authorizationStatus == .notDetermined else { return Self.allows(manager.authorizationStatus) }
        await withCheckedContinuation { continuation in
            whenInUseWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
        // The prompt took the app inactive. The Always request that follows knows its own dialog by the app going
        // inactive again, so it starts once the app is back.
        await Self.waitUntilActive()
        return Self.allows(manager.authorizationStatus)
    }

    func requestAlways() async -> Bool {
        let manager = locationManager()
        // Never asked: When In Use first, whoever calls (TT-234, D116).
        if manager.authorizationStatus == .notDetermined {
            guard await requestWhenInUse() else { return false }
        }
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
            UserDefaults.standard.set(true, forKey: Self.alwaysAskedKey)
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
            guard status != .notDetermined else { return }
            self.finishWhenInUse()
            guard status != self.askedFrom else { return }
            self.finishWaiting()
        }
    }

    // MARK: Private

    /// A wake-up in the background gets about 10 s: a background task covers the decision and the watch's start (reading
    /// today's alerted trains), after which the watch's GPS keeps the app running.
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

    /// The When In Use prompt was answered.
    private func finishWhenInUse() {
        let waiting = whenInUseWaiters
        whenInUseWaiters = []
        for waiter in waiting { waiter.resume() }
    }

    /// An iOS prompt takes the app inactive: waits until it is active again.
    private static func waitUntilActive() async {
        while UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func allows(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
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
        id = UIApplication.shared.beginBackgroundTask(withName: "autoRide.wake") { [weak self] in
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

/// GPS for a watch armed with the app closed (TT-243, D120; a background check's before, TT-176): with Always and the
/// `location` background mode, standard updates can start in the background after a wake-up and keep the app running while
/// the watch decides, and the ride it starts keeps them until the next launch. Automatic pauses stay off, so no fix is
/// stationary. Each fix carries its age from its timestamp: batched fixes would otherwise share one time and break Y2's
/// rules. It never asks.
@MainActor
final class BackgroundFixes: NSObject, LocationProviding, CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private var onFix: (@MainActor @Sendable (LocationFix) -> Void)?

    var isAuthorized: Bool {
        locationManager().authorizationStatus == .authorizedAlways
    }

    var canAsk: Bool { false }

    var isPrecise: Bool {
        locationManager().accuracyAuthorization == .fullAccuracy
    }

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

    /// Stop, then start with the same callback (TT-251, D127): the wrong train check's try at waking paused updates.
    func restartUpdates() {
        guard let onFix else { return }
        stopUpdates()
        startUpdates(onFix)
    }

    func stopUpdates() {
        onFix = nil
        guard let manager else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.map { Self.fix(from: $0, now: Date()) }
        Task { @MainActor in
            for fix in fixes { self.onFix?(fix) }
        }
    }

    /// A fix as the watch and the ride read it, with its age from its own timestamp.
    nonisolated static func fix(from location: CLLocation, now: Date) -> LocationFix {
        LocationFix(
            coordinate: GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            horizontalAccuracy: location.horizontalAccuracy,
            age: max(0, now.timeIntervalSince(location.timestamp))
        )
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // No fix this time; the watch carries on with the next one, and decides at its deadline anyway.
    }

    private func locationManager() -> CLLocationManager {
        if let manager { return manager }
        let manager = CLLocationManager()
        manager.delegate = self
        self.manager = manager
        return manager
    }
}
