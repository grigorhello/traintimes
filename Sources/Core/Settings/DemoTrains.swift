import Foundation

/// Settings › Testing › Demo trains (D49), for TestFlight builds. Raw values are what the setting stores on device.
enum DemoTrains: String, CaseIterable, Sendable {
    case off
    /// Made-up live status on the real timetable: the next train late, one cancelled, the rest on time, plus a line notice.
    case delays
    /// The cached timetable as if there were no connection.
    case offline
    /// The next train leaves in 8 min and its platform is not posted yet, on a feed that posts platforms: the card's
    /// pulsing placeholder (TT-162, D55).
    case awaitingPlatform
    /// A ride on board from Union to Clarkson, 5:32 to 5:43 PM, six times as fast, on its own clock (TT-172, D63,
    /// `DemoRide`): the ride strip on Schedule opens it. The timetable stays as it is.
    case ride
    /// The last 17 minutes before the 5:13 PM train leaves Union, with an alert on it, ten times as fast and over again, on
    /// its own clock (TT-177, D69, `DemoDeparture`): the countdown strip on Schedule opens it, and "I’m on board" hands over
    /// into the demo ride. The timetable stays as it is.
    case departure

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
