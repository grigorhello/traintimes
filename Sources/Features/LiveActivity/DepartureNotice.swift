import Foundation
import UserNotifications

/// The departure question as a notification (TT-231, D110; the Live view canvas's board 33): "On the 4:29 PM train?" with no
/// body, Yes and No. The alert server sends it only when it holds no Live Activity card for the train
/// (`server/src/activity.ts`); its payload is an alert's (`tripId`, `serviceDate`, `originId`, `destinationId`) with
/// `kind` `departure`, so a tap opens the train's Trip details.
enum DepartureNotice {
    static let category = "depart.question"
    /// Yes opens the app and starts the ride (Apple lets a Live Activity start only in the foreground).
    static let yesAction = "depart.yes"
    /// No runs in the background: the train is declined for today.
    static let noAction = "depart.no"
    static let kind = "departure"

    static var notificationCategory: UNNotificationCategory {
        UNNotificationCategory(
            identifier: category,
            actions: [
                UNNotificationAction(identifier: yesAction, title: String(localized: "detect.yes"), options: [.foreground]),
                UNNotificationAction(identifier: noAction, title: String(localized: "detect.no"), options: []),
            ],
            intentIdentifiers: [],
            options: []
        )
    }

    /// A question left unanswered goes 10 min after it came (the card's rule); the app removes it when it next comes to the
    /// front, since the server cannot take back a delivered notification.
    static func removeExpired(now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let expired = await center.deliveredNotifications()
            .filter { $0.request.content.categoryIdentifier == category && now.timeIntervalSince($0.date) >= LiveDeparture.askFor }
            .map(\.request.identifier)
        guard !expired.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: expired)
    }
}
