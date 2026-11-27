import UIKit
import UserNotifications

/// The wrong train warning as a notification (TT-250, D127; the Live view canvas's board 57): posted by the app only when it
/// is not in front and no card can show. Local, Time Sensitive, the default sound, one post and one buzz (the five buzzes
/// are the card's). "Wrong train?" with "Doesn’t stop at Clarkson. Next stop Oakville, 5:38 PM.", and under press and hold
/// "Trains from Oakville" (opens the app) and "I’m fine" (in the background). Its payload carries the train's ids and the
/// three stations, so the actions work after a relaunch with no warning held; `kind` `wrongTrain` keeps it out of Alerts ›
/// Recent (`AlertUpdate`).
enum WrongTrainNotice {
    static let category = "wrong.train"
    static let trainsAction = "wrong.trains"
    static let fineAction = "wrong.fine"
    static let kind = "wrongTrain"
    /// One at a time: a new one replaces the last.
    static let identifier = "wrongTrain"
    /// `notification_opened`'s kind.
    static let analyticsKind = "wrong_train"

    /// The category; action titles are fixed when it is registered, so the launch names the first "See trains" and the
    /// presenter names it for the station right before posting.
    static func notificationCategory(trainsTitle: String? = nil) -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: category,
            actions: [
                UNNotificationAction(
                    identifier: trainsAction, title: trainsTitle ?? String(localized: "alerts.see_trains"), options: [.foreground]
                ),
                UNNotificationAction(identifier: fineAction, title: String(localized: "wrong.fine"), options: []),
            ],
            intentIdentifiers: [],
            options: []
        )
    }

    /// The payload: the train's ids, X's next stop and O.
    static func userInfo(_ note: WrongTrainNote) -> [String: String] {
        [
            "kind": kind,
            "tripId": note.ride.tripId,
            "serviceDate": String(note.ride.serviceDate),
            "originId": note.ride.originId,
            "destinationId": note.ride.destinationId,
            "nextStopId": note.nextStopId,
            "wrongOriginId": note.originId,
        ]
    }

    /// Posts it at once. The categories are read back first, so the one with the station's name is in place.
    static func post(title: String, body: String, userInfo: [String: String]) async {
        let center = UNUserNotificationCenter.current()
        _ = await center.notificationCategories()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = category
        content.threadIdentifier = "onboard"
        content.userInfo = userInfo
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    /// The train and the stations from a payload; nil for anything else.
    static func train(from userInfo: [AnyHashable: Any]) -> (ride: Ride, nextStopId: String, originId: String)? {
        guard userInfo["kind"] as? String == kind,
              let tripId = userInfo["tripId"] as? String,
              let date = (userInfo["serviceDate"] as? String).flatMap({ Int($0) }),
              let origin = userInfo["originId"] as? String,
              let destination = userInfo["destinationId"] as? String,
              let next = userInfo["nextStopId"] as? String else { return nil }
        let ride = Ride(
            trip: TripKey(serviceDay: ServiceDay(dateKey: date), tripId: tripId), from: origin, to: destination
        )
        return (ride, next, userInfo["wrongOriginId"] as? String ?? origin)
    }
}

/// Every category the app registers, in one place: the departure question's (TT-231) and the wrong train's (TT-250).
enum NotificationCategories {
    static func register(wrongTrainsTitle: String? = nil) {
        UNUserNotificationCenter.current().setNotificationCategories([
            DepartureNotice.notificationCategory,
            WrongTrainNotice.notificationCategory(trainsTitle: wrongTrainsTitle),
        ])
    }
}

/// The warning's notification on the phone. It never asks for permission: with notifications off the warning in the app is
/// all there is.
@MainActor
final class SystemWrongTrainNotifier: WrongTrainNotifying {
    func post(_ note: WrongTrainNote) async {
        NotificationCategories.register(wrongTrainsTitle: note.trainsTitle)
        await WrongTrainNotice.post(title: note.title, body: note.body, userInfo: WrongTrainNotice.userInfo(note))
    }

    func remove() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [WrongTrainNotice.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [WrongTrainNotice.identifier])
    }
}

/// Background time while the demo plays (`beginBackgroundTask`, as `SystemWakeLocation`'s): the demo ride has no location
/// session, so a locked phone keeps the app awake through the five buzzes.
@MainActor
final class SystemBackgroundTime: BackgroundTiming {
    private var task: UIBackgroundTaskIdentifier = .invalid

    func begin() {
        guard task == .invalid else { return }
        task = UIApplication.shared.beginBackgroundTask(withName: "wrongTrain.demo") { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}
