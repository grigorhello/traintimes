import XCTest
@testable import TrainTimes

/// The requests match the alert server's API (server/src/api.ts, TT-140).
final class HTTPAlertServerTests: XCTestCase {
    func testRuleRequestMatchesTheServerAPI() throws {
        let server = HTTPAlertServer()
        let rule = AlertRule(id: "rule-1", kind: .thisTrip, trip: AlertFixtures.trip(), route: AlertFixtures.route)
        let request = try server.request("PUT", path: "v1/installations/abc/rules/\(rule.id)", body: rule)

        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.absoluteString, "https://alerts.traintimes.ca/v1/installations/abc/rules/rule-1")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["kind"] as? String, "trip")
        XCTAssertEqual(body["tripId"] as? String, "LW-0732-20261105")
        XCTAssertEqual(body["serviceDate"] as? String, "20261105")
        XCTAssertEqual(body["line"] as? String, "LW")
        XCTAssertEqual(body["scheduledDeparture"] as? String, "2026-11-05T12:32:00Z")
        XCTAssertEqual(body["origin"] as? [String: String], ["id": "OA", "name": "Oakville"])
        XCTAssertEqual(body["destination"] as? [String: String], ["id": "UN", "name": "Union"])
        XCTAssertEqual(body["weekdays"] as? [Int], [])
        XCTAssertEqual(body["paused"] as? Bool, false)
    }

    func testRegistrationAndDeleteRequests() throws {
        let server = HTTPAlertServer()
        let registration = InstallationRegistration(deviceToken: "ab", timeFormat: "12h", environment: "sandbox")
        let put = try server.request("PUT", path: "v1/installations/abc", body: registration)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(put.httpBody)) as? [String: String])
        XCTAssertEqual(body, ["deviceToken": "ab", "timeFormat": "12h", "environment": "sandbox"])

        let delete = try server.request("DELETE", path: "v1/installations/abc/rules/rule-1", body: nil as AlertRule?)
        XCTAssertEqual(delete.httpMethod, "DELETE")
        XCTAssertNil(delete.httpBody)
    }

    /// `GET …/rules` as the server answers it (server/src/api.ts `ruleJSON`, TT-143).
    func testRuleListReadsEachRulesState() throws {
        let server = HTTPAlertServer()
        let get = try server.request("GET", path: "v1/installations/abc/rules", body: nil as AlertRule?)
        XCTAssertEqual(get.httpMethod, "GET")
        XCTAssertEqual(get.url?.absoluteString, "https://alerts.traintimes.ca/v1/installations/abc/rules")
        XCTAssertNil(get.httpBody)

        let json = """
        {"rules": [
          {"id": "r1", "kind": "repeat", "tripId": "LW-0732-20261105", "serviceDate": "20261105", "line": "LW",
           "scheduledDeparture": "2026-11-05T12:32:00.000Z", "origin": {"id": "OA", "name": "Oakville"},
           "destination": {"id": "UN", "name": "Union"}, "weekdays": [1, 2, 3, 4, 5], "paused": false,
           "state": "reviewNeeded", "noMatchingTrainOn": null},
          {"id": "r2", "kind": "trip", "tripId": "LW-0758-20261105", "serviceDate": "20261105", "line": "LW",
           "scheduledDeparture": "2026-11-05T12:58:00.000Z", "origin": {"id": "OA", "name": "Oakville"},
           "destination": {"id": "UN", "name": "Union"}, "weekdays": [], "paused": true, "state": "on",
           "noMatchingTrainOn": "20261105"}
        ]}
        """
        let list = try JSONDecoder().decode(HTTPAlertServer.RuleList.self, from: Data(json.utf8))
        XCTAssertEqual(list.rules, [
            AlertRuleStatus(id: "r1", state: .reviewNeeded, noMatchingTrainOn: nil),
            AlertRuleStatus(id: "r2", state: .on, noMatchingTrainOn: "20261105"),
        ])
    }
}
