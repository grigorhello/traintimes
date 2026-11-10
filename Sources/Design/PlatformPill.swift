import SwiftUI

/// The platform slot's placeholder (TT-162, D55): a skeleton pill the size of a digit, shown on the next train's card while
/// its platform is not published yet. It pulses like a loading card; static with Reduce Motion, and in snapshots.
struct PlatformPill: View {
    static let width: CGFloat = 18
    static let height: CGFloat = 11

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Off in snapshot tests, so the image is stable.
    @Environment(\.skeletonPulses) private var pulses
    @State private var dimmed = false

    var body: some View {
        Capsule()
            .fill(TTColor.inkTertiary.opacity(0.28))
            .frame(width: Self.width, height: Self.height)
            .opacity(dimmed ? 0.4 : 1)
            // The pill's bottom sits on the text baseline, as a digit does.
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            .onAppear {
                guard pulses, !reduceMotion else { return }
                // One fade out and back takes 1.6 s.
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dimmed = true }
            }
    }
}
