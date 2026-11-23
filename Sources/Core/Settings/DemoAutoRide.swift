import Foundation

/// Settings › Testing › Demo trains › Depart › Automatic ride (TT-242, D120): with the demo departure playing, a demo watch
/// decides whether the phone left with the 5:16 PM train, on the demo's clock. Raw values are what the setting stores on
/// device (`-settings.demoAutoRide boards` in a launch argument).
enum DemoAutoRide: String, CaseIterable, Sendable {
    /// No demo watch: the question asks when the train leaves, as before.
    case off
    /// The phone leaves Union with the train: the ride starts by itself.
    case boards
    /// The phone stays at Union, still: not on board, so no ride starts.
    case stays
    /// No train positions: no ride starts, and after 3 min it cannot tell.
    case noFeed

    static let key = "settings.demoAutoRide"

    /// The stored choice, read from the standard defaults.
    static var stored: DemoAutoRide {
        UserDefaults.standard.string(forKey: key).flatMap(DemoAutoRide.init(rawValue:)) ?? .off
    }
}
