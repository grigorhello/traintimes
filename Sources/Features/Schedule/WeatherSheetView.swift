import SwiftUI

/// The weather sheet (TT-226; Schedule canvas boards 14, 15 and 21): the station and the day, a 44 pt glyph and the
/// temperature at 48 pt with one line, three facts in one card, six hours, and Apple's Weather attribution. A system sheet
/// at the height of its content; nothing staggers inside. Three sizes: 48, 17 and 15 pt, plus the 13 pt attribution.
struct WeatherSheetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let sheet: WeatherSheet
    /// Apple's mark and legal link; nil until loaded (the text stands in for the mark).
    var credit: WeatherCredit?
    @State private var height: CGFloat = 420

    var body: some View {
        content
            .padding(.horizontal, TTSpace.s5)
            .padding(.top, 26)
            .padding(.bottom, TTSpace.s4)
            .frame(maxWidth: .infinity, alignment: .top)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .presentationDetents([.height(height)])
            .presentationDragIndicator(.visible)
            .presentationBackground(TTColor.surface)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("weather.sheet")
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: TTSpace.s3) {
                Text(verbatim: sheet.station)
                    .font(TTFont.headline)
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(verbatim: sheet.dayLabel)
                    .font(TTFont.subhead)
                    .foregroundStyle(TTColor.inkSecondary)
            }
            hero.padding(.top, 14)
            facts.padding(.top, TTSpace.s4)
            hours.padding(.top, TTSpace.s4)
            attribution
                .frame(maxWidth: .infinity)
                .padding(.top, TTSpace.s4)
        }
    }

    private var hero: some View {
        HStack(spacing: TTSpace.s3) {
            WeatherGlyph(icon: sheet.icon, size: 44)
            Text(verbatim: sheet.temperature)
                .font(TTFont.weatherTemperature)
                .monospacedDigit()
                .tracking(-1)
                .foregroundStyle(TTColor.ink)
                .fixedSize()
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: sheet.line)
                    .font(TTFont.headline)
                    .foregroundStyle(TTColor.ink)
                if let detail = sheet.detail {
                    Text(verbatim: detail)
                        .font(TTFont.subhead)
                        .foregroundStyle(TTColor.inkSecondary)
                }
            }
            .padding(.leading, 6)
        }
    }

    private var facts: some View {
        HStack(alignment: .top, spacing: TTSpace.s2) {
            ForEach(sheet.facts, id: \.label) { fact in
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: fact.label)
                        .font(TTFont.subhead)
                        .foregroundStyle(TTColor.inkSecondary)
                    Text(verbatim: fact.value)
                        .font(TTFont.headline)
                        .monospacedDigit()
                        .foregroundStyle(TTColor.ink)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, TTSpace.s3)
        .padding(.horizontal, TTSpace.s4)
        .background(TTColor.canvas, in: RoundedRectangle(cornerRadius: TTRadius.lg))
    }

    private var hours: some View {
        HStack(spacing: 0) {
            ForEach(Array(sheet.hours.enumerated()), id: \.offset) { _, hour in
                VStack(spacing: TTSpace.s1) {
                    Text(verbatim: hour.label)
                        .font(TTFont.subhead)
                        .foregroundStyle(TTColor.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    WeatherGlyph(icon: hour.icon, size: 24)
                    Text(verbatim: hour.temperature)
                        .font(TTFont.headline)
                        .monospacedDigit()
                        .foregroundStyle(TTColor.ink)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Apple's Weather mark (its own light or dark image) and the "Other data sources" link, required by WeatherKit.
    private var attribution: some View {
        HStack(spacing: TTSpace.s1) {
            if let url = colorScheme == .dark ? credit?.darkMark : credit?.lightMark {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    markText
                }
                .frame(height: 12)
            } else {
                markText
            }
            Text(verbatim: "·")
                .foregroundStyle(TTColor.inkSecondary)
            Link(destination: (credit ?? .fixture).legal) {
                Text("weather.attribution.legal")
                    .underline()
                    .foregroundStyle(TTColor.inkSecondary)
            }
            .accessibilityIdentifier("weather.attribution")
        }
        .font(TTFont.footnote)
    }

    private var markText: some View {
        Text("weather.attribution.mark")
            .fontWeight(.semibold)
            .foregroundStyle(TTColor.ink)
    }
}
