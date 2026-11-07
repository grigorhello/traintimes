import SwiftUI

/// One day in the 7-day strip.
struct DayCell: View {
    let weekday: String
    let day: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(weekday).font(TTFont.subhead)
                Text(day).font(TTFont.headline).monospacedDigit()
            }
            .foregroundStyle(isSelected ? TTColor.onAccent : TTColor.ink)
            .frame(minWidth: TTSize.dayCell, minHeight: TTSize.targetMin + TTSpace.s2)
            .background(isSelected ? TTColor.accent : TTColor.surface, in: RoundedRectangle(cornerRadius: TTRadius.sm))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Weekday chip in an alert's Repeat rule.
struct DayChip: View {
    let letter: String
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(letter)
                .font(TTFont.body)
                .foregroundStyle(isOn ? TTColor.onAccent : TTColor.ink)
                .frame(width: TTSize.targetMin + TTSpace.s1, height: TTSize.targetMin + TTSpace.s1)
                .background(isOn ? TTColor.accent : .clear, in: Circle())
                .overlay(Circle().strokeBorder(isOn ? .clear : TTColor.controlBorder, lineWidth: 1))
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
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(TTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: TTRadius.sm))
        .animation(.easeOut(duration: 0.2), value: selection)
    }
}

#Preview("Controls") { ControlsGallery() }
#Preview("Controls dark") { ControlsGallery().preferredColorScheme(.dark) }
