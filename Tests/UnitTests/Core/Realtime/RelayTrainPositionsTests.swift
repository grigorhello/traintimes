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
        let noTime = await positions.position(of: key("20261109-LW-1015"))
        XCTAssertEqual(noTime?.reportedAt, Date(timeIntervalSince1970: 1_762_689_600), "the feed's time stands in")
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
}
