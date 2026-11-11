import Foundation
import UserNotifications

/// The background question as a notification (TT-176, *Live-Detect-Lock*): "On the 5:13 PM train?" and "Lakeshore West,
/// moving with it since Union. Start On board for a tap before Clarkson.", with Start On board (opens the app, which starts
/// the ride) and Not me. It names the train that fits best; Schedule's question can offer two (D68). Every time is
/// formatted by the one formatter (D17).
struct DetectionNotice: Equatable {
    static let category = "detect.question"
    /// One identifier, so a new question replaces the last one instead of stacking.
    static let identifier = "detect.question"
    static let startAction = "detect.start"
    static let notMeAction = "detect.notMe"

    let title: String
    let body: String
}

extension DetectionNotice {
    init?(_ question: TrainMatcher.Question, formatter: some TimeFormatting) {
        guard let train = question.trains.first else { return nil }
        title = String(format: String(localized: "detect.question"), formatter.time(train.departure))
        let origin = question.since?.name ?? train.plan.stops.first?.station.name ?? train.route.from.name
        body = String(
            format: String(localized: "detect.notif.body"),
            train.route.line?.name ?? "",
            TrainQuestion.shortName(origin),
            TrainQuestion.shortName(train.route.to.name)
        )
    }

    /// The two actions, registered at launch. Start On board opens the app: Apple lets a Live Activity start only in the
    /// foreground, so the ride starts there, never in the handler. Not me runs in the background.
    static var notificationCategory: UNNotificationCategory {
        UNNotificationCategory(
            identifier: category,
            actions: [
                UNNotificationAction(identifier: startAction, title: String(localized: "detect.notif.start"), options: [.foreground]),
                UNNotificationAction(identifier: notMeAction, title: String(localized: "detect.notif.notMe"), options: []),
            ],
            intentIdentifiers: [],
            options: []
        )
    }
}

/// Posts the question through the notification centre, replacing the last one.
@MainActor
final class SystemDetectionNotifier: DetectionNotifying {
    private let formatter: @MainActor () -> TimeFormatter

    init(formatter: @escaping @MainActor () -> TimeFormatter) {
        self.formatter = formatter
    }

    func post(_ question: TrainMatcher.Question) {
        guard let notice = DetectionNotice(question, formatter: formatter()), let train = DetectedTrain(question) else { return }
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = .default
        content.categoryIdentifier = DetectionNotice.category
        content.userInfo = train.userInfo
        let request = UNNotificationRequest(identifier: DetectionNotice.identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
