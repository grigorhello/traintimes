/// A GO line: its code ("LW"), its name and the feed's colour. In `Shared/` since TT-183, so the widgets draw its tile.
struct Line: Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    /// Hex colour from feed metadata ("#111827"); nil when the feed has none (the header then uses ink-secondary).
    let colorHex: String?
}
