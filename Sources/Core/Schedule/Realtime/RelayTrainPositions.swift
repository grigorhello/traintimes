import Foundation

/// Where GO's train feed (GTFS-realtime VehiclePosition) places each train, from the alert server's `GET /v1/trains`
/// (TT-179, D88): the ride's second source after 60 s without a fix ("Live · GO train data", D60) and train detection's
/// feed (D68). One fetch per 20 s is shared by every trip asked about; a failed fetch gives no positions until the next.
actor RelayTrainPositions: TrainPositionProviding {
    static let url = HTTPAlertServer.production.appending(path: "v1/trains")
    /// The app's one instance, so the ride and train detection share each fetch.
    static let shared = RelayTrainPositions()
    /// A fetch this recent is reused.
    static let reuseInterval: TimeInterval = 20

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
    /// The last fetch's trains by trip id, with their GTFS start date.
    private var trains: [String: (startDate: Int?, position: TrainPosition)] = [:]
    private var lastAttempt: Date?
    private var fetching: Task<[String: (startDate: Int?, position: TrainPosition)], Error>?

    init(clock: any AppClock = SystemClock(), download: Download? = nil) {
        self.clock = clock
        self.download = download ?? {
            let request = URLRequest(url: Self.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return data
        }
    }

    func position(of trip: TripKey) async -> TrainPosition? {
        await refreshIfDue()
        guard let train = trains[trip.tripId] else { return nil }
        if let startDate = train.startDate, startDate != trip.serviceDay.dateKey { return nil }
        return train.position
    }

    private func refreshIfDue() async {
        let now = clock.now
        if fetching == nil, let lastAttempt, now.timeIntervalSince(lastAttempt) < Self.reuseInterval { return }
        lastAttempt = now
        do {
            trains = try await fetch()
        } catch {
            trains = [:]
        }
    }

    /// One download however many trips are asked about at the same time.
    private func fetch() async throws -> [String: (startDate: Int?, position: TrainPosition)] {
        if let fetching { return try await fetching.value }
        let task = Task.detached { [download] in
            let body = try JSONDecoder().decode(Body.self, from: try await download())
            let feedTime = body.timestamp ?? 0
            var trains: [String: (startDate: Int?, position: TrainPosition)] = [:]
            for train in body.trains {
                let reportedAt = Date(timeIntervalSince1970: train.timestamp ?? feedTime)
                let position = TrainPosition(
                    coordinate: GeoPoint(latitude: train.latitude, longitude: train.longitude), reportedAt: reportedAt
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
