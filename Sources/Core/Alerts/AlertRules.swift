import Foundation
import Observation

/// The rider's alert rules (TT-141): kept on device and saved on the alert server under the anonymous installation id
/// (D5, D38). The bell (TT-141), the alert setup sheet (TT-142), the Alerts tab (TT-143) and the watched-trip strip
/// (TT-144) share one instance.
///
/// One alert per train card (TT-189, D70): `alert(for:on:)`, the alert that covers a train on its day, is the one lookup the
/// bell, Trip details, the watched-trip strip and Live mode read. Repeat saved for a train with a one-day alert changes that
/// alert under its id, and a one-day alert that a switched-on repeating alert also covers is merged away (at launch and
/// after each save).
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
    /// Alerts whose change went back on device after a failed save, to be sent again in their saved version (TT-191).
    static let pendingSavesKey = "alerts.pendingSaves"

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
    @ObservationIgnored private var pendingSaves: [String]

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
        pendingSaves = defaults?.stringArray(forKey: Self.pendingSavesKey) ?? []
        let stored = (defaults?.data(forKey: Self.rulesKey)).flatMap { try? JSONDecoder().decode([Stored].self, from: $0) } ?? []
        rules = stored.map(\.rule)
        for item in stored {
            // A save cut short by the app quitting never reached On.
            serverStates[item.rule.id] = item.state == .settingUp ? .couldNotSave : item.state
        }
        // Doubles kept by an older build go now; the server hears with the next call.
        mergeDoubles()
    }

    /// The rule's state in words. On needs notifications allowed; otherwise it reads Notifications off.
    func state(of rule: AlertRule) -> AlertRuleState {
        let state = serverStates[rule.id] ?? .couldNotSave
        if state == .on, let permission, permission != .allowed { return .notificationsOff }
        return state
    }

    /// Alerts switched on and still in force on `today` (paused ones and past This-trip ones do not count): the number the
    /// notifications-off warning speaks of (TT-169).
    func switchedOnCount(on today: ServiceDay) -> Int {
        rules.filter { !$0.paused && $0.isCurrent(on: today) }.count
    }

    /// A rule the server set to Review needed: its usual train has changed (the Alerts tab dot, TT-143).
    var needsReview: Bool {
        rules.contains { state(of: $0) == .reviewNeeded }
    }

    /// The server found no matching train for this Repeat rule on that service day (rule 8): "No matching train today".
    func hasNoMatchingTrain(_ rule: AlertRule, on day: ServiceDay) -> Bool {
        noTrainDates[rule.id] == String(day.dateKey)
    }

    /// The one lookup (TT-189, D70): the alert that covers this train on its day between the route's stations, a This-trip
    /// alert for it or a Repeat alert for its usual train on one of its days. A card has one alert; while an older build's
    /// double is still stored, the alert that works wins (switched on and saved), then the switched-on one, then the
    /// repeating one.
    func alert(for trip: Trip, on route: Route) -> AlertRule? {
        rules.filter { $0.covers(trip, on: route) }.min { rank($0) < rank($1) }
    }

    /// The repeating alert for this train's usual train, whichever days it has: a bell on a day it leaves out adds that day
    /// to it rather than making a second alert (TT-189).
    func usualAlert(for trip: Trip, on route: Route) -> AlertRule? {
        rules.first { $0.isUsualTrain(of: trip, on: route) }
    }

    /// The watched-trip strip's question (TT-144, D39) and the filled bell's: the train's alert is switched on and On.
    func isWatched(_ trip: Trip, on route: Route) -> Bool {
        guard let rule = alert(for: trip, on: route) else { return false }
        return !rule.paused && state(of: rule) == .on
    }

    /// Trip details' "Manage alert" and its bell: the train has an alert that is switched on, whatever its saved state.
    func isAlerted(_ trip: Trip, on route: Route) -> Bool {
        alert(for: trip, on: route).map { !$0.paused } ?? false
    }

    /// The stored alert a candidate is saved over, so enabling it again updates that alert: the one-day alert for the same
    /// train; for Repeat, the repeating alert of the same usual train (line, stations and scheduled time of day), else the
    /// one-day alert for the candidate's own train, so Repeat changes that alert under its id (TT-189). A one-day candidate
    /// never takes over a repeating alert's days; on a day one covers it is merged away after the save.
    func matching(_ candidate: AlertRule) -> AlertRule? {
        let oneDay = rules.first { $0.kind == .thisTrip && $0.covers(trainOf: candidate) }
        guard candidate.kind == .repeating else { return oneDay }
        return rules.first { $0.kind == .repeating && $0.isSameUsualTrain(as: candidate) } ?? oneDay
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
    /// A stored rule's id updates that rule; a new one for a card that has an alert updates that alert (`matching`). A save
    /// already in flight for the rule sends nothing more. Doubles it leaves are merged away afterwards (TT-189).
    func save(_ candidate: AlertRule) async {
        var rule = candidate
        rule.id = storedID(of: candidate)
        guard !inFlight.contains(rule.id) else { return }
        inFlight.insert(rule.id)
        await send(rule)
        inFlight.remove(rule.id)
        if mergeDoubles() { await retryPendingDeletes() }
    }

    /// Saves a change from the bell or its capsule with nothing half-kept (TT-191, D71). When the server cannot take it, a
    /// stored alert goes back to what was saved (its last version and state) and a new one goes away, deleted on the server
    /// with the next call in case it got there. A removed alert saved again (Undo) takes back its pending delete. False
    /// when the change went back; a save already in flight for the alert sends nothing more and counts as kept.
    @discardableResult
    func commit(_ candidate: AlertRule) async -> Bool {
        let id = storedID(of: candidate)
        let previous = rules.first { $0.id == id }
        let previousState = serverStates[id]
        if previous == nil { pendingDeletes.removeAll { $0 == id } }
        await save(candidate)
        guard contains(id), serverStates[id] == .couldNotSave, !inFlight.contains(id) else { return true }
        if let previous, let index = rules.firstIndex(where: { $0.id == id }) {
            rules[index] = previous
            serverStates[id] = previousState ?? .couldNotSave
            // The failed save may have reached the server with its answer lost: send the saved version again with the
            // next call, so the server ends with what the rider sees.
            if !pendingSaves.contains(id) { pendingSaves.append(id) }
        } else {
            rules.removeAll { $0.id == id }
            serverStates[id] = nil
            pendingDeletes.append(id)
        }
        persist()
        return false
    }

    /// The id a candidate is saved under: its own when stored, else that of the alert it is saved over (`matching`).
    private func storedID(of candidate: AlertRule) -> AlertRule.ID {
        guard !contains(candidate.id), let existing = matching(candidate) else { return candidate.id }
        return existing.id
    }

    private func send(_ rule: AlertRule) async {
        upsert(rule, state: .settingUp)
        await refreshPermission()
        await retryPendingDeletes()
        await retryPendingSaves()
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
            pendingSaves.removeAll { $0 == rule.id }
            set(.on, for: rule.id)
        } catch {
            if contains(rule.id) { set(.couldNotSave, for: rule.id) }
        }
    }

    /// Reads the permission again and what the server says about each rule (TT-143): Review needed once the usual train
    /// has changed, back to On once a save cleared it, and the last day with no matching train. A rule being saved keeps
    /// its state, and so does one that could not be saved, since the server still has its old version and Try again
    /// must stay offered. An unreachable server changes nothing. Called on coming to the foreground and on the Alerts tab.
    func refresh() async {
        await refreshPermission()
        // A delete the server missed is sent again even when no rule is left, so a deleted alert stops (TT-153).
        await retryPendingDeletes()
        await retryPendingSaves()
        guard !rules.isEmpty else { return }
        let statuses: [AlertRuleStatus]
        do {
            statuses = try await server.rules(installation: installation)
        } catch AlertServerError.unknownInstallation {
            // The server dropped this installation (APNs reported its token gone): register again and save each rule
            // again, so none reads On while nothing watches it (TT-153). A rule merged away or deleted meanwhile is skipped,
            // so the loop never puts it back (TT-189).
            registered = nil
            for rule in rules where contains(rule.id) && !inFlight.contains(rule.id) { await save(rule) }
            return
        } catch {
            return
        }
        var dates = noTrainDates
        for status in statuses where contains(status.id) && !inFlight.contains(status.id) && serverStates[status.id] != .couldNotSave {
            let state: AlertRuleState = status.state == .reviewNeeded ? .reviewNeeded : .on
            if serverStates[status.id] != state { set(state, for: status.id) }
            dates[status.id] = status.noMatchingTrainOn
        }
        if dates != noTrainDates { noTrainDates = dates }
        // The token and Time format reach the server once per launch and whenever either changed (a restored backup, a
        // TestFlight build over a Debug one, Settings › Time format), not only with the next save (TT-153). Last, so a
        // slow push token never holds up the states above.
        try? await registerIfNeeded()
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
        removeOnDevice(id)
        await deleteOnServer(id)
    }

    /// The same delete, gone on device before it returns, with the server's part left running: the bell's capsule and
    /// its Undo answer at once, and Undo waits for the returned task so its save lands after the delete (TT-191).
    func deleteInBackground(_ id: AlertRule.ID) -> Task<Void, Never> {
        removeOnDevice(id)
        return Task { await deleteOnServer(id) }
    }

    private func removeOnDevice(_ id: AlertRule.ID) {
        rules.removeAll { $0.id == id }
        pendingSaves.removeAll { $0 == id }
        serverStates[id] = nil
        noTrainDates[id] = nil
        persist()
    }

    private func deleteOnServer(_ id: AlertRule.ID) async {
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

    /// Which of two alerts on one card wins (`alert(for:on:)`): the one that works, then the switched-on one, then Repeat.
    private func rank(_ rule: AlertRule) -> (Int, Int) {
        let works = !rule.paused && serverStates[rule.id] == .on
        return (works ? 0 : rule.paused ? 2 : 1, rule.kind == .repeating ? 0 : 1)
    }

    /// Merges doubles (TT-189): a one-day alert whose train a repeating alert also covers, while that one is switched on and
    /// saved, alerts nothing more, so it goes on device at once and on the server with the next call. Rules being saved are
    /// left alone. True when one went.
    @discardableResult
    private func mergeDoubles() -> Bool {
        let covering = rules.filter { $0.kind == .repeating && !$0.paused && serverStates[$0.id] == .on }
        let doubles = rules.filter { rule in
            rule.kind == .thisTrip && !inFlight.contains(rule.id) && covering.contains { $0.covers(trainOf: rule) }
        }
        guard !doubles.isEmpty else { return false }
        let ids = Set(doubles.map(\.id))
        rules.removeAll { ids.contains($0.id) }
        for id in ids {
            serverStates[id] = nil
            noTrainDates[id] = nil
        }
        pendingDeletes.append(contentsOf: doubles.map(\.id))
        persist()
        return true
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

    /// Sends again each alert whose change went back on device (`commit`), as it is on device now; one being saved is left
    /// to that save, and one removed meanwhile is dropped. Stops at the first failure (TT-191).
    private func retryPendingSaves() async {
        for id in pendingSaves {
            guard let rule = rules.first(where: { $0.id == id }) else {
                pendingSaves.removeAll { $0 == id }
                persist()
                continue
            }
            guard !inFlight.contains(id) else { continue }
            guard (try? await server.save(rule, installation: installation)) != nil else { return }
            guard contains(id) else {
                // Deleted while it was sent: delete it again, in case the delete reached the server first.
                try? await server.delete(ruleId: id, installation: installation)
                continue
            }
            guard rules.first(where: { $0.id == id }) == rule, !inFlight.contains(id) else {
                // Changed or being saved meanwhile: kept, so the next call sends the version on device last.
                if !pendingSaves.contains(id) { pendingSaves.append(id) }
                persist()
                continue
            }
            pendingSaves.removeAll { $0 == id }
            persist()
        }
    }

    private func persist() {
        guard let defaults else { return }
        let stored = rules.map { Stored(rule: $0, state: serverStates[$0.id] ?? .couldNotSave) }
        defaults.set(try? JSONEncoder().encode(stored), forKey: Self.rulesKey)
        defaults.set(pendingDeletes, forKey: Self.pendingDeletesKey)
        defaults.set(pendingSaves, forKey: Self.pendingSavesKey)
    }
}
