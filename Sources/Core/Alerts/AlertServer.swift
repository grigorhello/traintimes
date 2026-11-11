import Foundation

/// What the app registers for its installation (TT-140): the APNs device token, the Time format resolved to 12h or 24h
/// so notifications show times as the app does (D17), and the APNs environment; and the Live Activity push-to-start token
/// once iOS issues it (iOS 17.2+, TT-178), left out until then.
struct InstallationRegistration: Codable, Hashable, Sendable {
    let deviceToken: String
    let timeFormat: String
    let environment: String
    var startToken: String?
}

/// A before-departure Live Activity the app knows of (TT-178, D74): it started it, iOS gave it an update token, or the ride
/// took it over. The server then starts no other for that train, sends its updates and end to the token, and stops once
/// handed off.
struct LiveActivityReport: Codable, Hashable, Sendable {
    let tripId: String
    /// GTFS form, "20261109".
    let serviceDate: String
    let originId: String
    let destinationId: String
    var token: String?
    var handedOff = false
}

/// The alert server's app API (TT-140, D38), keyed by the anonymous installation id (D5).
protocol AlertServer: Sendable {
    func register(_ registration: InstallationRegistration, installation: String) async throws
    func save(_ rule: AlertRule, installation: String) async throws
    func delete(ruleId: String, installation: String) async throws
    /// What the server says about each stored rule: Review needed, and the last day with no matching train (TT-143).
    func rules(installation: String) async throws -> [AlertRuleStatus]
    /// A before-departure Live Activity's start, update token or hand-off (TT-178).
    func report(_ activity: LiveActivityReport, installation: String) async throws
}

/// What the Live Activity tells the alert server (TT-178): `AlertRules`, which registers the installation.
@MainActor
protocol LiveActivityReporting: AnyObject {
    /// iOS issued the push-to-start token; it goes with the registration.
    func reportStartToken(_ token: String) async
    func report(_ activity: LiveActivityReport) async
}

extension AlertServer {
    /// Fixture servers keep nothing of Live Activities.
    func report(_ activity: LiveActivityReport, installation: String) async throws {}
}

enum AlertServerError: Error, Equatable {
    /// 404 on a rule: the server does not know the installation, so the app registers again.
    case unknownInstallation
    case status(Int)
}

/// The deployed Worker at alerts.traintimes.ca. Until it is deployed every call fails, and a rule ends in Could not save.
struct HTTPAlertServer: AlertServer {
    static let production = URL(string: "https://alerts.traintimes.ca")!

    var baseURL = HTTPAlertServer.production
    var session: URLSession = .shared

    func register(_ registration: InstallationRegistration, installation: String) async throws {
        try await send("PUT", path: "v1/installations/\(installation)", body: registration)
    }

    func save(_ rule: AlertRule, installation: String) async throws {
        try await send("PUT", path: "v1/installations/\(installation)/rules/\(rule.id)", body: rule)
    }

    func delete(ruleId: String, installation: String) async throws {
        try await send("DELETE", path: "v1/installations/\(installation)/rules/\(ruleId)", body: nil as AlertRule?)
    }

    func rules(installation: String) async throws -> [AlertRuleStatus] {
        let data = try await send("GET", path: "v1/installations/\(installation)/rules", body: nil as AlertRule?)
        return try JSONDecoder().decode(RuleList.self, from: data).rules
    }

    func report(_ activity: LiveActivityReport, installation: String) async throws {
        try await send("PUT", path: "v1/installations/\(installation)/activities", body: activity)
    }

    /// The `GET …/rules` body: `{"rules": [...]}`, each rule with its state.
    struct RuleList: Decodable {
        let rules: [AlertRuleStatus]
    }

    /// The request a call sends; tests check it against the server's API.
    func request(_ method: String, path: String, body: (some Encodable)?) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path), timeoutInterval: 10)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
        }
        return request
    }

    @discardableResult
    private func send(_ method: String, path: String, body: (some Encodable)?) async throws -> Data {
        let (data, response) = try await session.data(for: request(method, path: path, body: body))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw status == 404 ? AlertServerError.unknownInstallation : AlertServerError.status(status)
        }
        return data
    }

    /// Dates as ISO 8601, which the server parses (`scheduledDeparture`).
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

/// Stands in for the server in Xcode previews, the unit test host and UI tests (`TT_FIXTURES`): every call succeeds
/// after a short wait, so Setting up shows before On.
struct FixtureAlertServer: AlertServer {
    var delay: Duration = .milliseconds(400)

    func register(_ registration: InstallationRegistration, installation: String) async throws {}

    func save(_ rule: AlertRule, installation: String) async throws {
        try await Task.sleep(for: delay)
    }

    func delete(ruleId: String, installation: String) async throws {}

    /// Nothing to review: every rule stays as the app saved it.
    func rules(installation: String) async throws -> [AlertRuleStatus] { [] }
}
