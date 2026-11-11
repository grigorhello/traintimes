import Foundation
import UserNotifications

/// One of the ride's local notifications (TT-173): what it says and how many real seconds from now it goes off.
struct RideNotification: Equatable, Sendable {
    let id: String
    let title: String
    let body: String
    /// Real seconds from now, 1 at least.
    let delay: TimeInterval
}

/// Where the ride's notifications go: `SystemRideNotifications` in the app, a fake in tests. A notification added with the
/// id of a pending one replaces it.
@MainActor
protocol RideNotificationScheduling: AnyObject {
    func add(_ notification: RideNotification)
    /// Removes pending notifications; one already delivered stays in Notification Center.
    func remove(ids: [String])
    /// Removes every pending ride notification, also ones an earlier launch scheduled.
    func removeAll()
}

/// The ride's notifications in Notification Center: Time Sensitive (the entitlement in `Config/TrainTimes.entitlements`,
/// which needs no extra permission), with `arrive.caf`. Adding fails quietly without notification permission.
@MainActor
final class SystemRideNotifications: RideNotificationScheduling {
    static let sound = UNNotificationSoundName("arrive.caf")

    func add(_ notification: RideNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = UNNotificationSound(named: Self.sound)
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "onboard"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, notification.delay), repeats: false)
        let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func remove(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    func removeAll() {
        Task {
            let ids = await Self.pendingRideIds()
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// The pending requests that are the ride's (`ArrivalNudge.id(_:)`), not the alert server's.
    private nonisolated static func pendingRideIds() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier).filter {
            $0.hasPrefix(ArrivalNudge.idPrefix)
        }
    }
}

/// The arriving nudge (TT-173, D66, Live-Spec "The nudge, honestly"): follows a ride engine's events.
///
/// With the app open, `.phase(.arriving)` plays the taps, the rumble and the chime, and reaching your stop one tap
/// (`ArrivalFeedback`). For the app closed or locked, two Time Sensitive notifications are scheduled when the ride starts,
/// from the timetable: "Arriving at Clarkson in 1 min" a minute before the expected arrival, and "This is Clarkson" at it.
/// They move with the estimate under the same identifiers, so a new one replaces the pending one, and stay where they
/// are when location dies, so they still go off on the timetable. While the app is open iOS does not show them
/// (`AppDelegate`), so the rider gets the nudge once either way.
@MainActor
final class ArrivalNudge {
    /// The two notifications: a minute before your stop, and at it.
    enum Moment: String, CaseIterable, Sendable {
        case arriving
        case here
    }

    /// A pending notification moves only when the estimate moved this much (ride seconds): a fix comes every second.
    static let moveThreshold: TimeInterval = 15
    /// A pending notification this close to going off (real seconds) is left to go off by itself, so it never comes twice.
    static let firesSoon: TimeInterval = 2

    private let notifications: any RideNotificationScheduling
    private let feedback: any ArrivalFeedback
    /// Ride seconds per real second: 1, or the demo ride's 6.
    private let rate: Double
    private weak var engine: RideEngine?
    private var following: Task<Void, Never>?

    private var ride: Ride?
    /// When each pending notification goes off, by the ride's clock.
    private var pending: [Moment: Date] = [:]
    /// Gone off, or too late to say, this ride: never scheduled again.
    private var done: Set<Moment> = []
    /// This ride was seen before your stop, so reaching it taps; a ride restored at your stop does not tap again.
    private var sawRideBeforeYourStop = false

    init(notifications: any RideNotificationScheduling, feedback: any ArrivalFeedback, rate: Double = 1) {
        self.notifications = notifications
        self.feedback = feedback
        self.rate = rate
    }

    /// The nudge on the phone: notifications in Notification Center, taps and the chime while the app is open.
    static func system(rate: Double = 1) -> ArrivalNudge {
        ArrivalNudge(notifications: SystemRideNotifications(), feedback: SystemArrivalFeedback(), rate: rate)
    }

    /// Follows the engine's events from now on.
    func follow(_ engine: RideEngine) {
        following?.cancel()
        self.engine = engine
        let events = engine.events()
        following = Task { [weak self, weak engine] in
            for await event in events {
                guard let self else { return }
                guard let engine else {
                    // The engine is gone (a demo ride dropped), so its ride is over: what it scheduled goes.
                    self.cancel()
                    return
                }
                guard let ride = engine.ride, let destination = engine.plan?.stops.last?.station else { continue }
                self.handle(event, ride: ride, destination: destination, now: engine.now)
            }
        }
    }

    /// Schedules the pending notifications again, after the notification prompt: ones added before it was answered were
    /// refused.
    func replan() {
        guard let engine, let ride = engine.ride, ride == self.ride, let state = engine.state,
              let destination = engine.plan?.stops.last?.station else { return }
        pending = [:]
        handle(.update(state), ride: ride, destination: destination, now: engine.now)
    }

    /// At launch, once the engine's saved ride is restored. With no ride, pending ride notifications are an earlier
    /// launch's, for a ride that is over: End ride on the Live Activity can open a stopped app and drop the saved ride
    /// before it is restored (TT-174), so the nudge never saw it end. They go.
    func restoreFinished() {
        guard engine?.ride == nil, ride == nil else { return }
        notifications.removeAll()
    }

    /// Stops following and removes the pending notifications (Demo trains › Ride turned off).
    func stop() {
        following?.cancel()
        following = nil
        cancel()
    }

    func handle(_ event: RideEvent, ride: Ride, destination: Station, now: Date) {
        if ride != self.ride {
            // "I'm on board" on another train replaces the ride without ending it: the old one's notifications go.
            cancel()
            self.ride = ride
        }
        switch event {
        case .update(let state):
            settle(now)
            switch state.phase {
            case .ended:
                cancel()
            case .atYourStop:
                break
            case .riding, .atStation, .yourStopNext, .arriving:
                sawRideBeforeYourStop = true
                place(.arriving, at: state.expectedArrival.addingTimeInterval(-RideEngine.arrivingLead), destination: destination, now: now)
                place(.here, at: state.expectedArrival, destination: destination, now: now)
            }
        case .phase(.arriving):
            feedback.arriving()
        case .phase(.atYourStop):
            if sawRideBeforeYourStop { feedback.atYourStop() }
            settle(now)
            // There before "Arriving" went off: it would come late, so it goes (also an earlier launch's, for a ride
            // restored here); and "This is …" comes now, not at the timetable's time.
            if !done.contains(.arriving) {
                notifications.remove(ids: [id(.arriving)])
                pending[.arriving] = nil
                done.insert(.arriving)
            }
            sendNow(.here, destination: destination, now: now)
        case .phase(.ended):
            cancel()
        case .phase:
            break
        }
    }

    /// Schedules a notification for `target`, or moves the pending one there when the estimate moved enough.
    private func place(_ moment: Moment, at target: Date, destination: Station, now: Date) {
        guard !done.contains(moment) else { return }
        if let current = pending[moment] {
            guard abs(target.timeIntervalSince(current)) >= Self.moveThreshold,
                  current.timeIntervalSince(now) / rate >= Self.firesSoon else { return }
        } else if target <= now {
            // Never scheduled and already past: a ride started or restored after it. The app open shows the moment, and
            // an earlier launch's notification under this id, set for an older estimate, goes.
            notifications.remove(ids: [id(moment)])
            done.insert(moment)
            return
        }
        add(moment, at: target, destination: destination, now: now)
    }

    /// The pending notification goes off now, unless it is about to anyway.
    private func sendNow(_ moment: Moment, destination: Station, now: Date) {
        guard !done.contains(moment), let current = pending[moment] else { return }
        if current.timeIntervalSince(now) / rate >= Self.firesSoon {
            add(moment, at: now, destination: destination, now: now)
        }
        pending[moment] = nil
        done.insert(moment)
    }

    private func add(_ moment: Moment, at target: Date, destination: Station, now: Date) {
        let name = RideDetails.shortName(destination.name)
        let notification = switch moment {
        case .arriving:
            RideNotification(
                id: id(moment), title: String(format: String(localized: "notif.arriving.title"), name),
                body: String(localized: "notif.arriving.body"), delay: max(1, target.timeIntervalSince(now) / rate)
            )
        case .here:
            RideNotification(
                id: id(moment), title: String(format: String(localized: "notif.here.title"), name),
                body: String(localized: "notif.here.body"), delay: max(1, target.timeIntervalSince(now) / rate)
            )
        }
        notifications.add(notification)
        pending[moment] = target
    }

    /// Pending notifications whose time came went off.
    private func settle(_ now: Date) {
        for (moment, time) in pending where time <= now {
            pending[moment] = nil
            done.insert(moment)
        }
    }

    /// The ride ended: its pending notifications go, and the next ride starts afresh. Both ids go even with nothing pending
    /// here: a ride restored at launch can end at once (cancelled while the app was stopped) with the earlier launch's
    /// notifications still pending under them.
    private func cancel() {
        if ride != nil { notifications.remove(ids: Moment.allCases.map { id($0) }) }
        pending = [:]
        done = []
        sawRideBeforeYourStop = false
        ride = nil
    }

    /// Every ride notification's identifier starts with it.
    nonisolated static let idPrefix = "onboard."

    /// One identifier per moment and ride, so a moved estimate replaces the pending notification.
    func id(_ moment: Moment) -> String {
        guard let ride else { return "\(Self.idPrefix)\(moment.rawValue)" }
        return "\(Self.idPrefix)\(moment.rawValue).\(ride.tripId).\(ride.serviceDate)"
    }
}
