import ActivityKit
import Foundation

/// The On board Live Activity (TT-174, D67): the ride on the Lock Screen and in the Dynamic Island. Compiled by the app,
/// which starts, updates and ends it (`RideLiveActivity`), and by the widget extension, which draws it. Every word and time
/// comes from the app already formatted (D17, D19), so the extension needs no strings of its own. The attributes and the
/// state together stay well under Apple's 4 KB.
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
        /// Where the ride is (`RidePhase`); the before-departure activity (TT-178) adds its phases here, so one activity
        /// carries the departure and then the ride.
        enum Phase: String, Codable, Hashable, Sendable {
            case riding, atStation, yourStopNext, arriving, atYourStop
        }

        var phase: Phase
        /// "Next stop · Port Credit", "Now at · Mimico", "Arriving at Clarkson", "This is your stop".
        var title: String
        /// "Clarkson 5:43 PM · 2 stops", "Your stop · doors in a minute".
        var detail: String
        /// The countdown runs on the device to this time (timer text, no updates needed); nil shows `now` instead.
        var countdownEnd: Date?
        /// "Now", in place of the countdown at a station and at your stop.
        var now: String
        /// The time under the countdown, "5:36 PM".
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

        /// About a minute before your stop: the activity turns brand green (the compact island's countdown on a green
        /// capsule) and alerts once.
        var isAlert: Bool { phase == .arriving }
    }

    /// This activity shows `ride`.
    func shows(tripId: String, serviceDate: Int, originId: String, destinationId: String) -> Bool {
        self.tripId == tripId && self.serviceDate == serviceDate && self.originId == originId
            && self.destinationId == destinationId
    }
}

/// The app's links from the activity: a tap opens Trip details on the ride, the expanded island's button ends it.
enum RideActivityLink: Equatable {
    case open
    case end

    static let scheme = "traintimes"

    var url: URL {
        switch self {
        case .open: URL(string: "\(Self.scheme)://ride")!
        case .end: URL(string: "\(Self.scheme)://ride/end")!
        }
    }

    init?(_ url: URL) {
        guard url.scheme == Self.scheme, url.host() == "ride" else { return nil }
        switch url.path() {
        case "", "/": self = .open
        case "/end": self = .end
        default: return nil
        }
    }
}
