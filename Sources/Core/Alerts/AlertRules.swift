import Foundation
import Observation

/// The rider's alert rules (TT-141): kept on device and saved on the alert server under the anonymous installation id
/// (D5, D38). The bell (TT-141), the alert setup sheet (TT-142), the Alerts tab (TT-143) and the watched-trip strip
/// (TT-144) share one instance.
///
/// A rule shows On only once the server stored it and the device token is registered, and only while notifications are
/// allowed: with permission off it shows Notifications off, but is still saved, so allowing notifications later needs no
/// resync. A rule the server could not take stays on device as Could not save; saving it again retries with the same id.
@Observable @MainActor
final class AlertRules: WatchedTripsProviding {
    /// JSON, read once at launch, so UI tests can clear it with `-alerts.rules ""`.
    static let rulesKey = "alerts.rules"
    static let installationKey = "alerts.installation"
    /// Rules deleted while the server was unreachable, deleted there on the next call.
    static let pendingDeletesKey = "alerts.pendingDeletes"

    /// Debug builds get sandbox device tokens; TestFlight and the App Store get production ones.
    #if DEBUG
    static let apnsEnvironment = "sandbox"
    #else
    static let apnsEnvironment = "production"
    #endif

    /// Newest first.
    private(set) var rules: [AlertRule] = []
    /// The notification permission last read; nil until the first read.
    private(set) var permission: NotificationPermission?
    /// What the server said about each rule: Setting up while a save is in flight, then On or Could not save, or
    /// Review needed once the server finds the usual train changed (TT-143).
    private var serverStates: [AlertRule.ID: AlertRuleState] = [:]
    /// The last selected day with no matching train, by rule, as the server reported it ("20261105", rule 8).
    private var noTrainDates: [AlertRule.ID: String] = [:]

    /// The anonymous installation id (D5), a lowercase UUID kept on device.
    let installation: String
    private let server: any AlertServer
    private let push: any PushRegistering
    private let permissions: any NotificationPermissionProviding
    /// The Time format sent with the token, so notifications show times as the app does (D17).
    private let settings: AppSettings?
    /// Nil keeps everything in memory (previews and tests that do not check storage).
    private let defaults: UserDefaults?
    @ObservationIgnored private var registered: InstallationRegistration?
    @ObservationIgnored private var inFlight: Set<AlertRule.ID> = []
    @ObservationIgnored private var pendingDeletes: [String]

    init(
        server: any AlertServer, push: any PushRegistering, permissions: any NotificationPermissionProviding,
        settings: AppSettings? = nil, defaults: UserDefaults? = .standard
    ) {
        self.server = server
        self.push = push
        self.permissions = permissions
        self.settings = settings
        self.defaults = defaults
        let installation = defaults?.string(forKey: Self.installationKey) ?? UUID().uuidString.lowercased()
        defaults?.set(installation, forKey: Self.installationKey)
        self.installation = installation
        pendingDeletes = defaults?.stringArray(forKey: Self.pendingDeletesKey) ?? []
        let stored = (defaults?.data(forKey: Self.rulesKey)).flatMap { try? JSONDecoder().decode([Stored].self, from: $0) } ?? []
        rules = stored.map(\.rule)
        for item in stored {
            // A save cut short by the app quitting never reached On.
            serverStates[item.rule.id] = item.state == .settingUp ? .couldNotSave : item.state
        }
    }

    /// The rule's state in words. On needs notifications allowed; otherwise it reads Notifications off.
    func state(of rule: AlertRule) -> AlertRuleState {
        let state = serverStates[rule.id] ?? .couldNotSave
        if state == .on, let permission, permission != .allowed { return .notificationsOff }
        return state
    }

    /// A rule the server set to Review needed: its usual train has changed (the Alerts tab dot, TT-143).
    var needsReview: Bool {
        rules.contains { state(of: $0) == .reviewNeeded }
    }

    /// The server found no matching train for this Repeat rule on that service day (rule 8): "No matching train today".
    func hasNoMatchingTrain(_ rule: AlertRule, on day: ServiceDay) -> Bool {
        noTrainDates[rule.id] == String(day.dateKey)
    }

    /// The This-trip rule for a train between the route's stations.
    func thisTripRule(for trip: TripKey, on route: Route) -> AlertRule? {
        rules.first { $0.kind == .thisTrip && $0.trip == trip && $0.origin.id == route.from.id && $0.destination.id == route.to.id }
    }

    /// The watched-trip strip's question (TT-144, D39): a trip is watched while a This-trip rule for it is On, as the
    /// filled bell shows. A Repeat rule's usual train cannot be named by a trip id alone; TT-142 adds it with Repeat.
    func isWatched(_ trip: TripKey) -> Bool {
        rules.contains { $0.kind == .thisTrip && $0.trip == trip && state(of: $0) == .on }
    }

    /// The stored rule the candidate would duplicate: the same train for This trip, the same usual train for Repeat
    /// (line, stations and scheduled time of day), so enabling it again updates that rule.
    func matching(_ candidate: AlertRule) -> AlertRule? {
        rules.first { rule in
            guard rule.kind == candidate.kind else { return false }
            return switch rule.kind {
            case .thisTrip: rule.trip == candidate.trip && rule.origin.id == candidate.origin.id && rule.destination.id == candidate.destination.id
            case .repeating: rule.isSameUsualTrain(as: candidate)
            }
        }
    }

    /// Reads the permission again, on coming back to the foreground or before a save.
    func refreshPermission() async {
        let current = await permissions.current()
        if current != permission { permission = current }
    }

    /// Shows the iOS permission dialog if the rider has not been asked yet, then reads the answer. The alert setup sheet
    /// calls it on "Enable alerts" (TT-142), never before.
    func requestPermission() async {
        if await permissions.current() == .notAsked {
            _ = await permissions.request()
        }
        await refreshPermission()
    }

    /// Saves the rule on device and on the server: Setting up, then On (or Notifications off), or Could not save.
    /// A rule that duplicates a stored one updates it; a save already in flight for the rule sends nothing more.
    func save(_ candidate: AlertRule) async {
        var rule = candidate
        if let existing = matching(candidate) { rule.id = existing.id }
        guard !inFlight.contains(rule.id) else { return }
        inFlight.insert(rule.id)
        defer { inFlight.remove(rule.id) }
        upsert(rule, state: .settingUp)
        await refreshPermission()
        await retryPendingDeletes()
        do {
            try await registerIfNeeded()
            do {
                try await server.save(rule, installation: installation)
            } catch AlertServerError.unknownInstallation {
                registered = nil
                try await registerIfNeeded()
                try await server.save(rule, installation: installation)
            }
            guard contains(rule.id) else {
                // Deleted while it was saving: delete it again, in case the delete reached the server first.
                try? await server.delete(ruleId: rule.id, installation: installation)
                return
            }
            set(.on, for: rule.id)
        } catch {
            if contains(rule.id) { set(.couldNotSave, for: rule.id) }
        }
    }

    /// Reads the permission again and what the server says about each rule (TT-143): Review needed once the usual train
    /// has changed, back to On once a save cleared it, and the last day with no matching train. A rule being saved keeps
    /// its state, and an unreachable server changes nothing. Called on coming to the foreground and on the Alerts tab.
    func refresh() async {
        await refreshPermission()
        guard !rules.isEmpty else { return }
        await retryPendingDeletes()
        guard let statuses = try? await server.rules(installation: installation) else { return }
        var dates = noTrainDates
        for status in statuses where contains(status.id) && !inFlight.contains(status.id) {
            let state: AlertRuleState = status.state == .reviewNeeded ? .reviewNeeded : .on
            if serverStates[status.id] != state { set(state, for: status.id) }
            dates[status.id] = status.noMatchingTrainOn
        }
        if dates != noTrainDates { noTrainDates = dates }
    }

    /// Puts a deleted rule back where it was and saves it again with the same id, so the server has it again (the Alerts
    /// tab's Undo, TT-143).
    func restore(_ rule: AlertRule, at index: Int) async {
        if !contains(rule.id) {
            rules.insert(rule, at: min(max(index, 0), rules.count))
            pendingDeletes.removeAll { $0 == rule.id }
        }
        await save(rule)
    }

    /// Removes the rule on device at once and on the server; if the server cannot be reached, it is deleted there on the
    /// next call.
    func delete(_ id: AlertRule.ID) async {
        rules.removeAll { $0.id == id }
        serverStates[id] = nil
        noTrainDates[id] = nil
        persist()
        do {
            try await server.delete(ruleId: id, installation: installation)
        } catch {
            pendingDeletes.append(id)
            persist()
        }
    }

    // MARK: Private

    private struct Stored: Codable {
        let rule: AlertRule
        let state: AlertRuleState
    }

    private func contains(_ id: AlertRule.ID) -> Bool {
        rules.contains { $0.id == id }
    }

    private func upsert(_ rule: AlertRule, state: AlertRuleState) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.insert(rule, at: 0)
        }
        set(state, for: rule.id)
    }

    private func set(_ state: AlertRuleState, for id: AlertRule.ID) {
        serverStates[id] = state
        persist()
    }

    private func registerIfNeeded() async throws {
        let token = try await push.deviceToken()
        let twentyFourHour = settings?.timeFormatter.usesTwentyFourHour ?? false
        let registration = InstallationRegistration(
            deviceToken: token, timeFormat: twentyFourHour ? "24h" : "12h", environment: Self.apnsEnvironment
        )
        guard registration != registered else { return }
        try await server.register(registration, installation: installation)
        registered = registration
    }

    private func retryPendingDeletes() async {
        for id in pendingDeletes {
            guard (try? await server.delete(ruleId: id, installation: installation)) != nil else { return }
            pendingDeletes.removeAll { $0 == id }
            persist()
        }
    }

    private func persist() {
        guard let defaults else { return }
        let stored = rules.map { Stored(rule: $0, state: serverStates[$0.id] ?? .couldNotSave) }
        defaults.set(try? JSONEncoder().encode(stored), forKey: Self.rulesKey)
        defaults.set(pendingDeletes, forKey: Self.pendingDeletesKey)
    }
}
