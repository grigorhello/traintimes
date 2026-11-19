import Foundation

/// Station names as the station picker searches them and the widgets write them (TT-183), shared by the app and the widget
/// extension.
enum StationNames {
    /// The name, or the name from any word on, starts with `prefix` (case and accent insensitive, D54): "oak" and "uni" find
    /// Oakville GO and Union Station GO, "st" finds Union Station GO too.
    static func matches(_ name: String, prefix: String) -> Bool {
        var start = name.startIndex
        while start < name.endIndex {
            let rest = name[start...]
            if rest.range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil { return true }
            guard let separator = rest.firstIndex(where: { $0 == " " || $0 == "-" }) else { return false }
            start = name.index(after: separator)
        }
        return false
    }

    /// The name a widget has room for: "Oakville GO" is "Oakville", "Union Station GO" and "Union Station" are "Union".
    static func short(_ name: String) -> String {
        var short = name
        for suffix in [" GO", " Station"] where short.hasSuffix(suffix) && short.count > suffix.count {
            short = String(short.dropLast(suffix.count))
        }
        return short
    }
}
