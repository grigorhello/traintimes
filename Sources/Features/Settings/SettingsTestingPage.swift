import SwiftUI

/// The Testing page (TT-168, D57; TestFlight and Debug builds only): Demo trains as a glass switch with one line describing
/// the chosen mode, Mock time as a switch that opens the date and time and the quick choices, and Reset, which turns
/// everything off and goes back to the real time. `DemoTrains` and `MockTime` behave as before.
struct SettingsTestingPage: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPageScaffold(
            title: "settings.testing",
            trailing: { resetButton },
            content: {
                VStack(alignment: .leading, spacing: TTSpace.s2) {
                    header("settings.demo_trains").settingsRise(order: 0)
                    demoCard.settingsRise(order: 0)
                    header("settings.testing.time").settingsRise(order: 1)
                    mockTimeCard.settingsRise(order: 1)
                    SettingsNote(text: "settings.testing.footnote").settingsRise(order: 2)
                }
            }
        )
    }

    private func header(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(TTFont.footnote)
            .foregroundStyle(TTColor.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TTSpace.s4)
            .padding(.top, TTSpace.s2)
            .accessibilityAddTraits(.isHeader)
    }

    /// "Reset" appears once anything is on, with a small spring.
    private var resetButton: some View {
        let active = viewModel.isTestingActive
        return Button { viewModel.resetTesting() } label: { Text("settings.testing.reset") }
            .buttonStyle(.ttText)
            .opacity(active ? 1 : 0)
            .scaleEffect(active ? 1 : 0.9)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : SettingsMotion.arrive, value: active)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
            .accessibilityIdentifier("settings.testing.reset")
    }

    // MARK: Demo trains

    private var demoCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                GlassSwitch(
                    selection: $viewModel.demoTrains,
                    options: [
                        .init(
                            value: .off, label: .text("settings.demo_trains.off"), name: "settings.demo_trains.off",
                            identifier: "settings.demoTrains.off"
                        ),
                        .init(
                            value: .delays, label: .text("settings.demo_trains.delays"), name: "settings.demo_trains.delays",
                            identifier: "settings.demoTrains.delays"
                        ),
                        .init(
                            value: .offline, label: .text("settings.demo_trains.offline"), name: "settings.demo_trains.offline",
                            identifier: "settings.demoTrains.offline"
                        ),
                        .init(
                            value: .awaitingPlatform, label: .text("settings.demo_trains.platform"),
                            name: "settings.demo_trains.platform", identifier: "settings.demoTrains.platform"
                        ),
                    ]
                )
                description
            }
            .padding(TTSpace.s3)
        }
    }

    /// One line for the chosen mode. All four are laid on top of each other, so the card keeps the height of the longest and
    /// the lines cross-fade.
    private var description: some View {
        ZStack(alignment: .topLeading) {
            ForEach(DemoTrains.allCases, id: \.self) { mode in
                Text(mode.detail)
                    .font(TTFont.footnote)
                    .foregroundStyle(TTColor.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(mode == viewModel.demoTrains ? 1 : 0)
                    .accessibilityHidden(mode != viewModel.demoTrains)
            }
        }
        .padding(.horizontal, 2)
        .animation(.easeOut(duration: 0.15), value: viewModel.demoTrains)
    }

    // MARK: Mock time

    private var mockTimeCard: some View {
        SettingsCard {
            Toggle(isOn: $viewModel.isMockTimeOn) {
                Text("settings.mock_time").font(TTFont.body).foregroundStyle(TTColor.ink)
            }
            .tint(TTColor.accent)
            .padding(.horizontal, TTSpace.s4)
            .frame(minHeight: SettingsMetrics.rowHeight)
            .accessibilityIdentifier("settings.mockTime")

            if viewModel.isMockTimeOn {
                SettingsHairline().dropsIn(order: 0, reduceMotion: reduceMotion)
                dateAndTimeRow.dropsIn(order: 0, reduceMotion: reduceMotion)
                SettingsHairline().dropsIn(order: 1, reduceMotion: reduceMotion)
                presetsRow.dropsIn(order: 1, reduceMotion: reduceMotion)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SettingsMotion.reveal, value: viewModel.isMockTimeOn)
    }

    /// The date and time as the system's two pills, in Toronto time.
    private var dateAndTimeRow: some View {
        HStack {
            DatePicker(
                "settings.mock_time", selection: $viewModel.mockTimeStart, displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .environment(\.timeZone, goTimeZone)
            .accessibilityIdentifier("settings.mockTime.picker")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TTSpace.s4)
        .frame(minHeight: SettingsMetrics.rowHeight)
    }

    /// Early morning, Late evening and Midnight, on the picker's date.
    private var presetsRow: some View {
        HStack(spacing: TTSpace.s2) {
            ForEach(MockTimePreset.allCases, id: \.self) { preset in
                Button { viewModel.chooseMockTime(preset) } label: {
                    Text(LocalizedStringKey(preset.titleKey))
                        .font(TTFont.badge)
                        .foregroundStyle(TTColor.accent)
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(TTColor.accentSoft, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityIdentifier(preset.identifier)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TTSpace.s4)
        .frame(minHeight: SettingsMetrics.rowHeight)
    }
}

private extension DemoTrains {
    /// The line under the switch for this mode.
    var detail: LocalizedStringKey {
        switch self {
        case .off: "settings.demo_trains.off_detail"
        case .delays: "settings.demo_trains.delays_detail"
        case .offline: "settings.demo_trains.offline_detail"
        case .awaitingPlatform: "settings.demo_trains.platform_detail"
        }
    }
}

private extension View {
    /// A Mock time row arriving: it drops in 12 pt and fades, 24 ms after the row before (30 ms for the first).
    func dropsIn(order: Int, reduceMotion: Bool) -> some View {
        let drop = AnyTransition.offset(y: -12).combined(with: .opacity)
            .animation(SettingsMotion.rise.delay(SettingsMotion.dropDelay(order: order)))
        return transition(reduceMotion ? AnyTransition.opacity : drop)
    }
}
