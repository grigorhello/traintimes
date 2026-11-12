import SwiftUI

/// The platform pill (TT-199, D82): the posted number in bold on a tinted pill, or a dash on a grey one while it is not
/// posted yet. One shape for every place that shows a platform; the app (`PlatformTag`, with its tokens) and the Live
/// Activity (its own dark palette) give it colours and a size, and put the "Platform" label before it.
struct PlatformBadge: View {
    struct Palette: Sendable {
        let numberInk: Color
        let numberFill: Color
        let dashInk: Color
        let dashFill: Color
    }

    /// "7"; nil draws the dash.
    let number: String?
    /// The number's point size; the pill (1.6 times as tall), the dash and the corners scale from it.
    var size: CGFloat = 17
    let palette: Palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.38, style: .continuous)
        ZStack {
            if let number {
                Text(verbatim: number)
                    .font(.system(size: size, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(palette.numberInk)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, size * 0.55)
            } else {
                Capsule()
                    .fill(palette.dashInk)
                    .frame(width: size, height: max(2, size * 0.15))
            }
        }
        .frame(minWidth: size * 2.45)
        .frame(height: size * 1.6)
        .background(number == nil ? palette.dashFill : palette.numberFill, in: shape)
    }
}
