import SwiftUI

/// What the watched-trip strip shows (TT-144), times already formatted by the one formatter (D17).
struct WatchedTripStrip: Hashable, Identifiable {
    let id: TripKey
    /// "7:05 AM to Union": the scheduled departure, which stays the train's name (D9).
    let title: String
    /// "Departed · Est. arrival 7:46 AM", or the scheduled arrival when the feed gives no estimate (D15).
    let detail: String
}

/// The compact accent-soft strip above the timeline for a watched train that has left (`schedule-watched.png`, canvas
/// `.strip`): filled bell, the train and its arrival, chevron. A tap opens Trip details; a sideways swipe hides it.
struct WatchedTripStripView: View {
    let strip: WatchedTripStrip
    let onOpen: () -> Void
    let onDismiss: () -> Void
    @State private var dragOffset: CGFloat = 0

    /// A sideways drag past this hides the strip; a shorter one springs back.
    private static let dismissDistance: CGFloat = 80

    var body: some View {
        HStack(spacing: TTSpace.s3) {
            Image(systemName: "bell.fill")
                .font(.system(size: TTSize.iconButtonGlyph))
                .foregroundStyle(TTColor.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: strip.title)
                    .font(TTFont.headline)
                    .foregroundStyle(TTColor.ink)
                Text(verbatim: strip.detail)
                    .font(TTFont.footnote)
                    .foregroundStyle(TTColor.inkSecondary)
            }
            .monospacedDigit()
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: TTSize.iconSM, weight: .semibold))
                .foregroundStyle(TTColor.accent)
        }
        .padding(.vertical, TTSpace.s2 - TTSpace.s1 / 2)
        .padding(.horizontal, TTSpace.s3)
        .frame(minHeight: TTSize.targetMin)
        .background(TTColor.accentSoft, in: RoundedRectangle(cornerRadius: TTRadius.lg, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: TTRadius.lg, style: .continuous))
        .offset(x: dragOffset)
        .onTapGesture(perform: onOpen)
        .gesture(
            DragGesture(minimumDistance: TTSpace.s5)
                .onChanged { dragOffset = $0.translation.width }
                .onEnded { value in
                    if abs(value.translation.width) > Self.dismissDistance {
                        onDismiss()
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("schedule.watched")
    }
}
