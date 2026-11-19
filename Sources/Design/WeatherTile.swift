import SwiftUI

/// A weather glyph (TT-226): SF Symbols, fill variants, palette rendering, so the cloud is grey and only the sun, moon,
/// drops and flakes carry colour. Nil draws the grey cloud of a tile with nothing to show.
struct WeatherGlyph: View {
    let icon: WeatherIcon?
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.palette)
            .foregroundStyle(colors.0, colors.1)
            .font(.system(size: size * 0.82, weight: .regular))
            .frame(width: size + 4, height: size)
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch icon {
        case .sun: "sun.max.fill"
        case .moon: "moon.fill"
        case .partlySun: "cloud.sun.fill"
        case .partlyMoon: "cloud.moon.fill"
        case .cloud, nil: "cloud.fill"
        case .rain: "cloud.rain.fill"
        case .snow: "cloud.snow.fill"
        case .wind: "wind"
        }
    }

    /// The palette's layers: the cloud first, then what it carries.
    private var colors: (Color, Color) {
        switch icon {
        case .sun: (TTColor.weatherSun, TTColor.weatherSun)
        case .moon: (TTColor.weatherMoon, TTColor.weatherMoon)
        case .partlySun: (TTColor.weatherCloud, TTColor.weatherSun)
        case .partlyMoon: (TTColor.weatherCloud, TTColor.weatherMoon)
        case .cloud, .wind: (TTColor.weatherCloud, TTColor.weatherCloud)
        case .rain: (TTColor.weatherCloud, TTColor.weatherRain)
        case .snow: (TTColor.weatherCloud, TTColor.weatherSnow)
        case nil: (TTColor.inkTertiary, TTColor.inkTertiary)
        }
    }
}

/// The weather tile pinned at the left of Schedule's day strip (TT-226): 80 × 48 pt, a day tile's solid surface and
/// shadow, a 28 pt coloured glyph and the temperature, no words. Grey and flat with a dash when there is nothing to show,
/// and then it opens nothing; a skeleton while the first request runs.
struct WeatherTileView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tile: WeatherTile
    /// The cross-fade and the rolling temperature on a day change (off in snapshots, `\.playsScheduleMotion`).
    var animates = true
    let action: () -> Void

    static let size = CGSize(width: 80, height: 48)
    static let gap: CGFloat = 5

    var body: some View {
        Button(action: action) {
            content
                .frame(width: Self.size.width, height: Self.size.height)
                .background(background, in: RoundedRectangle(cornerRadius: TTRadius.md))
                .shadow(color: .black.opacity(colorScheme == .dark || !isRaised ? 0 : 0.06), radius: 1, x: 0, y: 1)
        }
        .buttonStyle(WeatherTilePressStyle(animates: animates && !reduceMotion))
        .disabled(!opens)
        .accessibilityLabel(Text("weather.tile"))
        .accessibilityValue(Text(verbatim: value))
        .accessibilityIdentifier("schedule.weather")
    }

    @ViewBuilder private var content: some View {
        switch tile {
        case .loading:
            HStack(spacing: Self.gap) {
                Circle().fill(TTColor.surfaceRaised).frame(width: 26, height: 26)
                Capsule().fill(TTColor.surfaceRaised).frame(width: 24, height: 14)
            }
        case .shows(let icon, let temperature):
            HStack(spacing: Self.gap) {
                ZStack {
                    WeatherGlyph(icon: icon)
                        .id(icon)
                        .transition(.opacity)
                }
                Text(verbatim: temperature)
                    .font(TTFont.headline)
                    .monospacedDigit()
                    .tracking(-0.6)
                    .foregroundStyle(TTColor.ink)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .fixedSize()
            }
            .animation(animates ? .easeOut(duration: 0.2) : nil, value: tile)
        case .unavailable:
            HStack(spacing: Self.gap) {
                WeatherGlyph(icon: nil)
                Text(verbatim: "—")
                    .font(TTFont.body)
                    .foregroundStyle(TTColor.inkTertiary)
            }
        }
    }

    private var opens: Bool {
        if case .shows = tile { return true }
        return false
    }

    /// Raised with the card shadow, except the grey tile, which lies flat like a departed card.
    private var isRaised: Bool { tile.unavailableReason == nil }

    private var background: Color {
        guard !isRaised else { return TTColor.surface }
        return colorScheme == .dark ? TTColor.surface.opacity(0.55) : TTColor.surfaceRaised
    }

    private var value: String {
        if case .shows(_, let temperature) = tile { return temperature }
        return "—"
    }
}

/// The tile's press: 0.96 in 0.1 s, back on the button spring (0.30 / 0.65). No haptic: opening a sheet is navigation (D95).
struct WeatherTilePressStyle: ButtonStyle {
    var animates = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && animates ? 0.96 : 1)
            .animation(
                configuration.isPressed ? .easeOut(duration: 0.1) : .spring(response: 0.30, dampingFraction: 0.65),
                value: configuration.isPressed
            )
    }
}
