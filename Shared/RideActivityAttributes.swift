import ActivityKit
import Foundation

/// The On board Live Activity (TT-174, D67): the ride on the Lock Screen and in the Dynamic Island, and before it the
/// alerted train's countdown (TT-178, D74), one activity that the hand-off turns into the ride. Compiled by the app, which
/// starts, updates and ends it (`RideLiveActivity`), and by the widget extension, which draws it; the alert server starts,
/// updates and ends the departure with pushes (`server/src/activity.ts`), so the state's keys are its JSON too. Every word
/// and time comes already formatted (D17, D19), so the extension needs no strings of its own. The attributes and the state
/// together stay well under Apple's 4 KB.
struct RideActivityAttributes: ActivityAttributes, Sendable {
    /// The ride it shows, so the app finds its activity again after a relaunch.
    let tripId: String
    /// The GTFS service date, 20261127.
    let serviceDate: Int
    let originId: String
    let destinationId: String
    /// The line's code on its tile, "LW", and its colour, "#8B1A31" (D49); nil draws the tile grey.
    let lineCode: String
    let lineColorHex: String?
    /// "Clarkson", set in semibold in the bar's right label.
    let destinationName: String
    /// The stops on the bar, the origin and your stop included.
    let stopCount: Int

    struct ContentState: Codable, Hashable, Sendable {
        /// Where the ride is (`RidePhase`), or before it where the alerted train is (`LiveDeparture.Phase`, TT-178): one
        /// activity carries the departure and then the ride.
        enum Phase: String, Codable, Hashable, Sendable {
            case riding, atStation, yourStopNext, arriving, atYourStop
            case countingDown, boarding, departed
        }

        var phase: Phase
        /// "Next stop · Port Credit", "Now at · Mimico", "Arriving at Clarkson", "This is your stop"; before departure the
        /// train, "5:13 PM to Clarkson".
        var title: String
        /// "Clarkson 5:43 PM · 2 stops", "Your stop · doors in a minute"; before departure "Platform 7 · On time".
        var detail: String
        /// The countdown runs on the device to this time (timer text, no updates needed); nil shows `now` instead.
        var countdownEnd: Date?
        /// "Now", in place of the countdown at a station and at your stop; empty before departure.
        var now: String
        /// The time under the countdown, "5:36 PM"; "departs" before departure.
        var time: String
        /// The bar's two labels: "Union Station 5:13 PM", when the train left the origin, and "Clarkson 5:43 PM", when it is
        /// expected at your stop.
        var departure: String
        var arrival: String
        /// Where the train is on the bar, in stops from the origin: 3.25 is a quarter of the way from the fourth stop to
        /// the fifth; the last stop's index at your stop.
        var position: Double
        /// "End ride", or "Done" at your stop: the expanded island's link.
        var button: String
        /// "Updated 5:31 PM": takes the detail's place once the activity is stale (the app stopped updating it).
        var updated: String

        // Before departure (TT-178); nil and false during the ride.

        /// The expanded island's line, "Arrives Clarkson 5:43 PM".
        var arrives: String?
        /// The start of the detail: "Platform 7", "Platform" (the pill follows), or "Check the board".
        var platform: String?
        /// The pending platform's pill follows "Platform" (D55; still, since an activity does not animate).
        var pill = false
        /// Counting down a late train: the countdown and the delay in amber.
        var late = false

        /// About a minute before your stop: the activity turns brand green (the compact island's countdown on a green
        /// capsule) and alerts once.
        var isAlert: Bool { phase == .arriving }

        /// Before departure: the countdown to the train, "I’m on board" in the expanded island.
        var isDeparture: Bool {
            switch phase {
            case .countingDown, .boarding, .departed: true
            case .riding, .atStation, .yourStopNext, .arriving, .atYourStop: false
            }
        }
    }

    /// This activity shows `ride`.
    func shows(tripId: String, serviceDate: Int, originId: String, destinationId: String) -> Bool {
        self.tripId == tripId && self.serviceDate == serviceDate && self.originId == originId
            && self.destinationId == destinationId
    }
}

extension RideActivityAttributes.ContentState {
    enum CodingKeys: String, CodingKey {
        case phase, title, detail, countdownEnd, now, time, departure, arrival, position, button, updated
        case arrives, platform, pill, late
    }

    /// The alert server's push carries the same keys (`server/src/activity.ts`). `countdownEnd` travels as seconds since
    /// 1970, so the app and the server write it alike whatever date strategy ActivityKit decodes with; a missing key reads as
    /// empty rather than failing the whole activity.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phase = try container.decode(Phase.self, forKey: .phase)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        countdownEnd = try container.decodeIfPresent(Double.self, forKey: .countdownEnd).map(Date.init(timeIntervalSince1970:))
        now = try container.decodeIfPresent(String.self, forKey: .now) ?? ""
        time = try container.decodeIfPresent(String.self, forKey: .time) ?? ""
        departure = try container.decodeIfPresent(String.self, forKey: .departure) ?? ""
        arrival = try container.decodeIfPresent(String.self, forKey: .arrival) ?? ""
        position = try container.decodeIfPresent(Double.self, forKey: .position) ?? 0
        button = try container.decodeIfPresent(String.self, forKey: .button) ?? ""
        updated = try container.decodeIfPresent(String.self, forKey: .updated) ?? ""
        arrives = try container.decodeIfPresent(String.self, forKey: .arrives)
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
        pill = try container.decodeIfPresent(Bool.self, forKey: .pill) ?? false
        late = try container.decodeIfPresent(Bool.self, forKey: .late) ?? false
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(phase, forKey: .phase)
        try container.encode(title, forKey: .title)
        try container.encode(detail, forKey: .detail)
        try container.encodeIfPresent(countdownEnd?.timeIntervalSince1970, forKey: .countdownEnd)
        try container.encode(now, forKey: .now)
        try container.encode(time, forKey: .time)
        try container.encode(departure, forKey: .departure)
        try container.encode(arrival, forKey: .arrival)
        try container.encode(position, forKey: .position)
        try container.encode(button, forKey: .button)
        try container.encode(updated, forKey: .updated)
        try container.encodeIfPresent(arrives, forKey: .arrives)
        try container.encodeIfPresent(platform, forKey: .platform)
        try container.encode(pill, forKey: .pill)
        try container.encode(late, forKey: .late)
    }
}

/// The app's links from the activity: during the ride a tap opens Trip details on the ride and the expanded island's button
/// ends it; before departure (TT-178) a tap opens the train's Trip details and the button starts the ride on it.
enum RideActivityLink: Equatable {
    case open
    case end
    case departure
    case board

    static let scheme = "traintimes"

    var url: URL {
        switch self {
        case .open: URL(string: "\(Self.scheme)://ride")!
        case .end: URL(string: "\(Self.scheme)://ride/end")!
        case .departure: URL(string: "\(Self.scheme)://departure")!
        case .board: URL(string: "\(Self.scheme)://departure/board")!
        }
    }

    init?(_ url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        switch (url.host(), url.path()) {
        case ("ride", ""), ("ride", "/"): self = .open
        case ("ride", "/end"): self = .end
        case ("departure", ""), ("departure", "/"): self = .departure
        case ("departure", "/board"): self = .board
        default: return nil
        }
    }
}
