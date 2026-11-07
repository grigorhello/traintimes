import Foundation

/// What a tapped notification opens (TT-144, rule 10). The alert server (TT-140, D38) puts the link beside `aps`:
/// `tripId`, `serviceDate` ("20261105", GTFS form), `originId` and `destinationId` for a trip alert, or `ruleId` alone
/// when a repeating rule needs review.
enum NotificationLink: Hashable, Sendable {
    /// A trip alert. The stations are the alert rule's, so the trip opens on the route the rider watches it on; nil in
    /// a payload without them, when the saved route is used.
    case trip(TripKey, originId: String?, destinationId: String?)
    /// "Your usual train has changed": the rule is reviewed in the Alerts tab.
    case rule(id: String)

    init?(userInfo: [AnyHashable: Any]) {
        if let tripId = userInfo["tripId"] as? String, !tripId.isEmpty,
           let date = userInfo["serviceDate"] as? String, let day = ServiceDay(gtfsDate: date) {
            self = .trip(
                TripKey(serviceDay: day, tripId: tripId),
                originId: userInfo["originId"] as? String,
                destinationId: userInfo["destinationId"] as? String
            )
        } else if let ruleId = userInfo["ruleId"] as? String, !ruleId.isEmpty {
            self = .rule(id: ruleId)
        } else {
            return nil
        }
    }

    /// The same payload as JSON, as UI tests pass it in the launch environment in place of a real notification.
    init?(json: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return nil }
        self.init(userInfo: object)
    }

    enum Target: Equatable {
        /// Trip details for that trip and service date.
        case trip(TripKey)
        case alerts
    }

    /// A trip alert opens Trip details for its trip and service date; one for a past service date, or a rule that needs
    /// review, opens the Alerts tab instead.
    func target(today: ServiceDay) -> Target {
        switch self {
        case .trip(let key, _, _): key.serviceDay < today ? .alerts : .trip(key)
        case .rule: .alerts
        }
    }

    /// The route to open a trip alert on: the alert's stations, else the saved route (also when a station is not in
    /// the schedule on device).
    func route(stations: any StationRepository, saved: Route?) async -> Route? {
        guard case .trip(_, let originId?, let destinationId?) = self,
              let all = try? await stations.stations(),
              let from = all.first(where: { $0.id == originId }),
              let to = all.first(where: { $0.id == destinationId }),
              let route = try? await stations.route(from: from, to: to)
        else { return saved }
        return route
    }
}

extension ServiceDay {
    /// Parses a GTFS service date, "20261105", as the alert server sends it; "2026-11-05" works too.
    init?(gtfsDate string: String) {
        guard string.count == 8, string.allSatisfy(\.isNumber) else {
            self.init(string)
            return
        }
        let digits = Array(string)
        guard let year = Int(String(digits[0..<4])), let month = Int(String(digits[4..<6])), let day = Int(String(digits[6..<8])),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.init(year: year, month: month, day: day)
    }
}
