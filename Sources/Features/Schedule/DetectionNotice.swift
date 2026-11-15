import Foundation
import UserNotifications

/// The background question as a notification (TT-176; TT-205, D92, *Live-Detect-Lock*): "On the train to Clarkson?" with no
/// body, and Yes (opens the app, which starts the ride) and No. It names the rider's stop of the train that fits best, as
/// Schedule's question does.
struct DetectionNotice: Equatable {
    static let category = "detect.question"
    /// One identifier, so a new question replaces the last one instead of stacking.
    static let identifier = "detect.question"
    static let startAction = "detect.start"
    static let notMeAction = "detect.notMe"

    let title: String
}

extension DetectionNotice {
    init?(_ question: TrainMatcher.Question) {
        guard let shown = TrainQuestion(question) else { return nil }
        title = shown.title
    }

    /// The two actions, registered at launch. Yes opens the app: Apple lets a Live Activity start only in the foreground, so
    /// the ride starts there, never in the handler. No (the old Not me) runs in the background.
    static var notificationCategory: UNNotificationCategory {
        UNNotificationCategory(
            identifier: category,
            actions: [
                UNNotificationAction(identifier: startAction, title: String(localized: "detect.yes"), options: [.foreground]),
                UNNotificationAction(identifier: notMeAction, title: String(localized: "detect.no"), options: []),
            ],
            intentIdentifiers: [],
            options: []
        )
    }
}

/// Posts the question through the notification centre, replacing the last one.
@MainActor
final class SystemDetectionNotifier: DetectionNotifying {
    func post(_ question: TrainMatcher.Question) {
        guard let notice = DetectionNotice(question), let train = DetectedTrain(question) else { return }
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.sound = .default
        content.categoryIdentifier = DetectionNotice.category
        content.userInfo = train.userInfo
        let request = UNNotificationRequest(identifier: DetectionNotice.identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
