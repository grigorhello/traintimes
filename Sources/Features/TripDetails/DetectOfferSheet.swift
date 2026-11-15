import SwiftUI

/// The offer after the first completed ride (TT-176, *Live-Always*; one straight ask since TT-205, D93, board 16): "Detect
/// my train next time?", one line, Turn on and Not now, in the first ride's sheet's shape (`PermissionAsk`). Turn on leads
/// to the iOS "also when you are not using the app" dialog; the sheet closes once it is answered. Shown once.
struct DetectOfferSheet: View {
    var onTurnOn: () -> Void = {}
    var onNotNow: () -> Void = {}

    static let height: CGFloat = PermissionAsk.height

    var body: some View {
        PermissionAsk(
            title: "loc.always.title", line: "loc.always.body", action: "loc.turnOn",
            actionID: "detect.offer.turnOn", laterID: "detect.offer.later",
            onAction: onTurnOn, onLater: onNotNow
        )
        .accessibilityIdentifier("sheet.detectOffer")
    }
}
