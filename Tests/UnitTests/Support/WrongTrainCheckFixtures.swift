import Foundation
import XCTest
@testable import TrainTimes

/// The warning's presenter in check tests (TT-251): records each raise and withdrawal; `answer()` stands in for the rider.
@MainActor
final class RecordingPresenter: WrongTrainRaising {
    private(set) var warning: WrongTrainWarning?
    private(set) var raised: [WrongTrainWarning] = []
    private(set) var withdrawals = 0

    func raise(_ warning: WrongTrainWarning, now: Date, rate: Double) -> Task<Void, Never>? {
        guard self.warning == nil else { return nil }
        self.warning = warning
        raised.append(warning)
        return Task {}
    }

    func withdraw() {
        guard warning != nil else { return }
        warning = nil
        withdrawals += 1
    }

    /// The rider answered, or the warning ran out.
    func answer() {
        warning = nil
    }
}

/// The timetable's side of the check in tests: fixed candidates, trips and line stations.
actor FakeWrongTimetable: WrongTrainTimetable {
    private let candidates: [WrongTrainCandidate]
    private let trips: [TripKey: TimetableTrip]
    private let stations: [Station]

    init(candidates: [WrongTrainCandidate], trips: [TimetableTrip] = [], stations: [Station] = WrongWorld.line) {
        self.candidates = candidates
        self.trips = Dictionary(trips.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        self.stations = stations
    }

    func candidates(leaving station: String, on day: ServiceDay) async -> [WrongTrainCandidate] { candidates }
    func trip(_ key: TripKey) async -> TimetableTrip? { trips[key] }
    func stations(onLine lineId: String) async -> [Station] { stations }
}

/// The live feed's stops ahead in tests, set per trip id.
actor FakeLiveStops: LiveStopsProviding {
    private var stops: [String: LiveStopsAhead] = [:]

    func set(_ tripId: String, _ live: LiveStopsAhead?) { stops[tripId] = live }
    func stopsAhead(of trip: TripKey) async -> LiveStopsAhead? { stops[trip.tripId] }
}

/// GO's position history in tests: the last four timed positions per trip, and how often each form was read.
actor FakePositionHistory: TrainPositionHistoryProviding {
    private var history = TrainPositionHistory()
    private(set) var reads = 0
    private(set) var fastReads = 0

    func add(_ tripId: String, _ position: TrainPosition, readAt: Date) {
        let read = ReadPosition(position: position, readAt: readAt)
        if position.hasVehicleTime { history.timed[tripId] = Array(((history.timed[tripId] ?? []) + [read]).suffix(4)) }
        history.latest[tripId] = read
    }

    func positions(on day: ServiceDay, fast: Bool) async -> TrainPositionHistory {
        reads += 1
        if fast { fastReads += 1 }
        return history
    }
}

/// The wrong train check on `WrongWorld` (O to D on the eastbound T, L at 5:30 PM), with a clock in seconds after L, the
/// shared fake location and fakes for the rest. The check looks only when a test calls `look()` (or `play`).
@MainActor
final class CheckRig {
    let clock: TestClock
    let location = FakeLocation(authorized: true)
    let presenter = RecordingPresenter()
    let stops = FakeLiveStops()
    let positions = FakePositionHistory()
    let defaults = UserDefaults.ephemeral()
    let plan: RidePlan
    let ride: Ride
    let candidates: [String: WrongTrainCandidate]
    var autoRideOff = false
    var testing = false
    var rideRunning = false
    var declined: Set<TripKey> = []
    var alerted: [AutoRideTrain] = []
    private(set) var alertedReads = 0
    private(set) var check: WrongTrainCheck!

    init(at seconds: Double = -600, origin: String = "O", candidates: [WrongTrainCandidate], trips: [TimetableTrip] = []) {
        plan = WrongWorld.plan(origin: origin)
        ride = WrongWorld.ride(origin: origin)
        self.candidates = Dictionary(candidates.map { ($0.trip.tripId, $0) }, uniquingKeysWith: { first, _ in first })
        clock = TestClock(now: WrongWorld.departure.addingTimeInterval(seconds))
        check = WrongTrainCheck(
            presenter: presenter, location: location,
            timetable: FakeWrongTimetable(candidates: candidates, trips: trips + candidates.map(Self.trip)),
            liveStops: stops, positions: positions, clock: clock, store: WrongTrainStore(defaults: defaults),
            lookInterval: nil,
            alertedTrains: { [weak self] _ in
                self?.alertedReads += 1
                return self?.alerted ?? []
            },
            rideRuns: { [weak self] in self?.rideRunning ?? false },
            isDeclined: { [weak self] in self?.declined.contains($0) ?? false },
            autoRideOff: { [weak self] in self?.autoRideOff ?? false },
            isTesting: { [weak self] in self?.testing ?? false },
            reportsStationary: true
        )
    }

    /// A candidate's timetable trip: O, then its stops after O, 5 min apart.
    static func trip(_ candidate: WrongTrainCandidate) -> TimetableTrip {
        let ids = ["O"] + candidate.stopsAfter
        let stops = ids.enumerated().map { index, id in
            TimetableTrip.Stop(
                station: Station(id: id, name: id + " GO"),
                arrival: candidate.departure.addingTimeInterval(Double(index) * 300),
                departure: candidate.departure.addingTimeInterval(Double(index) * 300)
            )
        }
        return TimetableTrip(key: candidate.trip, lineId: candidate.lineId, stops: stops, track: nil)
    }

    func time(_ seconds: Double) -> Date { WrongWorld.departure.addingTimeInterval(seconds) }
    func at(_ seconds: Double) { clock.set(time(seconds)) }

    /// The point `metres` from O along trip `id`'s track (T's for "T"), `north` metres north of it.
    func point(_ id: String, _ metres: Double, north: Double = 0) -> GeoPoint {
        let shape: TrackShape, along: Double
        if let candidate = candidates[id] {
            shape = candidate.shape
            along = candidate.originAlong
        } else {
            shape = plan.track!.shape
            along = plan.track!.stopDistances[0]
        }
        var point = shape.point(at: along + metres)
        point.latitude += north / 111_195.08
        return point
    }

    /// A fix from the phone, as the watch's or the engine's `fixTap` hands it over.
    func phone(at point: GeoPoint, stationary: Bool = false) {
        check.receive(LocationFix(coordinate: point, horizontalAccuracy: 8, isStationary: stationary, age: 0))
    }

    /// GO's timed position of trip `id` reported at `seconds`, read now.
    func train(_ id: String, reported seconds: Double, at point: GeoPoint) async {
        await positions.add(id, TrainPosition(coordinate: point, reportedAt: time(seconds), hasVehicleTime: true), readAt: clock.now)
    }

    /// The live feed's stops ahead for trip `id`, 5 min apart from L.
    func stops(_ id: String, _ list: [String], cancelled: Bool = false) async {
        let ahead = list.enumerated().map { index, stop in
            LiveStopsAhead.Stop(id: stop, time: WrongWorld.departure.addingTimeInterval(Double(index + 1) * 300))
        }
        await stops.set(id, LiveStopsAhead(stops: ahead, isCancelled: cancelled, isFresh: true))
    }

    /// The watch armed on T at the clock's moment; waits for the check to open.
    func armWatch() async {
        check.watchArmed(ride, plan: plan, departure: WrongWorld.departure, reader: location)
        await settle()
    }

    /// Plays the seconds `from` to `to`: a fix each second where `phone` gives one, each train's position every 30 s
    /// (reported on the half minute after L, read 40 s later) where `trains` gives one, and a look every 15 s. Stops when
    /// `until` holds or the check closes.
    func play(
        from: Int, to: Int, phone: (Double) -> GeoPoint?, trains: [String: (Double) -> GeoPoint?] = [:],
        until: () -> Bool = { false }
    ) async {
        for second in from...to {
            let s = Double(second)
            at(s)
            if let point = phone(s) { self.phone(at: point) }
            let reported = s - 40
            if Int(reported) % 30 == 0 {
                for (id, place) in trains.sorted(by: { $0.key < $1.key }) {
                    if let point = place(reported) { await train(id, reported: reported, at: point) }
                }
            }
            if second % 15 == 0 { await check.look() }
            if until() || check.checked == nil { return }
        }
    }

    /// Lets the check's tasks run (its opening reads the fakes).
    func settle() async {
        for _ in 0..<200 {
            await Task.yield()
            if check.checked != nil { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    /// A train leaving O at `start` seconds after L along trip `id`'s track: the phone or its positions.
    func leaving(_ id: String, at start: Double) -> (Double) -> GeoPoint {
        { [unowned self] in self.point(id, WrongWorld.moving($0, from: start)) }
    }
}
