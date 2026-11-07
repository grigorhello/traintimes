import Foundation

/// One alert rule as the alert server stores it (TT-140, D38): This trip or Repeat. The id is picked by the app, so
/// saving the same rule again updates it on the server. Encoded as the server's JSON body, and kept on device the same way.
struct AlertRule: Codable, Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case thisTrip = "trip"
        case repeating = "repeat"
    }

    struct Stop: Codable, Hashable, Sendable {
        let id: String
        let name: String
    }

    var id: String
    var kind: Kind
    /// The picked train (D9): the feed trip id and its service date as GTFS writes it, "20261105".
    var tripId: String
    var serviceDate: String
    /// The line's short name, "LW".
    var line: String
    var scheduledDeparture: Date
    var origin: Stop
    var destination: Stop
    /// Repeat only: ISO weekdays, 1 is Monday.
    var weekdays: [Int]
    var paused: Bool

    init(id: String = UUID().uuidString.lowercased(), kind: Kind, trip: Trip, route: Route, weekdays: [Int] = [], paused: Bool = false) {
        self.id = id
        self.kind = kind
        tripId = trip.key.tripId
        serviceDate = String(trip.key.serviceDay.dateKey)
        line = route.line?.id ?? ""
        scheduledDeparture = trip.scheduledDeparture
        origin = Stop(id: route.from.id, name: route.from.name)
        destination = Stop(id: route.to.id, name: route.to.name)
        self.weekdays = kind == .repeating ? weekdays : []
        self.paused = paused
    }

    /// The picked train's identity (D9).
    var trip: TripKey? {
        guard serviceDate.count == 8, let key = Int(serviceDate) else { return nil }
        return TripKey(serviceDay: ServiceDay(dateKey: key), tripId: tripId)
    }

    /// A Repeat rule stands for the usual train: same line, stations and scheduled departure time of day, whatever the day.
    func isSameUsualTrain(as other: AlertRule) -> Bool {
        line == other.line && origin.id == other.origin.id && destination.id == other.destination.id
            && ServiceDay.minutesIntoServiceDay(scheduledDeparture) == ServiceDay.minutesIntoServiceDay(other.scheduledDeparture)
    }
}

/// A rule's state in words (§ Alert setup: rule states). On is shown only once the server stored the rule and the device
/// token is registered, and only while notifications are allowed.
enum AlertRuleState: String, Codable, Sendable {
    case settingUp
    case on
    case notificationsOff
    case couldNotSave
    case reviewNeeded
}

/// What the alert setup sheet opens for (TT-142): a train from a card or Trip details, on This trip or Repeat.
struct AlertSetupRequest: Hashable, Sendable {
    let route: Route
    let trip: Trip
    let kind: AlertRule.Kind
}
