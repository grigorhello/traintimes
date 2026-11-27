import XCTest
@testable import TrainTimes

/// TT-179 (D88): train positions from the alert server's `GET /v1/trains`.
final class RelayTrainPositionsTests: XCTestCase {
    private let monday = ServiceDay(year: 2026, month: 11, day: 9)

    private let body = Data("""
    {"timestamp":1762689600,"trains":[
      {"tripId":"20261109-LW-1713","startDate":"20261109","latitude":43.4467,"longitude":-79.6668,"stopped":true,"timestamp":1762689590},
      {"tripId":"20261109-LW-1015","latitude":43.6,"longitude":-79.5,"stopped":false}
    ]}
    """.utf8)

    /// Counts downloads; `fails` makes the next ones throw.
    private actor Server {
        var calls = 0
        var fails = false
        let body: Data
        init(body: Data) { self.body = body }
        func setFails(_ value: Bool) { fails = value }
        func download() throws -> Data {
            calls += 1
            if fails { throw URLError(.badServerResponse) }
            return body
        }
    }

    private func key(_ trip: String, _ day: ServiceDay? = nil) -> TripKey {
        TripKey(serviceDay: day ?? monday, tripId: trip)
    }

    func testReadsEachTrainsPositionAndTime() async {
        let server = Server(body: body)
        let positions = RelayTrainPositions(clock: TestClock(now: .now), download: { try await server.download() })

        let train = await positions.position(of: key("20261109-LW-1713"))
        XCTAssertEqual(train?.coordinate, GeoPoint(latitude: 43.4467, longitude: -79.6668))
        XCTAssertEqual(train?.reportedAt, Date(timeIntervalSince1970: 1_762_689_590))
        XCTAssertEqual(train?.hasVehicleTime, true)
        let noTime = await positions.position(of: key("20261109-LW-1015"))
        XCTAssertEqual(noTime?.reportedAt, Date(timeIntervalSince1970: 1_762_689_600), "the feed's time stands in")
        XCTAssertEqual(noTime?.hasVehicleTime, false, "and says so, so an automatic start never counts it (TT-242)")
        let otherDay = await positions.position(of: key("20261109-LW-1713", ServiceDay(year: 2026, month: 11, day: 10)))
        XCTAssertNil(otherDay, "a start date of another service day is another train")
        let missing = await positions.position(of: key("20261109-LW-9999"))
        XCTAssertNil(missing)
        let calls = await server.calls
        XCTAssertEqual(calls, 1, "one fetch serves every trip")
    }

    func testFetchesAgainAfter20SecondsAndGivesNothingWhileFailing() async {
        let server = Server(body: body)
        let clock = TestClock(now: .now)
        let positions = RelayTrainPositions(clock: clock, download: { try await server.download() })

        _ = await positions.position(of: key("20261109-LW-1713"))
        clock.advance(seconds: 19)
        _ = await positions.position(of: key("20261109-LW-1713"))
        var calls = await server.calls
        XCTAssertEqual(calls, 1)

        await server.setFails(true)
        clock.advance(seconds: 1)
        let failed = await positions.position(of: key("20261109-LW-1713"))
        XCTAssertNil(failed)
        calls = await server.calls
        XCTAssertEqual(calls, 2)

        await server.setFails(false)
        clock.advance(seconds: 20)
        let back = await positions.position(of: key("20261109-LW-1713"))
        XCTAssertNotNil(back)
    }

    // MARK: The history (TT-251, D127)

    /// A body with train A at `time` (seconds after the feed's 1762689600) and train B with no time of its own.
    private func body(_ time: Double, latitude: Double = 43.44) -> Data {
        Data("""
        {"timestamp":\(1_762_689_600 + time),"trains":[
          {"tripId":"20261109-LW-1713","startDate":"20261109","latitude":\(latitude),"longitude":-79.66,"timestamp":\(1_762_689_600 + time)},
          {"tripId":"20261109-LW-1015","latitude":43.6,"longitude":-79.5}
        ]}
        """.utf8)
    }

    /// Serves the next body each call; `fails` makes the next ones throw. Counts the fast calls apart.
    private actor Feed {
        var bodies: [Data]
        var fails = false
        private(set) var calls = 0
        private(set) var fastCalls = 0
        init(_ bodies: [Data]) { self.bodies = bodies }
        func setFails(_ value: Bool) { fails = value }
        func download(fast: Bool) throws -> Data {
            calls += 1
            if fast { fastCalls += 1 }
            if fails { throw URLError(.badServerResponse) }
            return bodies.count > 1 ? bodies.removeFirst() : bodies[0]
        }
    }

    func testKeepsTheLastFourTimedPositionsOfEachTrainAcrossAFailedFetch() async {
        // Five fetches, the train's own time new in each but one.
        let feed = Feed([body(0), body(20), body(20), body(40), body(60), body(80)])
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_762_689_605))
        let positions = RelayTrainPositions(
            clock: clock, download: { try await feed.download(fast: false) }, fastDownload: { try await feed.download(fast: true) }
        )
        var history = TrainPositionHistory()
        for _ in 0..<6 {
            history = await positions.positions(on: monday, fast: false)
            clock.advance(seconds: 20)
        }
        let timed = history.timed["20261109-LW-1713"] ?? []
        XCTAssertEqual(timed.map(\.position.reportedAt.timeIntervalSince1970), [1_762_689_620, 1_762_689_640, 1_762_689_660, 1_762_689_680],
                       "the last four, a repeated vehicle time once")
        XCTAssertEqual(timed.last?.readAt, Date(timeIntervalSince1970: 1_762_689_605 + 100), "each stamped with when it was read")
        XCTAssertNil(history.timed["20261109-LW-1015"], "a position with no time of its own is not timed")
        XCTAssertEqual(history.latest["20261109-LW-1015"]?.position.hasVehicleTime, false, "but is the latest of any kind")

        await feed.setFails(true)
        history = await positions.positions(on: monday, fast: false)
        XCTAssertEqual(history.timed["20261109-LW-1713"]?.count, 4, "a failed fetch keeps the history")
        let gone = await positions.position(of: key("20261109-LW-1713"))
        XCTAssertNil(gone, "while one position still gives nothing, as before")
        let otherDay = await positions.positions(on: ServiceDay(year: 2026, month: 11, day: 10), fast: false)
        XCTAssertTrue(otherDay.timed.isEmpty, "a start date of another service day is another train")
    }

    func testTheFastFormIsReusedFor10Seconds() async {
        let feed = Feed([body(0)])
        let clock = TestClock(now: .now)
        let positions = RelayTrainPositions(
            clock: clock, download: { try await feed.download(fast: false) }, fastDownload: { try await feed.download(fast: true) }
        )
        _ = await positions.positions(on: monday, fast: true)
        clock.advance(seconds: 9)
        _ = await positions.positions(on: monday, fast: true)
        var fast = await feed.fastCalls
        XCTAssertEqual(fast, 1)
        clock.advance(seconds: 1)
        _ = await positions.positions(on: monday, fast: true)
        fast = await feed.fastCalls
        XCTAssertEqual(fast, 2, "10 s on, the fast form fetches again")
        clock.advance(seconds: 15)
        _ = await positions.position(of: key("20261109-LW-1713"))
        let calls = await feed.calls
        XCTAssertEqual(calls, 2, "the ordinary form reuses any fetch for 20 s")
        XCTAssertEqual(RelayTrainPositions.fastURL.query, "fresh=15")
    }
}
