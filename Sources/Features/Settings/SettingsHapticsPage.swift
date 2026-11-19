import SwiftUI

/// Settings › Testing › Haptics (TT-214, D95; TestFlight and Debug builds): every feel to try on the phone, the app's moments
/// with their feel at their time (TT-215, D100: the feel only, not the screen's motion), the bell turning on with a fast and
/// a slow save, a glass switch, and Cold start, which throws the haptic engine away before each Rail
/// joint to feel the slowest first beat. The simulator has no haptics.
struct SettingsHapticsPage: View {
    @State private var coldStart = false
    @State private var format = TimeFormat.twelveHour

    var body: some View {
        SettingsPageScaffold(title: "haptics.title") {
            VStack(alignment: .leading, spacing: TTSpace.s2) {
                header("haptics.feels").settingsRise(order: 0)
                feelsCard.settingsRise(order: 0)
                header("haptics.moments").settingsRise(order: 1)
                momentsCard.settingsRise(order: 1)
                header("haptics.bell").settingsRise(order: 1)
                bellCard.settingsRise(order: 1)
                header("haptics.switch").settingsRise(order: 2)
                switchCard.settingsRise(order: 2)
                coldStartCard.settingsRise(order: 3)
                SettingsNote(text: "haptics.footnote").settingsRise(order: 3)
            }
        }
        // Rail joint's first beat on time from the first tap, unless Cold start asks for the worst case.
        .onAppear {
            coldStart = haptics.coldStart
            haptics.warm()
        }
    }

    private var haptics: TTHaptics { .shared }

    private func header(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(TTFont.footnote)
            .foregroundStyle(TTColor.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TTSpace.s4)
            .padding(.top, TTSpace.s2)
            .accessibilityAddTraits(.isHeader)
    }

    /// A row per feel; a tap plays it.
    private var feelsCard: some View {
        SettingsCard {
            ForEach(Array(HapticFeel.listed.enumerated()), id: \.element) { index, feel in
                if index > 0 { SettingsHairline() }
                Button { haptics.play(feel) } label: {
                    SettingsRow(title: LocalizedStringKey(feel.titleKey)) {
                        SettingsValue(text: Text(LocalizedStringKey(feel.detailKey)))
                    }
                }
                .buttonStyle(SettingsRowButtonStyle())
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("haptics.feel.\(feel.rawValue)")
            }
        }
    }

    /// A row per moment of the map; a tap plays its feel at its time after the tap.
    private var momentsCard: some View {
        SettingsCard {
            ForEach(Array(HapticMoment.allCases.enumerated()), id: \.element) { index, moment in
                if index > 0 { SettingsHairline() }
                Button { haptics.play(moment) } label: {
                    SettingsRow(title: LocalizedStringKey(moment.titleKey)) {
                        SettingsValue(text: Text(LocalizedStringKey(moment.detailKey)))
                    }
                }
                .buttonStyle(SettingsRowButtonStyle())
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("haptics.moment.\(moment.rawValue)")
            }
        }
    }

    /// A real bell in two rows: its save back in 60 ms (Rail joint with the swell), or in 1.2 s (the soft wait tap at
    /// 150 ms, then Rail joint as it goes solid). A second tap turns it off with Tap.
    private var bellCard: some View {
        SettingsCard {
            HapticsBellRow(title: "haptics.bell.fast", save: .milliseconds(60), haptics: haptics)
                .accessibilityIdentifier("haptics.bell.fast")
            SettingsHairline()
            HapticsBellRow(title: "haptics.bell.slow", save: .milliseconds(1200), haptics: haptics)
                .accessibilityIdentifier("haptics.bell.slow")
        }
    }

    /// One glass switch: a Click as the thumb arrives, the same both ways.
    private var switchCard: some View {
        SettingsCard {
            SettingsRow(title: "haptics.switch.row", trailingInset: TTSpace.s2) {
                GlassSwitch(
                    selection: $format,
                    options: [
                        .init(
                            value: .device, label: .text("settings.time_format.device"), name: "settings.time_format.device.name",
                            identifier: "haptics.switch.device"
                        ),
                        .init(
                            value: .twelveHour, label: .text("settings.time_format.12h"), name: "settings.time_format.12h.name",
                            identifier: "haptics.switch.12h"
                        ),
                        .init(
                            value: .twentyFourHour, label: .text("settings.time_format.24h"),
                            name: "settings.time_format.24h.name", identifier: "haptics.switch.24h"
                        ),
                    ],
                    segmentWidth: 52
                )
            }
        }
    }

    private var coldStartCard: some View {
        SettingsCard {
            Toggle(isOn: Binding(get: { coldStart }, set: { coldStart = $0; haptics.coldStart = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("haptics.cold_start").font(TTFont.body).foregroundStyle(TTColor.ink)
                    Text("haptics.cold_start.detail").font(TTFont.footnote).foregroundStyle(TTColor.inkSecondary)
                }
            }
            .tint(TTColor.accent)
            .padding(.horizontal, TTSpace.s4)
            .padding(.vertical, TTSpace.s2)
            .frame(minHeight: SettingsMetrics.rowHeight)
            .accessibilityIdentifier("haptics.coldStart")
        }
        .padding(.top, TTSpace.s3)
    }
}

/// A row with a real `AlertBellButton` whose save takes `save`: the bell's faces and feels as on a card (TT-214).
private struct HapticsBellRow: View {
    let title: LocalizedStringKey
    let save: Duration
    let haptics: any HapticPlaying
    @State private var face = BellFace.off

    var body: some View {
        SettingsRow(title: title, trailingInset: TTSpace.s1) {
            AlertBellButton(face: face, label: Text(title), glyph: 26, target: 48) { tap() }
        }
    }

    private func tap() {
        switch face {
        case .off:
            face = .waiting
            let wait = haptics.play(.wait, after: .milliseconds(150))
            Task {
                try? await Task.sleep(for: save)
                wait.cancel()
                haptics.play(.railJoint)
                face = .on
            }
        case .on:
            haptics.play(.tap)
            face = .off
        case .asking, .waiting, .crossed:
            break
        }
    }
}
