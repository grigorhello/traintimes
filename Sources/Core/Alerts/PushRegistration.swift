import UIKit

/// The APNs device token the alert server sends to (TT-141). iOS issues one whether or not notifications are allowed.
@MainActor
protocol PushRegistering {
    /// The token as hex, asking iOS to register for remote notifications on first use.
    func deviceToken() async throws -> String
}

/// The token from iOS. `AppDelegate` forwards the registration callbacks here.
@MainActor
final class SystemPushRegistration: PushRegistering {
    static let shared = SystemPushRegistration()

    private var token: String?
    private var waiting: [CheckedContinuation<String, any Error>] = []

    func deviceToken() async throws -> String {
        if let token { return token }
        return try await withCheckedThrowingContinuation { continuation in
            waiting.append(continuation)
            if waiting.count == 1 { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        token = hex
        resume(with: .success(hex))
    }

    /// Without the Push Notifications entitlement, or with no network, iOS reports a failure: the rule ends in Could not save.
    func didFail(_ error: any Error) {
        resume(with: .failure(error))
    }

    private func resume(with result: Result<String, any Error>) {
        let continuations = waiting
        waiting = []
        for continuation in continuations { continuation.resume(with: result) }
    }
}

/// A made-up token for previews, the unit test host and UI tests, which never register with APNs.
struct FixturePushRegistration: PushRegistering {
    func deviceToken() async throws -> String { String(repeating: "0", count: 64) }
}
