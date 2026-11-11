import Foundation
@testable import TrainTimes

extension UserDefaults {
    /// A fresh, empty suite, so tests never read or write the app's real settings.
    static func ephemeral() -> UserDefaults {
        let name = "TrainTimesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

/// A fixed notification permission in place of `UNUserNotificationCenter`.
struct FakeNotificationPermission: NotificationPermissionProviding {
    let value: NotificationPermission

    init(_ value: NotificationPermission) {
        self.value = value
    }

    func current() async -> NotificationPermission { value }
}

/// A permission a test changes, as the rider does in iOS Settings, whose dialog answers `answer` and counts each time it
/// is shown (TT-190).
actor SettableNotificationPermission: NotificationPermissionProviding {
    private var value: NotificationPermission
    private let answer: NotificationPermission
    private(set) var requests = 0

    init(_ value: NotificationPermission, answer: NotificationPermission = .off) {
        self.value = value
        self.answer = answer
    }

    func set(_ value: NotificationPermission) {
        self.value = value
    }

    func current() -> NotificationPermission { value }

    func request() -> NotificationPermission {
        requests += 1
        if value == .notAsked { value = answer }
        return value
    }
}

/// A clock a test moves forward by hand, for the Schedule minute tick.
/// `@unchecked Sendable` is safe: `value` is only read and written while holding `lock`.
final class TestClock: AppClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(now: Date) {
        value = now
    }

    var now: Date { lock.withLock { value } }

    func advance(minutes: Int) {
        advance(seconds: TimeInterval(minutes * 60))
    }

    func advance(seconds: TimeInterval) {
        lock.withLock { value = value.addingTimeInterval(seconds) }
    }

    func set(_ date: Date) {
        lock.withLock { value = date }
    }
}

/// The alert server in alert tests: records every call, can fail, and can hold a rule's save until the test releases it.
actor FakeAlertServer: AlertServer {
    private(set) var registrations: [InstallationRegistration] = []
    private(set) var saved: [AlertRule] = []
    private(set) var deleted: [String] = []
    /// What `GET …/rules` answers (TT-143).
    private(set) var statuses: [AlertRuleStatus] = []
    /// Live Activity reports (TT-178).
    private(set) var activityReports: [LiveActivityReport] = []
    private var failing = false
    private var holding = false
    private var holdingDeletes = false
    private var unknownInstallationOnce = false
    private var held: [CheckedContinuation<Void, Never>] = []

    var isHolding: Bool { !held.isEmpty }

    func setFailing(_ value: Bool) { failing = value }
    func setStatuses(_ value: [AlertRuleStatus]) { statuses = value }
    func holdSaves() { holding = true }
    func holdDeletes() { holdingDeletes = true }
    func answerUnknownInstallationOnce() { unknownInstallationOnce = true }

    func release() {
        holding = false
        holdingDeletes = false
        held.forEach { $0.resume() }
        held = []
    }

    func register(_ registration: InstallationRegistration, installation: String) async throws {
        if failing { throw URLError(.cannotFindHost) }
        registrations.append(registration)
    }

    func save(_ rule: AlertRule, installation: String) async throws {
        if holding { await withCheckedContinuation { held.append($0) } }
        if failing { throw URLError(.cannotFindHost) }
        if unknownInstallationOnce {
            unknownInstallationOnce = false
            throw AlertServerError.unknownInstallation
        }
        saved.append(rule)
    }

    func delete(ruleId: String, installation: String) async throws {
        if holdingDeletes { await withCheckedContinuation { held.append($0) } }
        if failing { throw URLError(.cannotFindHost) }
        deleted.append(ruleId)
    }

    func rules(installation: String) async throws -> [AlertRuleStatus] {
        if failing { throw URLError(.cannotFindHost) }
        if unknownInstallationOnce {
            unknownInstallationOnce = false
            throw AlertServerError.unknownInstallation
        }
        return statuses
    }

    func report(_ activity: LiveActivityReport, installation: String) async throws {
        if failing { throw URLError(.cannotFindHost) }
        if unknownInstallationOnce {
            unknownInstallationOnce = false
            throw AlertServerError.unknownInstallation
        }
        activityReports.append(activity)
    }

    /// Waits until a save or a delete is held.
    func waitUntilHolding() async {
        while held.isEmpty { await Task.yield() }
    }
}

/// Alert test values: the 7:32 AM train from Oakville to Union on Thu Nov 5 (the fixture route).
enum AlertFixtures {
    static let route = Route(
        from: Station(id: "OA", name: "Oakville"), to: Station(id: "UN", name: "Union"),
        line: Line(id: "LW", name: "Lakeshore West", colorHex: nil)
    )

    static func trip(_ id: String = "LW-0732-20261105", day: Int = 5, departure: String = "12:32") -> Trip {
        Trip(
            key: TripKey(serviceDay: ServiceDay(year: 2026, month: 11, day: day), tripId: id),
            scheduledDeparture: try! Date(String(format: "2026-11-%02dT%@:00Z", day, departure), strategy: .iso8601),
            scheduledArrival: try! Date(String(format: "2026-11-%02dT13:12:00Z", day), strategy: .iso8601),
            platform: .pending,
            tags: []
        )
    }

    /// A route on the Lakeshore West line, "Union to Oakville".
    static func route(_ from: (String, String), _ to: (String, String)) -> Route {
        Route(from: Station(id: from.0, name: from.1), to: Station(id: to.0, name: to.1), line: Line(id: "LW", name: "Lakeshore West", colorHex: nil))
    }

    @MainActor
    static func rules(
        _ server: FakeAlertServer, permission: NotificationPermission = .allowed, settings: AppSettings? = nil,
        defaults: UserDefaults? = nil
    ) -> AlertRules {
        AlertRules(
            server: server, push: FixturePushRegistration(), permissions: FakeNotificationPermission(permission),
            settings: settings, defaults: defaults
        )
    }
}

/// Line notices without a Schedule view model, for the Alerts tab (TT-143).
@MainActor
final class FakeLineNotices: LineNoticesProviding {
    var todayNotices: [LineNotice]

    init(_ todayNotices: [LineNotice] = []) {
        self.todayNotices = todayNotices
    }
}
