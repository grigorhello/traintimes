import SwiftUI

/// The Testing page (TT-168, D57; TestFlight and Debug builds only): Demo trains as a glass switch with one line describing
/// the chosen mode, and under Depart the automatic ride's demo with its last check (TT-242, D120), Mock time as a switch
/// that opens the date and time and the quick choices, Demo place with Automatic direction's last look under it (TT-234,
/// D116), the Haptics page (TT-214), and Reset, which turns everything off and goes back to the real time. `DemoTrains` and
/// `MockTime` behave as before.
struct SettingsTestingPage: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.timeFormatter) private var formatter
    @Environment(\.feedbackNudge) private var feedbackNudge
    /// "Play on Schedule" was tapped: the Feedback button asks on the next still Schedule (TT-228).
    @State private var nudgeQueued = false

    var body: some View {
        SettingsPageScaffold(
            title: "settings.testing",
            trailing: { resetButton },
            content: {
                VStack(alignment: .leading, spacing: TTSpace.s2) {
                    header("settings.demo_trains").settingsRise(order: 0)
                    demoSection.settingsRise(order: 0)
                    header("settings.live_data").settingsRise(order: 1)
                    liveCard.settingsRise(order: 1)
                    header("settings.testing.time").settingsRise(order: 2)
                    mockTimeCard.settingsRise(order: 2)
                    demoWeatherCard.settingsRise(order: 2)
                    SettingsNote(text: "settings.testing.footnote").settingsRise(order: 3)
                    // Under Time, so Mock time's rows stay where they were on the screen.
                    demoPlaceSection.settingsRise(order: 3)
                    toolCards.settingsRise(order: 4)
                }
                // Depart's Automatic ride and its Last check come and go with the rows under them moving together.
                .animation(reduceMotion ? .easeOut(duration: 0.2) : SettingsMotion.reveal, value: viewModel.showsDemoAutoRide)
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

    /// The Haptics page and the Feedback animation, at the end of the page.
    private var toolCards: some View {
        VStack(alignment: .leading, spacing: TTSpace.s2) {
            hapticsCard
            feedbackNudgeCard
        }
    }

    /// Haptics (TT-214): the page where every feel can be tried on the phone.
    private var hapticsCard: some View {
        SettingsCard {
            NavigationLink(value: SettingsPage.haptics) {
                SettingsRow(title: "haptics.title") { SettingsChevron() }
            }
            .buttonStyle(SettingsRowButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("settings.haptics")
        }
        .padding(.top, TTSpace.s3)
    }

    /// Feedback animation (TT-228, D112; TT-252, D128): Schedule's Feedback button asks 1.5 s after the next time Schedule
    /// is still, also in builds where it would not play by itself.
    private var feedbackNudgeCard: some View {
        SettingsCard {
            Button {
                feedbackNudge?.playOnNextStill()
                nudgeQueued = true
            } label: {
                SettingsRow(title: "settings.feedback_nudge") {
                    Text(nudgeQueued ? LocalizedStringKey("settings.feedback_nudge.queued") : "settings.feedback_nudge.play")
                        .font(TTFont.body)
                        .foregroundStyle(nudgeQueued ? TTColor.inkSecondary : TTColor.accent)
                }
            }
            .buttonStyle(SettingsRowButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("settings.feedbackNudge")
        }
        .padding(.top, TTSpace.s3)
    }

    // MARK: Demo trains

    /// The Demo trains card, and under Depart the automatic ride's Last check below it (TT-242, D120).
    private var demoSection: some View {
        VStack(alignment: .leading, spacing: TTSpace.s2) {
            demoCard
            if viewModel.showsDemoAutoRide {
                lastCheck
            }
        }
    }

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
                        .init(
                            value: .ride, label: .text("settings.demo_trains.ride"), name: "settings.demo_trains.ride",
                            identifier: "settings.demoTrains.ride"
                        ),
                        .init(
                            value: .departure, label: .text("settings.demo_trains.departure"),
                            name: "settings.demo_trains.departure", identifier: "settings.demoTrains.departure"
                        ),
                    ]
                )
                description
                if viewModel.showsDemoExpress {
                    // The demo ride as an express (TT-232): the word the Schedule card's bolt reads as.
                    Toggle(isOn: $viewModel.demoExpress) {
                        Text("tag.express").font(TTFont.body).foregroundStyle(TTColor.ink)
                    }
                    .tint(TTColor.accent)
                    .padding(.horizontal, 2)
                    .accessibilityIdentifier("settings.demoExpress")
                }
                if viewModel.showsDemoAutoRide {
                    autoRide
                }
            }
            .padding(TTSpace.s3)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SettingsMotion.reveal, value: viewModel.showsDemoExpress)
    }

    // MARK: Automatic ride (TT-242, D120)

    /// Under Depart: the demo watch decides whether the phone left Union with the 5:16 PM train, on the demo's clock. Off,
    /// Boards, Stays and No feed on the same switch as Demo trains, with one line for the chosen mode.
    private var autoRide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("settings.demo_auto_ride")
                .font(TTFont.body)
                .foregroundStyle(TTColor.ink)
                .padding(.horizontal, 2)
                .padding(.top, TTSpace.s1)
            GlassSwitch(
                selection: $viewModel.demoAutoRide,
                options: DemoAutoRide.allCases.map { mode -> GlassSwitch<DemoAutoRide>.Option in
                    GlassSwitch<DemoAutoRide>.Option(
                        value: mode, label: .text(mode.switchLabel), name: mode.switchLabel,
                        identifier: "settings.demoAutoRide.\(mode.rawValue)"
                    )
                }
            )
            ZStack(alignment: .topLeading) {
                ForEach(DemoAutoRide.allCases, id: \.self) { mode in
                    Text(mode.switchDetail)
                        .font(TTFont.footnote)
                        .foregroundStyle(TTColor.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(mode == viewModel.demoAutoRide ? 1 : 0)
                        .accessibilityHidden(mode != viewModel.demoAutoRide)
                }
            }
            .padding(.horizontal, 2)
            .animation(.easeOut(duration: 0.15), value: viewModel.demoAutoRide)
        }
    }

    /// The last check: how the automatic ride's last watch ended, the seconds after the train left and when the hold reached
    /// the server, kept for the run only. Information, so plain text under the card, as Last look; never a place.
    private var lastCheck: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("settings.last_check").font(TTFont.footnote).foregroundStyle(TTColor.inkSecondary)
            Text(verbatim: viewModel.lastCheckText(formatter: formatter))
                .monospacedDigit()
                .font(TTFont.subhead)
                .foregroundStyle(TTColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TTSpace.s4)
        .padding(.top, TTSpace.s1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.lastCheck")
    }

    /// One line for the chosen mode. All of them are laid on top of each other, so the card keeps the height of the longest and
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

    // MARK: Live data

    /// Live data (TT-195): a made-up feed on the real timetable, six choices on the same switch as Demo trains; the sixth,
    /// Board, shows Boarding at the platform (TT-233, D114).
    private var liveCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                GlassSwitch(
                    selection: $viewModel.mockLive,
                    options: MockLive.allCases.map { live -> GlassSwitch<MockLive>.Option in
                        let key = LocalizedStringKey(live.labelKey ?? "settings.live_data.off")
                        return GlassSwitch<MockLive>.Option(
                            value: live, label: .text(key), name: key, identifier: "settings.liveData.\(live.rawValue)"
                        )
                    }
                )
                ZStack(alignment: .topLeading) {
                    ForEach(MockLive.allCases, id: \.self) { live in
                        Text(LocalizedStringKey(live.detailKey))
                            .font(TTFont.footnote)
                            .foregroundStyle(TTColor.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(live == viewModel.mockLive ? 1 : 0)
                            .accessibilityHidden(live != viewModel.mockLive)
                    }
                }
                .padding(.horizontal, 2)
                .animation(.easeOut(duration: 0.15), value: viewModel.mockLive)
            }
            .padding(TTSpace.s3)
        }
    }

    // MARK: Demo place

    /// Demo place and the last look (TT-234, D116).
    private var demoPlaceSection: some View {
        VStack(alignment: .leading, spacing: TTSpace.s2) {
            header("settings.demo_place")
            demoPlaceCard
            lastLook
        }
    }

    /// Demo place: Automatic direction reads the phone as at one of the route's two stations, so a turn can be tried at a
    /// desk; Off uses the real location.
    private var demoPlaceCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                GlassSwitch(selection: $viewModel.demoPlace, options: demoPlaceOptions)
                Text("settings.demo_place.detail")
                    .font(TTFont.footnote)
                    .foregroundStyle(TTColor.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
            }
            .padding(TTSpace.s3)
        }
    }

    /// Off, then the route's two stations by their short names, each segment named by its station id.
    private var demoPlaceOptions: [GlassSwitch<String?>.Option] {
        let off = GlassSwitch<String?>.Option(
            value: nil, label: .text("settings.demo_place.off"), name: "settings.demo_place.off",
            identifier: "settings.demoPlace.off"
        )
        let stations = viewModel.demoPlaceStations.map { station -> GlassSwitch<String?>.Option in
            // A station's name is no key of the strings file, so the switch shows it as it is.
            let name = LocalizedStringKey(station.name)
            return GlassSwitch<String?>.Option(
                value: station.id, label: .text(name), name: name, identifier: "settings.demoPlace.\(station.id)"
            )
        }
        return [off] + stations
    }

    /// The last look: how long it waited and what it did, kept for the run only, so the time a look takes can be read on
    /// a phone. Information, so plain text under the card; never a place.
    private var lastLook: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("settings.last_look").font(TTFont.footnote).foregroundStyle(TTColor.inkSecondary)
            Text(verbatim: viewModel.lastLookText).monospacedDigit().font(TTFont.subhead).foregroundStyle(TTColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TTSpace.s4)
        .padding(.top, TTSpace.s1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.lastLook")
    }

    // MARK: Demo weather

    /// Demo weather (TT-226): fixture weather on the weather tile, for the simulator and screenshots.
    private var demoWeatherCard: some View {
        SettingsCard {
            Toggle(isOn: $viewModel.isDemoWeatherOn) {
                Text("settings.demo_weather").font(TTFont.body).foregroundStyle(TTColor.ink)
            }
            .tint(TTColor.accent)
            .padding(.horizontal, TTSpace.s4)
            .frame(minHeight: SettingsMetrics.rowHeight)
            .accessibilityIdentifier("settings.demoWeather")
        }
        .padding(.top, TTSpace.s3)
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
        case .ride: "settings.demo_trains.ride_detail"
        case .departure: "settings.demo_trains.departure_detail"
        }
    }
}

private extension DemoAutoRide {
    /// The word on the switch.
    var switchLabel: LocalizedStringKey {
        switch self {
        case .off: "settings.demo_auto_ride.off"
        case .boards: "settings.demo_auto_ride.boards"
        case .stays: "settings.demo_auto_ride.stays"
        case .noFeed: "settings.demo_auto_ride.no_feed"
        }
    }

    /// The line under the switch for this mode.
    var switchDetail: LocalizedStringKey {
        switch self {
        case .off: "settings.demo_auto_ride.off_detail"
        case .boards: "settings.demo_auto_ride.boards_detail"
        case .stays: "settings.demo_auto_ride.stays_detail"
        case .noFeed: "settings.demo_auto_ride.no_feed_detail"
        }
    }
}

private extension MockLive {
    /// The line under the switch for this feed.
    var detailKey: String {
        switch self {
        case .off: "settings.live_data.off_detail"
        case .onTime: "settings.live_data.on_time_detail"
        case .mixed: "settings.live_data.mixed_detail"
        case .changing: "settings.live_data.changing_detail"
        case .stale: "settings.live_data.stale_detail"
        case .boarding: "settings.live_data.boarding_detail"
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
