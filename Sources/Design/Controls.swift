import SwiftUI

/// One day in the day strip (D49): a 60 × 48 pt tile, weekday over date. Selected is solid accent; Today, while another day
/// is selected, turns accent with a semibold label. Solid surface, never glass.
struct DayCell: View {
    @Environment(\.colorScheme) private var colorScheme
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
            .frame(width: Self.size.width, height: Self.size.height)
            .background(fill, in: RoundedRectangle(cornerRadius: TTRadius.md))
            .shadow(color: .black.opacity(colorScheme == .dark || isSelected ? 0 : 0.06), radius: 1, x: 0, y: 1)
            // The text and the tile cross-fade when the selection moves.
            .animation(.easeOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Weekday chip in an alert's Repeat rule: a 44 pt circle, as the canvas's `.day` (seven fit the sheet's width).
struct DayChip: View {
    let letter: String
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(letter)
                .font(TTFont.body)
                .foregroundStyle(isOn ? TTColor.onAccent : TTColor.ink)
                .frame(width: TTSize.targetMin, height: TTSize.targetMin)
                .background(isOn ? TTColor.accent : .clear, in: Circle())
                .overlay(Circle().strokeBorder(isOn ? .clear : TTColor.controlBorder, lineWidth: 1))
                .contentShape(Circle())    // an unselected chip's clear fill takes no taps on its own (D45)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Two or more equal segments; the selected one sits on a raised surface.
struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: LocalizedStringKey)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(selected ? TTFont.headline : TTFont.body)
                        .foregroundStyle(TTColor.ink)
                        .frame(maxWidth: .infinity, minHeight: TTSize.targetMin - TTSpace.s1)
                        .background(selected ? TTColor.surface : .clear, in: RoundedRectangle(cornerRadius: TTRadius.sm - 2))
                        .padding(.vertical, 2)    // inside the button, so each segment takes taps over 44 pt (D45)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 2)
        .background(TTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: TTRadius.sm))
        .animation(.easeOut(duration: 0.2), value: selection)
    }
}

#Preview("Controls") { ControlsGallery() }
#Preview("Controls dark") { ControlsGallery().preferredColorScheme(.dark) }
