import SwiftUI

/// What one option of a `GlassSwitch` shows.
enum GlassSwitchLabel {
    /// An SF Symbol (Appearance: automatic, sun, moon).
    case symbol(String)
    /// A word, in the digits-aligned 15 pt label ("Auto", "12h", "Delays").
    case text(LocalizedStringKey)
}

/// A choice between two to four options (TT-168, D57): a recessed track with one thumb that glides to the chosen option. Used
/// by Appearance (three symbols), Time format (three words) and Demo trains (four words) in Settings. The thumb is Liquid
/// Glass on iOS 26 and later, like the tab bar's pill, and a solid raised surface before it and when `\.rendersGlass` is off.
/// The chosen symbol or word is accent and semibold and presses in on a spring (`settingsPress`); the Appearance symbols
/// also turn a quarter. The track is 40 pt tall with 3 pt around the 34 pt thumb.
struct GlassSwitch<Value: Hashable>: View {
    struct Option {
        let value: Value
        let label: GlassSwitchLabel
        /// What VoiceOver reads, and what UI tests find ("Automatic", "Light", "Dark").
        let name: LocalizedStringKey
        let identifier: String
    }

    @Binding var selection: Value
    let options: [Option]
    /// One segment's width; nil fills the width it is given, in equal segments.
    var segmentWidth: CGFloat?
    /// The chosen symbol turns from -90° as it presses in (Appearance).
    var turns = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static var trackHeight: CGFloat { 40 }
    private static var inset: CGFloat { 3 }

    private var selectedIndex: Int { options.firstIndex { $0.value == selection } ?? 0 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { proxy in
                let segment = (proxy.size.width - 2 * Self.inset) / CGFloat(max(options.count, 1))
                SwitchThumb()
                    .frame(width: segment, height: Self.trackHeight - 2 * Self.inset)
                    .offset(x: Self.inset + CGFloat(selectedIndex) * segment, y: Self.inset)
                    .animation(reduceMotion ? .easeOut(duration: 0.2) : SettingsMotion.glide, value: selection)
            }
            HStack(spacing: 0) {
                ForEach(options.indices, id: \.self) { index in
                    segment(options[index])
                }
            }
            .padding(Self.inset)
        }
        .frame(width: segmentWidth.map { $0 * CGFloat(options.count) + 2 * Self.inset }, height: Self.trackHeight)
        .background(TTColor.surfaceRaised, in: Capsule())
    }

    private func segment(_ option: Option) -> some View {
        let isSelected = option.value == selection
        return Button {
            selection = option.value
        } label: {
            SwitchSegmentLabel(label: option.label, isSelected: isSelected, turns: turns)
                .frame(maxWidth: .infinity)
                .frame(height: Self.trackHeight - 2 * Self.inset)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(option.name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(option.identifier)
    }
}

/// The symbol or word of one option: accent and semibold while chosen, ink-secondary otherwise, pressing in when it becomes
/// the chosen one.
private struct SwitchSegmentLabel: View {
    let label: GlassSwitchLabel
    let isSelected: Bool
    let turns: Bool
    @State private var presses = 0

    var body: some View {
        content
            .foregroundStyle(isSelected ? TTColor.accent : TTColor.inkSecondary)
            .animation(.easeOut(duration: 0.2), value: isSelected)
            .settingsPress(trigger: presses, turns: turns)
            .onChange(of: isSelected) { _, nowSelected in
                if nowSelected { presses += 1 }
            }
    }

    @ViewBuilder private var content: some View {
        switch label {
        case .symbol(let name):
            Image(systemName: name).font(.system(size: 18, weight: isSelected ? .semibold : .medium))
        case .text(let key):
            Text(key).font(.system(size: 15, weight: isSelected ? .semibold : .medium)).monospacedDigit()
        }
    }
}

/// The thumb: Liquid Glass on iOS 26 and later; before it, and in snapshots (`\.rendersGlass` false), a solid surface lifted
/// by a soft shadow (white in light, the ink at 18 % in dark, on the raised track).
private struct SwitchThumb: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.rendersGlass) private var rendersGlass

    var body: some View {
        if #available(iOS 26, *), rendersGlass {
            Color.clear.glassEffect(.regular, in: Capsule())
        } else {
            Capsule()
                .fill(colorScheme == .dark ? TTColor.ink.opacity(0.18) : TTColor.surface)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.13), radius: 3.5, x: 0, y: 2)
        }
    }
}

#Preview("Glass switch") { GlassSwitchGallery() }
#Preview("Glass switch dark") { GlassSwitchGallery().preferredColorScheme(.dark) }

private struct GlassSwitchGallery: View {
    @State private var appearance = Appearance.system
    @State private var format = TimeFormat.twelveHour

    var body: some View {
        VStack(alignment: .leading, spacing: TTSpace.s5) {
            GlassSwitch(
                selection: $appearance,
                options: [
                    .init(value: .system, label: .symbol("circle.lefthalf.filled"), name: "settings.appearance.system", identifier: "system"),
                    .init(value: .light, label: .symbol("sun.max.fill"), name: "settings.appearance.light", identifier: "light"),
                    .init(value: .dark, label: .symbol("moon.fill"), name: "settings.appearance.dark", identifier: "dark"),
                ],
                segmentWidth: 46, turns: true
            )
            GlassSwitch(
                selection: $format,
                options: [
                    .init(value: .device, label: .text("settings.time_format.device"), name: "settings.time_format.device.name", identifier: "device"),
                    .init(value: .twelveHour, label: .text("settings.time_format.12h"), name: "settings.time_format.12h.name", identifier: "12h"),
                    .init(value: .twentyFourHour, label: .text("settings.time_format.24h"), name: "settings.time_format.24h.name", identifier: "24h"),
                ],
                segmentWidth: 52
            )
        }
        .padding(TTSpace.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TTColor.canvas)
    }
}
