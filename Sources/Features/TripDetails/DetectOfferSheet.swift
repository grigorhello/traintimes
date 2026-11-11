import SwiftUI

/// The offer after the first completed ride (TT-176, *Live-Always*): "Notice your train by itself", three points, where the
/// switch lives, Turn on and Not now. It has the first ride's permission sheet's shape (`RideIntroSheet`, TT-172). Turn on
/// leads to the iOS "also when you are not using the app" dialog; the sheet closes once it is answered. Shown once.
struct DetectOfferSheet: View {
    var onTurnOn: () -> Void = {}
    var onNotNow: () -> Void = {}

    static let height: CGFloat = 668

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                OutlinePin()
                    .frame(width: 34, height: 34)
                    .foregroundStyle(TTColor.accent)
                    .frame(width: 64, height: 64)
                    .background(TTColor.accentSoft, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.bottom, TTSpace.s2)
                    .accessibilityHidden(true)
                Text("loc.always.title")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(TTColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("loc.always.body")
                    .font(TTFont.subhead)
                    .foregroundStyle(TTColor.inkSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, TTSpace.s2)
            .padding(.top, TTSpace.s1)
            .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: TTSpace.s3) {
                point("tram.fill", RideIntroSheet.bold(String(localized: "loc.always.point.signal")))
                point("clock", RideIntroSheet.bold(String(localized: "loc.always.point.ios")))
                point("checkmark.circle.fill", RideIntroSheet.bold(String(localized: "loc.always.point.phone")))
            }
            .padding(.horizontal, TTSpace.s2)
            .padding(.top, TTSpace.s1)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("loc.always.note")
                .font(TTFont.footnote)
                .foregroundStyle(TTColor.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TTSpace.s2)

            Button(action: onTurnOn) {
                Text("loc.turnOn").frame(maxWidth: .infinity).frame(height: 52)
            }
            .buttonStyle(.ttGlassPrimary)
            .accessibilityIdentifier("detect.offer.turnOn")

            Button(action: onNotNow) {
                Text("loc.later").foregroundStyle(TTColor.inkSecondary)
            }
            .buttonStyle(.ttText)
            .accessibilityIdentifier("detect.offer.later")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TTSpace.s5)
        .padding(.top, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(TTColor.canvas)
        .accessibilityIdentifier("sheet.detectOffer")
        .presentationDetents([.height(Self.height)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(TTRadius.sheet)
        .presentationBackground(TTColor.canvas)
    }

    private func point(_ symbol: String, _ text: AttributedString) -> some View {
        HStack(alignment: .top, spacing: TTSpace.s3) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(TTColor.accent)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(TTFont.subhead)
                .foregroundStyle(TTColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
