import SwiftUI

// The pieces every Settings page is built from (TT-168, D57). A card holds things you can tap; plain text on the canvas is
// information. Cards are solid, never glass; text never sits on glass.

enum SettingsMetrics {
    /// Every row of every card.
    static let rowHeight: CGFloat = 56
}

/// A card of 56 pt rows split by hairlines: a surface in a 26 pt radius, the card shadow in light and a 0.5 pt white 8 % edge
/// in dark. The rows are clipped to it, so a pressed row keeps the rounded corners.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .clipShape(RoundedRectangle(cornerRadius: TTRadius.xl))
            .ttSheetCard()
    }
}

/// The line between two rows, inset 16 pt on the left.
struct SettingsHairline: View {
    var body: some View {
        Rectangle().fill(TTColor.hairline).frame(height: 1).padding(.leading, TTSpace.s4)
    }
}

/// A 56 pt row with 16 pt padding: the title on the left, `trailing` on the right (a value, a chevron, a switch).
struct SettingsRow<Trailing: View>: View {
    let title: LocalizedStringKey
    /// The switch rows sit 8 pt from the card's edge: the track is the row's tallest part.
    var trailingInset = TTSpace.s4
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: TTSpace.s3) {
            Text(title).font(TTFont.body).foregroundStyle(TTColor.ink).lineLimit(1)
            Spacer(minLength: TTSpace.s2)
            trailing
        }
        .padding(.leading, TTSpace.s4)
        .padding(.trailing, trailingInset)
        .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowHeight, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Tints a pressed row: the ink at 6 % in light, white at 8 % in dark (as the station picker's rows).
struct SettingsRowButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? (colorScheme == .dark ? Color.white.opacity(0.08) : TTColor.ink.opacity(0.06)) : Color.clear)
    }
}

/// A row's value, ink-secondary: "1.0 (12)", "Metrolinx", "2".
struct SettingsValue: View {
    let text: Text

    var body: some View {
        text.font(TTFont.body).foregroundStyle(TTColor.inkSecondary).lineLimit(1)
    }
}

/// The chevron of a row that opens a page.
struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(TTColor.inkTertiary)
            .accessibilityHidden(true)
    }
}

/// The arrow of a row that opens something outside the app (Safari, the iOS Settings app).
struct SettingsExternalArrow: View {
    var body: some View {
        Image(systemName: "arrow.up.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(TTColor.inkTertiary)
            .accessibilityHidden(true)
    }
}

/// Plain text under or between cards, in footnote ink-secondary, 16 pt in from the page margin.
struct SettingsNote: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(TTFont.footnote)
            .foregroundStyle(TTColor.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TTSpace.s4)
    }
}

/// A pushed page: a 44 pt row with the glass back button, the centred title and a trailing control, over a scrolling page
/// with 20 pt margins. The system bar is hidden (as on Schedule), so a swipe from the left edge goes back here. The tab bar
/// stays.
struct SettingsPageScaffold<Trailing: View, Content: View>: View {
    var title: LocalizedStringKey?
    var topPadding = TTSpace.s3
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let title {
                    Text(title)
                        .font(TTFont.navTitle)
                        .foregroundStyle(TTColor.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                HStack {
                    GlassIconButton(systemName: "chevron.left", label: "button.back", tint: TTColor.ink) { dismiss() }
                        .accessibilityIdentifier("settings.back")
                    Spacer(minLength: 0)
                    trailing
                }
            }
            .padding(.horizontal, TTSpace.s4)
            .frame(height: TTSize.targetMin)

            ScrollView {
                content
                    .padding(.horizontal, TTSpace.s5)
                    .padding(.top, topPadding)
                    .padding(.bottom, TTSpace.s6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(TTColor.canvas)
        .toolbar(.hidden, for: .navigationBar)
        // Hiding the bar also switches off the system's edge swipe, so this page answers it.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30).onEnded { drag in
                if drag.startLocation.x < 24, drag.translation.width > 80, abs(drag.translation.height) < 60 { dismiss() }
            }
        )
    }
}

extension SettingsPageScaffold where Trailing == EmptyView {
    /// A page with nothing at the right of its title row.
    init(title: LocalizedStringKey? = nil, topPadding: CGFloat = TTSpace.s3, @ViewBuilder content: () -> Content) {
        self.init(title: title, topPadding: topPadding, trailing: { EmptyView() }, content: content)
    }
}
