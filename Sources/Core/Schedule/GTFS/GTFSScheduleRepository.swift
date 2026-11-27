import Foundation

/// The schedule from GO Transit's published GTFS feed (TT-130, D35), with live status from its GTFS-realtime
/// TripUpdates feed (TT-131, D36) and line notices from its Alerts feed (TT-132, D37). With no live feeds (an app built
/// without the Metrolinx key) every trip is Scheduled and there are no notices. Neither feed carries platforms; those come
/// from GO's departures board for the route's origin (TT-225). GO's train feed says which trains stand at the origin
/// (TT-233, D114).
struct GTFSScheduleRepository: ScheduleRepository, StationRepository {
    /// A train is looked up in GO's train feed from this long before its scheduled departure (Union's trains stand at the
    /// platform up to half an hour before they leave) until this long after it (a late train).
    static let sightingLead: TimeInterval = 45 * 60
    static let sightingTail: TimeInterval = 90 * 60

    let store: GTFSFeedStore
    var live: GTFSRealtimeStore?
    var alerts: GTFSRealtimeStore?
    var platforms: PlatformStore?
    /// GO's train positions, for the trains at the route's origin (TT-233); nil without them, and every train then leaves
    /// by the clock.
    var trains: (any TrainPositionProviding)?
    /// Decides which notices are active, and which trains are near enough to their time to look up.
    var clock: any AppClock = SystemClock()

    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] {
        try await store.timetable().trips(from: route.from.id, to: route.to.id, on: day)
    }

    /// The feed's word on the route's trains that day. Its age is the producer's timestamp, never the time it was
    /// fetched, so a feed that stopped updating turns stale (D13). A failed fetch keeps the last good feed, as offline.
    /// The origin's platforms come with it (TT-225), fetched alongside; a board that fails leaves the dash. The pill waits
    /// (D55) only at a station whose board posts platforms. For the trains near their time it also says how far GO's train
    /// feed places each from the origin station, and which have dropped the origin from their update, so a card boards and
    /// departs with the train (TT-233, D114, `BoardingRule`); a train the feed does not carry gets neither.
    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot {
        guard let live else { return .empty }
        let platforms = platforms, origin = route.from.id
        async let fetchedBoard = platforms?.board(at: origin)
        let result = await live.latest()
        let board = await fetchedBoard
        guard let feed = result.feed, let fetchedAt = result.fetchedAt else {
            return LiveSnapshot(updatedAt: nil, isOffline: result.isOffline)
        }
        let updatedAt = min(feed.timestamp ?? fetchedAt, fetchedAt)
        let updates = feed.tripUpdates(on: day)
        var snapshot = LiveSnapshot(updatedAt: updatedAt, isOffline: result.isOffline, hasPlatformSource: board?.platforms.isEmpty == false)
        let timetable = try await store.timetable()
        // The saved route's stations carry no place; the timetable's do.
        let place = timetable.stations.first { $0.id == origin }?.place
        let now = clock.now
        for call in timetable.directCalls(from: route.from.id, to: route.to.id, on: day) {
            let update = updates[call.tripId]
            snapshot.updates[call.tripId] = update?.live(on: call, feedTime: updatedAt)
            snapshot.platforms[call.tripId] = board?.platform(forTrip: call.tripId)
            if update?.hasLeft(call) == true { snapshot.leftOrigin.insert(call.tripId) }
            let untilDeparture = call.departures[call.from].timeIntervalSince(now)
            // Offline the fixes are dropped anyway (`Departure.resolve`), so the train feed is not read: on a dead
            // connection its 10 s timeout would hold Offline back as long again.
            guard !result.isOffline, let trains, let place,
                  untilDeparture <= Self.sightingLead, untilDeparture >= -Self.sightingTail,
                  let position = await trains.position(of: TripKey(serviceDay: day, tripId: call.tripId)) else { continue }
            snapshot.originFixes[call.tripId] = OriginFix(
                metres: TrackShape.distance(position.coordinate, place), reportedAt: position.reportedAt
            )
        }
        return snapshot
    }

    /// The Alerts feed's notices for the line that are active now (D37). A failed fetch keeps the last good feed's.
    func lineNotices(for line: Line) async throws -> [LineNotice] {
        guard let alerts else { return [] }
        let result = await alerts.latest()
        guard let feed = result.feed, let fetchedAt = result.fetchedAt else { return [] }
        let routeCodes = try await store.timetable().routeCodes(ofLine: line.id)
        let feedTime = min(feed.timestamp ?? fetchedAt, fetchedAt)
        let now = clock.now
        return feed.alerts.compactMap { $0.lineNotice(for: line, routeCodes: routeCodes, now: now, feedTime: feedTime) }
    }

    /// The trip's stops with the live feed's estimate and skipped flag at each, where it gives them (D32).
    func stops(for trip: TripKey, on route: Route) async throws -> [TripStop] {
        let stops = try await store.timetable().stops(of: trip.tripId, from: route.from.id, to: route.to.id, on: trip.serviceDay)
        guard let feed = await live?.latest().feed, let update = feed.tripUpdates(on: trip.serviceDay)[trip.tripId] else {
            return stops
        }
        return update.applied(to: stops)
    }

    func lastServiceDay() async throws -> ServiceDay? {
        try await store.timetable().lastServiceDay
    }

    func stations() async throws -> [Station] {
        try await store.timetable().stations
    }

    func route(from: Station, to: Station) async throws -> Route {
        Route(from: from, to: to, line: try await store.timetable().line(between: from.id, and: to.id))
    }
}

extension GTFSScheduleRepository: RideDataProviding {
    func ridePlan(for ride: Ride) async throws -> RidePlan? {
        try await store.timetable().ridePlan(for: ride)
    }

    /// The trip's word in the TripUpdates feed (D36): cancelled, or late by your stop's own estimate, else by the last
    /// estimate before it, which carries on down the line as GTFS-realtime defines, else by the trip-wide delay.
    func rideStatus(for ride: Ride) async -> RideStatus {
        let day = ServiceDay(dateKey: ride.serviceDate)
        guard let feed = await live?.latest().feed, let update = feed.tripUpdates(on: day)[ride.tripId] else { return .none }
        if update.isCancelled { return RideStatus(isCancelled: true) }
        let stops = (try? await store.timetable().stops(of: ride.tripId, from: ride.originId, to: ride.destinationId, on: day)) ?? []
        let estimated = update.applied(to: stops).reversed().lazy.compactMap { stop in
            stop.expected.map { $0.timeIntervalSince(stop.scheduled) }
        }.first
        return RideStatus(delay: estimated ?? update.delay.map { TimeInterval($0) })
    }
}

extension GTFSScheduleRepository: RivalTrainsProviding {
    /// The other rail trips with a track leaving the ride's origin on its service day within `AutoRideRule.rivalWindow` of
    /// `departure` (TT-242, D120), each at the TripUpdates feed's expected departure there while the feed is fresh, else at
    /// its scheduled one (offline, stale, or no live store), as Schedule's cards read it. A trip the feed cancels or that
    /// skips the station stands beside no one there, so it is left out.
    func rivals(of ride: Ride, around departure: Date) async -> [RivalTrain] {
        guard let timetable = try? await store.timetable() else { return [] }
        let day = ServiceDay(dateKey: ride.serviceDate)
        let updates = await liveDepartures(from: ride.originId, on: day, timetable: timetable)
        return timetable.departures(from: ride.originId, on: day).compactMap { train in
            guard train.trip.tripId != ride.tripId, let shape = train.shape, let along = train.along else { return nil }
            let update = updates[train.trip.tripId]
            guard update?.isCancelled != true, update?.isStopSkipped != true else { return nil }
            let leaves = update?.expectedDeparture ?? train.departure
            guard abs(leaves.timeIntervalSince(departure)) <= AutoRideRule.rivalWindow else { return nil }
            return RivalTrain(trip: train.trip, departure: leaves, shape: shape, originAlong: along)
        }
    }

    /// The feed's word on each trip leaving the station that day, by trip id, read as `liveStatus` reads a route's
    /// origin; the expected departure only while the feed is fresh (`Freshness.isLive`). Empty with no feed.
    private func liveDepartures(from station: String, on day: ServiceDay, timetable: GTFSTimetable) async -> [String: LiveTripUpdate] {
        guard let live else { return [:] }
        let result = await live.latest()
        guard let feed = result.feed, let fetchedAt = result.fetchedAt else { return [:] }
        let updatedAt = min(feed.timestamp ?? fetchedAt, fetchedAt)
        let isFresh = Freshness(LiveSnapshot(updatedAt: updatedAt, isOffline: result.isOffline), now: clock.now).isLive
        let updates = feed.tripUpdates(on: day)
        var departures: [String: LiveTripUpdate] = [:]
        for call in timetable.departureCalls(from: station, on: day) {
            guard var update = updates[call.tripId]?.live(on: call, feedTime: updatedAt) else { continue }
            if !isFresh { update.expectedDeparture = nil }
            departures[call.tripId] = update
        }
        return departures
    }
}

extension GTFSScheduleRepository: WrongTrainTimetable, LiveStopsProviding {
    /// The trains a rider at `station` may take by mistake (TT-251, D127): `GTFSTimetable.candidates(leaving:on:)`.
    func candidates(leaving station: String, on day: ServiceDay) async -> [WrongTrainCandidate] {
        (try? await store.timetable().candidates(leaving: station, on: day)) ?? []
    }

    func trip(_ key: TripKey) async -> TimetableTrip? {
        try? await store.timetable().trip(id: key.tripId, on: key.serviceDay)
    }

    /// The line's stations in `GONetwork`'s order, Union first, with the timetable's places.
    func stations(onLine lineId: String) async -> [Station] {
        guard let line = GONetwork.line(lineId), let timetable = try? await store.timetable() else { return [] }
        let places = Dictionary(timetable.stations.map { ($0.id, $0.place) }, uniquingKeysWith: { first, _ in first })
        return ([GONetwork.union] + line.stations).map { station in
            var placed = station
            placed.place = places[station.id] ?? nil
            return placed
        }
    }

    /// The stops the TripUpdates feed still lists for the trip (D89), skipped ones apart, each at the feed's expected time
    /// (its time, else its delay on the timetable's), read as `liveStatus` reads a route: fresh while the feed is under
    /// 3 min old (`Freshness.isLive`). Nil with no feed or no update for the trip. No other API tells "left" from "no data"
    /// for any trip.
    func stopsAhead(of trip: TripKey) async -> LiveStopsAhead? {
        guard let live else { return nil }
        let result = await live.latest()
        guard let feed = result.feed, let fetchedAt = result.fetchedAt,
              let update = feed.tripUpdates(on: trip.serviceDay)[trip.tripId] else { return nil }
        let updatedAt = min(feed.timestamp ?? fetchedAt, fetchedAt)
        let isFresh = Freshness(LiveSnapshot(updatedAt: updatedAt, isOffline: result.isOffline), now: clock.now).isLive
        let scheduled = await self.trip(trip)?.stops ?? []
        var ahead = LiveStopsAhead(stops: [], isCancelled: update.isCancelled, isFresh: isFresh)
        for stop in update.stopTimeUpdates {
            guard let id = stop.stopId else { continue }
            if stop.relationship == .skipped {
                ahead.skipped.insert(id)
                continue
            }
            let timetable = scheduled.first { $0.station.id == id }
            let departs = Self.expected(stop.departure, scheduled: timetable?.departure)
            let time = departs ?? Self.expected(stop.arrival, scheduled: timetable?.arrival)
            ahead.stops.append(LiveStopsAhead.Stop(id: id, time: time))
        }
        return ahead
    }

    /// An event's time, else its delay on the scheduled time.
    private static func expected(_ event: GTFSRealtimeFeed.Event?, scheduled: Date?) -> Date? {
        guard let event else { return nil }
        if let time = event.time { return time }
        guard let delay = event.delay, let scheduled else { return nil }
        return scheduled.addingTimeInterval(TimeInterval(delay))
    }
}

/// Downloads the GO GTFS feed, imports its rail part and keeps the last good import on device, so the timetable works
/// offline (TT-130, D35). The first use waits for the download; after that the copy on device answers at once and is
/// refreshed in the background once it is a week old. A copy that no longer covers today waits for its refresh. A failed
/// refresh keeps the copy.
actor GTFSFeedStore {
    /// Metrolinx open data; public, no API key (Metrolinx Access and Use Agreement).
    static let feedURL = URL(string: "https://assets.metrolinx.com/raw/upload/Documents/Metrolinx/Open%20Data/GO-GTFS.zip")!
    static let refreshInterval: TimeInterval = 7 * 24 * 60 * 60
    /// A refresh that failed is not tried again for this long.
    static let retryInterval: TimeInterval = 60 * 60
    /// The same when the copy has run out, so a pull to refresh soon tries again.
    static let runOutRetryInterval: TimeInterval = 60
    static let shared = GTFSFeedStore(directory: .applicationSupportDirectory.appending(path: "GTFS", directoryHint: .isDirectory))

    typealias Download = @Sendable () async throws -> Data

    private let fileURL: URL
    private let clock: any AppClock
    private let download: Download
    private var current: GTFSTimetable?
    private var hasReadCopy = false
    private var refreshing: Task<GTFSTimetable, Error>?
    private var lastAttempt: Date?

    init(directory: URL, clock: any AppClock = SystemClock(), download: @escaping Download = { try await GTFSFeedStore.downloadFeed() }) {
        fileURL = directory.appending(path: "feed.json")
        self.clock = clock
        self.download = download
    }

    /// The timetable on device, refreshed when due; the first use downloads it.
    func timetable() async throws -> GTFSTimetable {
        if !hasReadCopy {
            hasReadCopy = true
            current = try? JSONDecoder().decode(GTFSFeed.self, from: Data(contentsOf: fileURL)).timetable
        }
        guard let current else { return try await refresh() }
        let now = clock.now
        guard Self.isDue(current, now: now) else { return current }
        // A copy that no longer covers today would show no trains, so its refresh is waited for (the copy if that
        // fails, as offline); a copy that is only a week old answers at once and is refreshed in the background.
        let expired = current.lastServiceDay.map { $0 < ServiceDay(containing: now) } ?? true
        if refreshing == nil {
            let retry = expired ? Self.runOutRetryInterval : Self.retryInterval
            guard lastAttempt.map({ now.timeIntervalSince($0) >= retry }) ?? true else { return current }
            lastAttempt = now
            guard expired else {
                Task { _ = try? await self.refresh() }
                return current
            }
        }
        guard expired else { return current }
        return (try? await refresh()) ?? current
    }

    /// Downloads and imports the feed, once however many callers ask at the same time, and keeps it on device.
    @discardableResult
    func refresh() async throws -> GTFSTimetable {
        if let refreshing { return try await refreshing.value }
        let task = Task.detached { [download, clock, fileURL] in
            let zip = try await download()
            let feed = try GTFSFeed(zip: zip, importedAt: clock.now)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Written whole or not at all, so a failed refresh leaves the last good copy.
            try JSONEncoder().encode(feed).write(to: fileURL, options: .atomic)
            return feed.timetable
        }
        refreshing = task
        defer { refreshing = nil }
        let timetable = try await task.value
        current = timetable
        // A new timetable rewrites the widget file (TT-182); posted on the main actor, where RootView listens.
        Task { @MainActor in NotificationCenter.default.post(name: .timetableImported, object: nil) }
        return timetable
    }

    /// A week old, the feed's last service day has passed, or a copy imported before TT-171, which has no track shapes for
    /// On board.
    static func isDue(_ timetable: GTFSTimetable, now: Date) -> Bool {
        guard timetable.feed.shapes != nil, let lastServiceDay = timetable.lastServiceDay, lastServiceDay >= ServiceDay(containing: now)
        else { return true }
        return now.timeIntervalSince(timetable.feed.importedAt) >= refreshInterval
    }

    static func downloadFeed() async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: feedURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}

private extension GTFSFeed {
    var timetable: GTFSTimetable { GTFSTimetable(feed: self) }
}

extension Notification.Name {
    /// `GTFSFeedStore` imported a new timetable (TT-182).
    static let timetableImported = Notification.Name("ca.traintimes.timetableImported")
}
