import Foundation
import Observation
import UserNotifications

/// One train-specific notification from the alert server (TT-140), as the Alerts tab's Recent updates list it (TT-143):
/// its title and body as delivered, when it arrived, and the trip it is about.
struct AlertUpdate: Codable, Hashable, Sendable, Identifiable {
    /// The status the notification reports, for its icon colour. The server sends it as `kind` beside the trip.
    enum Kind: String, Codable, Sendable {
        case delay
        case recovery
        case cancelled
        case skipped
    }

    /// The notification request's identifier.
    let id: String
    let kind: Kind
    /// "7:32 AM train delayed 9 min".
    let title: String
    /// "Oakville to Union. Now expected 7:41 AM, as reported at 7:14 AM."
    let body: String
    let deliveredAt: Date
    let tripId: String
    /// GTFS form, "20261105".
    let serviceDate: String
    var originId: String?
    var destinationId: String?

    /// Trip details for that trip and service date, as a tap on the notification opens (TT-144).
    var link: NotificationLink? {
        var userInfo: [String: String] = ["tripId": tripId, "serviceDate": serviceDate]
        userInfo["originId"] = originId
        userInfo["destinationId"] = destinationId
        return NotificationLink(userInfo: userInfo as [AnyHashable: Any])
    }
}

extension AlertUpdate {
    /// A notification's content and payload; nil for one that is not about a train ("Your usual train has changed").
    init?(id: String, deliveredAt: Date, title: String, body: String, userInfo: [AnyHashable: Any]) {
        guard let tripId = userInfo["tripId"] as? String, !tripId.isEmpty,
              let serviceDate = userInfo["serviceDate"] as? String, !serviceDate.isEmpty else { return nil }
        self.init(
            id: id,
            kind: (userInfo["kind"] as? String).flatMap(Kind.init(rawValue:)) ?? .delay,
            title: title,
            body: body,
            deliveredAt: deliveredAt,
            tripId: tripId,
            serviceDate: serviceDate,
            originId: userInfo["originId"] as? String,
            destinationId: userInfo["destinationId"] as? String
        )
    }

    init?(_ notification: UNNotification) {
        let content = notification.request.content
        self.init(
            id: notification.request.identifier, deliveredAt: notification.date, title: content.title, body: content.body,
            userInfo: content.userInfo
        )
    }
}

/// The train notifications iOS still shows in Notification Center.
protocol DeliveredNotificationsProviding: Sendable {
    func delivered() async -> [AlertUpdate]
}

struct SystemDeliveredNotifications: DeliveredNotificationsProviding {
    func delivered() async -> [AlertUpdate] {
        await UNUserNotificationCenter.current().deliveredNotifications().compactMap { AlertUpdate($0) }
    }
}

/// A fixed list: none in fixture runs (UI tests and the unit test host), sample updates in previews and snapshots.
struct FixedDeliveredNotifications: DeliveredNotificationsProviding {
    var updates: [AlertUpdate] = []

    func delivered() async -> [AlertUpdate] { updates }
}

/// Recent updates on the Alerts tab (TT-143): the train notifications delivered in the last 7 days, newest first. iOS
/// keeps a notification only until the rider clears or taps it, so each one the app sees is kept on device
/// (`alerts.updates`): those still in Notification Center whenever the list refreshes, and those that arrive while the app
/// is open or are tapped (`AppDelegate`).
@Observable @MainActor
final class AlertUpdates {
    static let storageKey = "alerts.updates"
    /// 7 days.
    static let window: TimeInterval = 7 * 24 * 60 * 60

    /// Newest first, none older than 7 days.
    private(set) var updates: [AlertUpdate] = []

    private let source: any DeliveredNotificationsProviding
    private let clock: any AppClock
    /// Nil keeps the list in memory (previews and the unit test host).
    private let defaults: UserDefaults?

    init(source: any DeliveredNotificationsProviding, clock: any AppClock, defaults: UserDefaults?) {
        self.source = source
        self.clock = clock
        self.defaults = defaults
        updates = Self.recent(Self.stored(in: defaults), now: clock.now)
    }

    /// Adds what Notification Center and the app have seen since, and drops anything older than 7 days.
    func refresh() async {
        let delivered = await source.delivered()
        var seen = Set<AlertUpdate.ID>()
        let all = (updates + delivered + Self.stored(in: defaults)).filter { seen.insert($0.id).inserted }
        let recent = Self.recent(all, now: clock.now)
        if recent != updates { updates = recent }
        Self.store(recent, in: defaults)
    }

    /// Keeps a notification the app saw arrive or that was tapped; iOS then no longer lists it.
    static func record(_ update: AlertUpdate, in defaults: UserDefaults?) {
        var all = stored(in: defaults)
        guard !all.contains(where: { $0.id == update.id }) else { return }
        all.append(update)
        store(all, in: defaults)
    }

    private static func recent(_ all: [AlertUpdate], now: Date) -> [AlertUpdate] {
        all.filter { now.timeIntervalSince($0.deliveredAt) < window }.sorted { $0.deliveredAt > $1.deliveredAt }
    }

    private static func stored(in defaults: UserDefaults?) -> [AlertUpdate] {
        (defaults?.data(forKey: storageKey)).flatMap { try? JSONDecoder().decode([AlertUpdate].self, from: $0) } ?? []
    }

    private static func store(_ updates: [AlertUpdate], in defaults: UserDefaults?) {
        defaults?.set(try? JSONEncoder().encode(updates), forKey: storageKey)
    }
}
