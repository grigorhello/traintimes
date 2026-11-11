import Foundation
import XCTest
@testable import TrainTimes

/// The On board tests' ride (TT-171): the 11:17 AM Lakeshore West train from Union on Fri Nov 27 (`20261127-LW-1015`,
/// shape UNAL) to Clarkson, from the November sample feed. The sample has no shapes.txt, so its track is a synthetic one
/// drawn through the line's stations.
enum OnBoardFixtures {
    static let friday = ServiceDay(year: 2026, month: 11, day: 27)
    static let ride = Ride(trip: TripKey(serviceDay: friday, tripId: "20261127-LW-1015"), from: "UN", to: "CL")

    /// Union, Exhibition, Mimico, Long Branch, Port Credit, Clarkson and Oakville, with a bend between each pair.
    static let shapes = """
    shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence,shape_dist_traveled
    UNAL,43.645195,-79.380600,1,
    UNAL,43.641500,-79.399000,2,
    UNAL,43.635549,-79.418927,3,
    UNAL,43.627500,-79.458000,4,
    UNAL,43.616411,-79.497762,5,
    UNAL,43.604500,-79.522500,6,
    UNAL,43.591317,-79.546149,7,
    UNAL,43.574000,-79.567000,8,
    UNAL,43.555999,-79.586881,9,
    UNAL,43.535000,-79.611000,10,
    UNAL,43.513127,-79.633206,11,
    UNAL,43.455594,-79.682242,12,
    """

    static func timetable() throws -> GTFSTimetable {
        let archive = try ZipArchive(data: GTFSTimetableTests.sampleZip())
        let feed = try GTFSFeed(importedAt: Date(timeIntervalSince1970: 0)) { name -> Data? in
            if name == "shapes.txt" { return Data(shapes.utf8) }
            return try archive.data(named: name)
        }
        return GTFSTimetable(feed: feed)
    }

    static func plan() throws -> RidePlan {
        try XCTUnwrap(timetable().ridePlan(for: ride))
    }

    /// 11:17 AM, Toronto, as GTFS writes it.
    static func time(_ hours: Int, _ minutes: Int, _ seconds: Int = 0) -> Date {
        friday.gtfsTime(hours * 3600 + minutes * 60 + seconds)
    }

    /// Where a train on time is at `time`: at each station from 20 s before its time to 20 s after, and at an even speed
    /// between them.
    static func along(at time: Date, plan: RidePlan) throws -> Double {
        let distances = try XCTUnwrap(plan.track).stopDistances
        let stops = plan.stops
        for index in stops.indices {
            let reaches = index == 0 ? Date.distantPast : stops[index].arrival.addingTimeInterval(-20)
            if time < reaches {
                let leaves = stops[index - 1].departure.addingTimeInterval(20)
                let fraction = time.timeIntervalSince(leaves) / reaches.timeIntervalSince(leaves)
                return distances[index - 1] + (distances[index] - distances[index - 1]) * max(0, fraction)
            }
            if index == stops.count - 1 || time <= stops[index].departure.addingTimeInterval(20) { return distances[index] }
        }
        return distances[stops.count - 1]
    }

    /// A phone fix on the track at that distance, or `north` metres off it.
    static func fix(along distance: Double, plan: RidePlan, north: Double = 0, stationary: Bool = false) throws -> LocationFix {
        var point = try XCTUnwrap(plan.track).shape.point(at: distance)
        point.latitude += north / 111_195.08
        return LocationFix(coordinate: point, horizontalAccuracy: 8, isStationary: stationary)
    }
}

/// The phone's location in ride tests: counts the permission requests, and sends the fixes a test gives it.
@MainActor
final class FakeLocation: LocationProviding {
    var isAuthorized: Bool
    /// What the rider answers to the When In Use prompt.
    var answer = true
    private(set) var requests = 0
    private(set) var isUpdating = false
    private var onFix: (@MainActor @Sendable (LocationFix) -> Void)?

    init(authorized: Bool = false) {
        isAuthorized = authorized
    }

    /// Unanswered until the first request, unless the test starts with location allowed.
    var canAsk: Bool { !isAuthorized && requests == 0 }

    func requestWhenInUse() async -> Bool {
        requests += 1
        isAuthorized = answer
        return answer
    }

    func startUpdates(_ onFix: @escaping @MainActor @Sendable (LocationFix) -> Void) {
        isUpdating = true
        self.onFix = onFix
    }

    func stopUpdates() {
        isUpdating = false
        onFix = nil
    }

    func send(_ fix: LocationFix) {
        onFix?(fix)
    }
}

/// The schedule side of a ride in tests: one plan, and a live status a test can change.
actor FakeRideData: RideDataProviding {
    let plan: RidePlan?
    private var status = RideStatus.none

    init(plan: RidePlan?) {
        self.plan = plan
    }

    func setStatus(_ value: RideStatus) { status = value }

    func ridePlan(for ride: Ride) async throws -> RidePlan? { plan }
    func rideStatus(for ride: Ride) async -> RideStatus { status }
}

/// The train feed in tests (TT-179 stands in later).
actor FakeTrainPositions: TrainPositionProviding {
    private var position: TrainPosition?

    func set(_ value: TrainPosition?) { position = value }

    func position(of trip: TripKey) async -> TrainPosition? { position }
}

/// Notification Center in nudge tests (TT-173): records every add and removal, and keeps what iOS would hold pending, where
/// an add replaces the pending notification with its id.
@MainActor
final class FakeRideNotifications: RideNotificationScheduling {
    private(set) var added: [RideNotification] = []
    private(set) var removed: [String] = []
    private(set) var pending: [String: RideNotification] = [:]

    func add(_ notification: RideNotification) {
        added.append(notification)
        pending[notification.id] = notification
    }

    func remove(ids: [String]) {
        removed += ids
        for id in ids { pending[id] = nil }
    }

    /// How many times every pending ride notification was removed.
    private(set) var removedAll = 0

    func removeAll() {
        removedAll += 1
        pending = [:]
    }
}

/// The taps and the chime in nudge tests: counts each.
@MainActor
final class FakeArrivalFeedback: ArrivalFeedback {
    private(set) var arrivals = 0
    private(set) var stops = 0

    func arriving() { arrivals += 1 }
    func atYourStop() { stops += 1 }
}
