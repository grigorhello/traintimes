import Foundation

/// The line notices the rider dismissed, by notice id, kept on device so a dismissed notice stays hidden after a
/// relaunch until a notice with a new id arrives (TT-132, D37).
@MainActor
final class DismissedNotices {
    /// A string array, so UI tests can clear it with `-notices.dismissed ""`.
    static let key = "notices.dismissed"
    /// The newest ids kept; notices end, so older ids no longer matter.
    static let limit = 50

    private var ids: [String]
    /// Nil keeps the list in memory only (previews, and tests that do not check it).
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        ids = defaults?.stringArray(forKey: Self.key) ?? []
    }

    func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    func dismiss(_ id: String) {
        guard !contains(id) else { return }
        ids = Array((ids + [id]).suffix(Self.limit))
        defaults?.set(ids, forKey: Self.key)
    }
}
