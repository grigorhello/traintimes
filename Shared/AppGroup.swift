import Foundation

/// The App Group the app and the widget extension share (TT-181, D101): the app writes the widget file into its container
/// (TT-182) and the widgets read it. Both entitlements files list it.
enum AppGroup {
    static let identifier = "group.ca.traintimes.TrainTimes"

    /// The shared container, or nil when the build is not entitled to the group.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
