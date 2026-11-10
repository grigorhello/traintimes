import SwiftUI

/// The About page (TT-168, D57): the app mark, name, tagline and version pill, one card of links that open in Safari, and two
/// plain notes.
struct SettingsAboutPage: View {
    let viewModel: SettingsViewModel
    @Environment(\.openURL) private var openURL
    /// Springs the mark in once the page is up.
    @State private var arrived = false

    var body: some View {
        SettingsPageScaffold(topPadding: 0) {
            VStack(spacing: TTSpace.s3) {
                hero
                linksCard.settingsRise(order: 2)
                SettingsNote(text: "settings.no_account").settingsRise(order: 3)
                SettingsNote(text: "settings.independent").padding(.top, -TTSpace.s1).settingsRise(order: 3)
            }
        }
        .onAppear { arrived = true }
    }

    /// The app icon at 76 pt keeps its light look in both modes, as on the canvas.
    private var hero: some View {
        VStack(spacing: 0) {
            Image("TrainTimesSymbol")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(TTColor.onAccent)
                .frame(width: TTSize.appMark, height: TTSize.appMark)
                .background(TTColor.accent)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .shadow(color: TTColor.accent.opacity(0.26), radius: 12, x: 0, y: 10)
                .environment(\.colorScheme, .light)
                .settingsBump(trigger: arrived, from: 0.72, response: 0.40, damping: 0.50, delay: 0.14)
                .accessibilityHidden(true)
            Text("app.name")
                .font(TTFont.appTitle)
                .tracking(-0.6)
                .foregroundStyle(TTColor.ink)
                .padding(.top, 14)
                .padding(.bottom, 2)
                .settingsRise(order: 0)
            Text("settings.tagline")
                .font(TTFont.subhead)
                .foregroundStyle(TTColor.inkSecondary)
                .settingsRise(order: 0)
            Text(verbatim: viewModel.versionLine)
                .font(TTFont.footnote)
                .monospacedDigit()
                .foregroundStyle(TTColor.inkSecondary)
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(TTColor.surfaceRaised, in: Capsule())
                .padding(.top, TTSpace.s3)
                .settingsRise(order: 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, TTSpace.s1)
        .padding(.bottom, TTSpace.s2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.aboutHero")
    }

    private var linksCard: some View {
        SettingsCard {
            linkRow("settings.privacy", value: nil, url: SettingsViewModel.privacyURL, id: "settings.privacy")
            SettingsHairline()
            linkRow(
                "settings.schedule_data", value: "settings.schedule_data_value", url: SettingsViewModel.dataURL,
                id: "settings.scheduleData"
            )
            SettingsHairline()
            linkRow(
                "settings.official_updates", value: nil, url: SettingsViewModel.officialUpdatesURL, id: "settings.officialUpdates"
            )
        }
    }

    private func linkRow(_ title: LocalizedStringKey, value: LocalizedStringKey?, url: URL, id: String) -> some View {
        Button { openURL(url) } label: {
            SettingsRow(title: title) {
                if let value { SettingsValue(text: Text(value)) }
                SettingsExternalArrow()
            }
        }
        .buttonStyle(SettingsRowButtonStyle())
        .accessibilityIdentifier(id)
    }
}
