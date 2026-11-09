import Foundation

/// Settings › Testing › Demo trains (D49), for TestFlight builds. Raw values are what the setting stores on device.
enum DemoTrains: String, CaseIterable, Sendable {
    case off
    /// Made-up live status on the real timetable: the next train late, one cancelled, the rest on time, plus a line notice.
    case delays
    /// The cached timetable as if there were no connection.
    case offline

    static let key = "settings.demoTrains"

    /// The stored choice, read from the standard defaults, so the schedule can read it from any thread.
    static var stored: DemoTrains {
        UserDefaults.standard.string(forKey: key).flatMap(DemoTrains.init(rawValue:)) ?? .off
    }
}

/// Where the app was installed from. The Testing section of Settings, and so Demo trains, shows in TestFlight and Debug
/// builds only; the App Store build never has it (D49).
enum BuildChannel {
    /// TestFlight builds carry a sandbox receipt.
    static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    static var showsTesting: Bool {
        #if DEBUG
        return true
        #else
        return isTestFlight
        #endif
    }
}
