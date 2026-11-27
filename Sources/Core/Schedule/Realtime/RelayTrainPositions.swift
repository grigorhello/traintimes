import Foundation

/// Where GO's train feed (GTFS-realtime VehiclePosition) places each train, from the alert server's `GET /v1/trains`
/// (TT-179, D88): the ride's second source after 60 s without a fix ("Live · GO train data", D60) and train detection's
/// feed (D68). One fetch per 20 s is shared by every trip asked about; a failed fetch gives no positions until the next.
///
/// The wrong train check (TT-251, D127) also reads every train's last timed positions (`positions(on:fast:)`): the last
/// four per trip with when each was read, kept across a failed fetch; while the phone moves it asks for the fast form, a
/// copy of GO's feed at most 15 s old (`?fresh=15`, `server/src/relay.ts`), reused for 10 s.
actor RelayTrainPositions: TrainPositionProviding, TrainPositionHistoryProviding {
    static let url = HTTPAlertServer.production.appending(path: "v1/trains")
    static let fastURL = url.appending(queryItems: [URLQueryItem(name: "fresh", value: "15")])
    /// The app's one instance, so the ride and train detection share each fetch.
    static let shared = RelayTrainPositions()
    /// A fetch this recent is reused.
    static let reuseInterval: TimeInterval = 20
    /// The fast form's reuse.
    static let fastReuseInterval: TimeInterval = 10
    /// Timed positions kept per trip.
    static let historyCount = 4
    /// A trip with no new position for this long leaves the history.
    static let historyKeeps: TimeInterval = 10 * 60

    typealias Download = @Sendable () async throws -> Data

    /// The server's JSON: times in seconds since 1970.
    private struct Body: Decodable {
        struct Train: Decodable {
            let tripId: String
            let startDate: String?
            let latitude: Double
            let longitude: Double
            let timestamp: Double?
        }
        let timestamp: Double?
        let trains: [Train]
    }

    private let clock: any AppClock
    private let download: Download
    private let fastDownload: Download
    /// The last fetch's trains by trip id, with their GTFS start date.
    private var trains: [String: (startDate: Int?, position: TrainPosition)] = [:]
    /// Each trip's last timed positions, oldest first, and its latest position of any kind, with when they were read.
    private var history: [String: (startDate: Int?, positions: [ReadPosition])] = [:]
    private var latest: [String: (startDate: Int?, position: ReadPosition)] = [:]
    private var lastAttempt: Date?
    private var fetching: Task<[String: (startDate: Int?, position: TrainPosition)], Error>?

    /// `download` reads `/v1/trains`, `fastDownload` its fast form; a test that passes only `download` gets it for both.
    init(clock: any AppClock = SystemClock(), download: Download? = nil, fastDownload: Download? = nil) {
        self.clock = clock
        self.download = download ?? { try await Self.get(Self.url) }
        self.fastDownload = fastDownload ?? download ?? { try await Self.get(Self.fastURL) }
    }

    private static func get(_ url: URL) async throws -> Data {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    func position(of trip: TripKey) async -> TrainPosition? {
        await refreshIfDue()
        guard let train = trains[trip.tripId] else { return nil }
        if let startDate = train.startDate, startDate != trip.serviceDay.dateKey { return nil }
        return train.position
    }

    /// Every trip's last timed positions and latest position on `day` (TT-251, D127).
    func positions(on day: ServiceDay, fast: Bool) async -> TrainPositionHistory {
        await refreshIfDue(fast: fast)
        var result = TrainPositionHistory()
        for (trip, entry) in history where entry.startDate.map({ $0 == day.dateKey }) ?? true {
            result.timed[trip] = entry.positions
        }
        for (trip, entry) in latest where entry.startDate.map({ $0 == day.dateKey }) ?? true {
            result.latest[trip] = entry.position
        }
        return result
    }

    private func refreshIfDue(fast: Bool = false) async {
        let now = clock.now
        let reuse = fast ? Self.fastReuseInterval : Self.reuseInterval
        if fetching == nil, let lastAttempt, now.timeIntervalSince(lastAttempt) < reuse { return }
        lastAttempt = now
        do {
            trains = try await fetch(fast: fast)
            record(trains, readAt: now)
        } catch {
            // The history stays: a failed fetch says nothing about where the trains were.
            trains = [:]
        }
    }

    /// Adds a fetch's positions to the history. The actor is re-entrant across the fetch, so two callers can record the
    /// same fetch: a position is told by its vehicle's time.
    private func record(_ trains: [String: (startDate: Int?, position: TrainPosition)], readAt: Date) {
        for (trip, train) in trains {
            latest[trip] = (train.startDate, ReadPosition(position: train.position, readAt: readAt))
            guard train.position.hasVehicleTime else { continue }
            var positions = history[trip]?.positions ?? []
            guard !positions.contains(where: { $0.position.reportedAt == train.position.reportedAt }) else { continue }
            positions.append(ReadPosition(position: train.position, readAt: readAt))
            positions.sort { $0.position.reportedAt < $1.position.reportedAt }
            history[trip] = (train.startDate, Array(positions.suffix(Self.historyCount)))
        }
        history = history.filter { readAt.timeIntervalSince($0.value.positions.last?.readAt ?? .distantPast) <= Self.historyKeeps }
        latest = latest.filter { readAt.timeIntervalSince($0.value.position.readAt) <= Self.historyKeeps }
    }

    /// One download however many trips are asked about at the same time.
    private func fetch(fast: Bool) async throws -> [String: (startDate: Int?, position: TrainPosition)] {
        if let fetching { return try await fetching.value }
        let download = fast ? fastDownload : download
        let task = Task.detached { [download] in
            let data = try await download()
            let body = try JSONDecoder().decode(Body.self, from: data)
            let feedTime = body.timestamp ?? 0
            var trains: [String: (startDate: Int?, position: TrainPosition)] = [:]
            for train in body.trains {
                // A train with no time of its own takes the feed's (TT-242, D120: an automatic start never counts it).
                let reportedAt = Date(timeIntervalSince1970: train.timestamp ?? feedTime)
                let position = TrainPosition(
                    coordinate: GeoPoint(latitude: train.latitude, longitude: train.longitude), reportedAt: reportedAt,
                    hasVehicleTime: train.timestamp != nil
                )
                trains[train.tripId] = (train.startDate.flatMap(Int.init), position)
            }
            return trains
        }
        fetching = task
        defer { fetching = nil }
        return try await task.value
    }
}
