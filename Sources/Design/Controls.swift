import SwiftUI

/// One day in the day strip (D49): a 60 × 48 pt tile, weekday over date. Selected is solid accent; Today, while another day
/// is selected, turns accent with a semibold label. Solid surface, never glass.
struct DayCell: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let weekday: String
    let day: String
    var isSelected = false
    /// Today's tile; it only shows when the tile is not the selected one.
    var isToday = false
    /// False where the strip draws the selected day's accent tile itself, under the tiles, so that it can glide from day
    /// to day (TT-164, D61): the selected tile is then see-through.
    var drawsSelection = true
    let action: () -> Void

    /// Canvas `.gday`.
    static let size = CGSize(width: 60, height: 48)
    /// The tile turning, at once to the eye, but as an animation, so that it turns in the same frame as the accent's glide
    /// starts (TT-164): a slow frame after the tap (the new trains being built) then still shows the old selection, where
    /// a tile turned straight away covered the accent that had not moved yet and left no day selected.
    private static let turn = Animation.linear(duration: 0.01)

    private var showsToday: Bool { isToday && !isSelected }

    private var fill: Color {
        guard isSelected else { return TTColor.surface }
        return drawsSelection ? TTColor.accent : .clear
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(weekday)
                    .font(showsToday ? TTFont.footnote.weight(.semibold) : TTFont.footnote)
                    .foregroundStyle(isSelected ? TTColor.onAccent : showsToday ? TTColor.accent : TTColor.inkSecondary)
                Text(day)
                    .font(TTFont.headline)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? TTColor.onAccent : showsToday ? TTColor.accent : TTColor.ink)
            }
            // Only the text cross-fades when the selection moves; the tile turns at once, as on the Motion board, so a
            // half-faded tile never shows the gliding accent through it (TT-164).
            .animation(.easeOut(duration: 0.2), value: isSelected)
            .frame(width: Self.size.width, height: Self.size.height)
            .background(fill, in: RoundedRectangle(cornerRadius: TTRadius.md))
            .shadow(color: .black.opacity(colorScheme == .dark || isSelected ? 0 : 0.06), radius: 1, x: 0, y: 1)
            // Reduce Motion: the accent jumps, so the tile turns with it at once.
            .animation(reduceMotion ? nil : Self.turn, value: isSelected)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Controls") { ControlsGallery() }
#Preview("Controls dark") { ControlsGallery().preferredColorScheme(.dark) }
