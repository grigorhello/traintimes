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
    /// "Clarkson": the rider's stop.
    let destinationName: String
    /// The stops on the stop line, the origin and your stop included.
    let stopCount: Int

    /// One card for every moment (TT-205, D93): the line's tile and one line, the big number under it, one labelled fact at
    /// the right, and during the ride the stop line. The same words as the app's screens.
    struct ContentState: Codable, Hashable, Sendable {
        /// Where the ride is (`RidePhase`), or before it where the alerted train is (`LiveDeparture.Phase`, TT-178): one
        /// activity carries the departure and then the ride. `departed` with `asks` is the question "On board?" (TT-231,
        /// D110); no new case, so a build from before TT-231 still reads the alert server's push.
        enum Phase: String, Codable, Hashable, Sendable {
            case riding, atStation, yourStopNext, arriving, atYourStop
            case countingDown, boarding, departed
        }

        var phase: Phase
        /// The one line: "5:13 PM departs in", "5:16 PM boarding now", "5:16 PM departed"; during the ride "Clarkson in",
        /// "Clarkson is next", "Arriving at Clarkson", "This is Clarkson".
        var title: String
        /// The big number runs on the device to this time (timer text, no updates needed): the expected departure, or the
        /// expected arrival at your stop. Nil shows `now` instead.
        var countdownEnd: Date?
        /// The big number in whole minutes, "15 min" (TT-219, D97): the app and the alert server send it again when the
        /// minute changes. Nil (a push from an older alert server) shows timer text to `countdownEnd` instead.
        var minutes: String?
        /// "Now" at your stop; empty once the train has left before a ride.
        var now: String
        /// The label at the right: "Platform" before departure, "Arrives" during the ride; empty when the card shows
        /// nothing there (arriving, at your stop).
        var label: String
        /// The value under it during the ride, "5:43 PM"; nil before departure, where the platform pill is the value.
        var value: String?
        /// "3 min late" beside the minutes while a train counts down late; nil otherwise.
        var delay: String?
        /// The posted platform, "7", in its pill (TT-199); nil draws the dash (the alert server knows no platforms).
        var platformNumber: String?
        /// The train runs late: the clock time in the line, and the arrival, in amber.
        var late = false
        /// Where the train is on the stop line, in dots from the origin: 3.25 is a quarter of the way from the fourth dot
        /// to the fifth; the last dot's index at your stop.
        var position: Double
        /// The stop line's dots on a ride that passes stations without stopping (TT-232, D111): every station from where
        /// you got on to your stop. Nil draws the attributes' `stopCount`, the ride's stops.
        var stations: Int?
        /// Which of those dots the train does not stop at: drawn hollow.
        var skipped: [Int] = []
        /// The Schedule card's express tag: the bolt above the train on the stop line, and after the tile in the compact
        /// island. Only during the ride.
        var express = false
        /// Your stop is next, or the train is boarding: the number turns mint, as on the ride screen.
        var isClose = false
        /// "Updated 5:31 PM": shown in place of the line once the activity is stale (the app stopped updating it).
        var updated: String
        /// The train has left with no ride on, and the card asks "On board?" with Yes and No (TT-231, D110).
        var asks = false

        /// About a minute before your stop: the activity alerts once.
        var isAlert: Bool { phase == .arriving }

        /// Arriving and at your stop: the Lock Screen card turns brand green.
        var isGreen: Bool { phase == .arriving || phase == .atYourStop }

        /// Before departure: the countdown to the train.
        var isDeparture: Bool {
            switch phase {
            case .countingDown, .boarding, .departed: true
            case .riding, .atStation, .yourStopNext, .arriving, .atYourStop: false
            }
        }

        /// The card asks "On board?" (TT-231, D110).
        var isAsking: Bool { phase == .departed && asks }
    }

    /// This activity shows `ride`.
    func shows(tripId: String, serviceDate: Int, originId: String, destinationId: String) -> Bool {
        self.tripId == tripId && self.serviceDate == serviceDate && self.originId == originId
            && self.destinationId == destinationId
    }
}

extension RideActivityAttributes.ContentState {
    enum CodingKeys: String, CodingKey {
        case phase, title, countdownEnd, minutes, now, label, value, delay, platformNumber, late, position, isClose, updated
        case stations, skipped, express
        case asks
        /// Written by the alert server before TT-205: the label's fallback, "Check the board".
        case platform
    }

    /// The alert server's push carries the same keys (`server/src/activity.ts`). `countdownEnd` travels as seconds since
    /// 1970, so the app and the server write it alike whatever date strategy ActivityKit decodes with; a missing key reads as
    /// empty rather than failing the whole activity, so a push from an older server still updates the card (its title, the
    /// countdown, and "Check the board" as the label).
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phase = try container.decode(Phase.self, forKey: .phase)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        countdownEnd = try container.decodeIfPresent(Double.self, forKey: .countdownEnd).map(Date.init(timeIntervalSince1970:))
        minutes = try container.decodeIfPresent(String.self, forKey: .minutes)
        now = try container.decodeIfPresent(String.self, forKey: .now) ?? ""
        label = try container.decodeIfPresent(String.self, forKey: .label)
            ?? container.decodeIfPresent(String.self, forKey: .platform) ?? ""
        value = try container.decodeIfPresent(String.self, forKey: .value)
        delay = try container.decodeIfPresent(String.self, forKey: .delay)
        platformNumber = try container.decodeIfPresent(String.self, forKey: .platformNumber)
        late = try container.decodeIfPresent(Bool.self, forKey: .late) ?? false
        position = try container.decodeIfPresent(Double.self, forKey: .position) ?? 0
        stations = try container.decodeIfPresent(Int.self, forKey: .stations)
        skipped = try container.decodeIfPresent([Int].self, forKey: .skipped) ?? []
        express = try container.decodeIfPresent(Bool.self, forKey: .express) ?? false
        isClose = try container.decodeIfPresent(Bool.self, forKey: .isClose) ?? false
        updated = try container.decodeIfPresent(String.self, forKey: .updated) ?? ""
        asks = try container.decodeIfPresent(Bool.self, forKey: .asks) ?? false
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(phase, forKey: .phase)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(countdownEnd?.timeIntervalSince1970, forKey: .countdownEnd)
        try container.encodeIfPresent(minutes, forKey: .minutes)
        try container.encode(now, forKey: .now)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(delay, forKey: .delay)
        try container.encodeIfPresent(platformNumber, forKey: .platformNumber)
        try container.encode(late, forKey: .late)
        try container.encode(position, forKey: .position)
        // Only on a ride that has them, so every other activity's JSON stays as the alert server writes it.
        try container.encodeIfPresent(stations, forKey: .stations)
        if !skipped.isEmpty { try container.encode(skipped, forKey: .skipped) }
        if express { try container.encode(express, forKey: .express) }
        try container.encode(isClose, forKey: .isClose)
        try container.encode(updated, forKey: .updated)
        if asks { try container.encode(asks, forKey: .asks) }
    }
}

/// The app's links from the activity: during the ride a tap opens Trip details on the ride; before departure (TT-178) a tap
/// opens the train's Trip details. The card's only buttons are the departure question's (TT-231, D110): Yes is `board`, No
/// is `DeclineDepartureIntent`; `end` stays as a link the app understands.
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
