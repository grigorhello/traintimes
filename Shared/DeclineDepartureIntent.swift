import ActivityKit
import AppIntents
import Foundation

/// No on the departure question (TT-231, D110): the Live Activity card's No button. It ends the card at once, without
/// opening the app, and hands the train to the app (`declined`), which keeps it as declined for today, counts the answer and
/// tells the alert server to send nothing more. Compiled by the app and the widget extension (the button needs the type);
/// iOS runs a `LiveActivityIntent` in the app's process, where `AppDelegate` sets `declined` at launch.
struct DeclineDepartureIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "detect.no"
    static let isDiscoverable = false

    @Parameter(title: "Trip") var tripId: String
    @Parameter(title: "Service date") var serviceDate: Int
    @Parameter(title: "From") var originId: String
    @Parameter(title: "To") var destinationId: String

    init() {}

    init(_ attributes: RideActivityAttributes) {
        tripId = attributes.tripId
        serviceDate = attributes.serviceDate
        originId = attributes.originId
        destinationId = attributes.destinationId
    }

    /// The app's handler: set by `AppDelegate` at launch; nil in the extension.
    @MainActor static var declined: (@MainActor (DeclinedDeparture) -> Void)?

    func perform() async throws -> some IntentResult {
        let train = DeclinedDeparture(tripId: tripId, serviceDate: serviceDate, originId: originId, destinationId: destinationId)
        for activity in Activity<RideActivityAttributes>.activities
        where activity.attributes.shows(
            tripId: train.tripId, serviceDate: train.serviceDate, originId: train.originId, destinationId: train.destinationId
        ) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        await MainActor.run { Self.declined?(train) }
        return .result()
    }
}

/// The train a No was about: the activity's identity.
struct DeclinedDeparture: Equatable, Sendable {
    let tripId: String
    let serviceDate: Int
    let originId: String
    let destinationId: String
}
