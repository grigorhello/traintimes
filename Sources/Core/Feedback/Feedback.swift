import Foundation

/// What a rider sends from the feedback sheet (TT-202, D85).
enum FeedbackKind: String, CaseIterable, Codable, Sendable {
    case feedback
    case question
}

/// One message, as `POST /v1/feedback` takes it. Nothing personal beyond the optional reply email: the app version, the
/// iPhone model and the iOS version come along so a report can be matched to a build.
struct FeedbackMessage: Codable, Equatable, Sendable {
    static let maxLength = 2000

    var kind: FeedbackKind
    var message: String
    var email: String?
    var appVersion: String
    var device: String
    var osVersion: String
}

/// Where a message goes: the alert server in the app, a fixture in previews and tests.
protocol FeedbackSending: Sendable {
    func send(_ message: FeedbackMessage) async throws
}

/// The alert server at alerts.traintimes.ca (D38), which stores the message in its database.
struct HTTPFeedbackSender: FeedbackSending {
    var baseURL = HTTPAlertServer.production
    var session: URLSession = .shared

    func send(_ message: FeedbackMessage) async throws {
        let (_, response) = try await session.data(for: request(message))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AlertServerError.status(status) }
    }

    /// The request `send` makes; tests check it against the server's API.
    func request(_ message: FeedbackMessage) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "v1/feedback"), timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(message)
        return request
    }
}

/// Previews, the unit test host and UI tests: succeeds after a short wait, and never reaches the network.
struct FixtureFeedbackSender: FeedbackSending {
    var delay: Duration = .milliseconds(400)

    func send(_ message: FeedbackMessage) async throws {
        try await Task.sleep(for: delay)
    }
}

/// The app version, the iPhone model identifier ("iPhone18,1") and the iOS version, attached to every message.
struct FeedbackContext: Equatable, Sendable {
    var appVersion: String
    var device: String
    var osVersion: String

    static var current: FeedbackContext {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return FeedbackContext(
            appVersion: build.isEmpty ? version : "\(version) (\(build))",
            device: modelIdentifier,
            osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        )
    }

    /// `utsname.machine`; the simulator reports the Mac's, so it reads the simulated model from the environment.
    private static var modelIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
