import SwiftUI

/// 18 pt radius surface. Light mode carries a 0 1 2 shadow at 6%; dark mode uses the canvas-to-surface step only.
/// `padding: 0` for a list of full-width rows split by hairlines (Settings).
struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat = TTSpace.s4
    /// A panel hangs right under the card (the station picker, D54): the bottom corners square off and the 1 pt shadow
    /// goes, so the card and the panel read as one surface.
    var joinsBelow = false
    /// A departed timeline card (TT-203, D86), 0 to 1: the surface turns to the canvas colour and the shadow to a 1 pt
    /// hairline outline.
    var flatness: CGFloat = 0
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: TTRadius.lg)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if flatness > 0 {
                    shape.fill(TTColor.canvas).opacity(flatness)
                        .overlay(shape.strokeBorder(TTColor.hairline, lineWidth: 1).opacity(flatness))
                }
            }
            .background(TTColor.surface, in: shape)
            // A strip behind the content (not over it, which clipped the route pin) squares off the rounded bottom corners.
            .background(alignment: .bottom) {
                Rectangle().fill(TTColor.surface).frame(height: TTRadius.lg).opacity(joinsBelow ? 1 : 0).allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(colorScheme == .dark || joinsBelow ? 0 : 0.06 * (1 - flatness)), radius: 1, x: 0, y: 1)
    }
}

/// A card on a sheet's canvas ground (TT-163, D56): a surface in a 26 pt radius, the `Card` shadow in light and a 0.5 pt
/// white 8 % inner edge in dark. Fills the width; the caller sets the padding. Train detection's strip and question on
/// Schedule use it with their own radii (TT-175).
private struct SheetCard: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TTColor.surface, in: shape)
            .overlay(shape.strokeBorder(.white.opacity(colorScheme == .dark ? 0.08 : 0), lineWidth: 0.5))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 1, x: 0, y: 1)
    }
}

extension View {
    func ttSheetCard(cornerRadius: CGFloat = TTRadius.xl) -> some View { modifier(SheetCard(cornerRadius: cornerRadius)) }
}

/// The one line that states the data mode (D14). Times are formatted by the one time formatter.
struct FreshnessLine: View {
    enum Mode: Hashable, Sendable {
        /// "Loading timetable": no schedule for this route yet (TT-115).
        case loading
        /// "Updated just now" or "Updated N min ago", from the one formatter.
        case live(updated: String)
        /// `day` ("Sun, Nov 8") is set on any day other than today.
        case scheduledOnly(day: String?)
        case stale(lastReported: String)
        /// `lastUpdated` is nil when nothing was ever fetched.
        case offline(lastUpdated: String?)
    }

    let mode: Mode

    var body: some View {
        HStack(spacing: TTSpace.s1) {
            if let symbol { Image(systemName: symbol) }
            Text(text).monospacedDigit()
        }
        .font(TTFont.footnote)
        .foregroundStyle(TTColor.inkSecondary)
    }

    private var text: String {
        switch mode {
        case .loading: String(localized: "freshness.loading")
        case .live(let updated): updated
        case .scheduledOnly(let day?): String(format: String(localized: "freshness.scheduled_only_day"), day)
        case .scheduledOnly(.none): String(localized: "freshness.scheduled_only")
        case .stale(let time): String(format: String(localized: "freshness.stale"), time)
        case .offline(let time?): String(format: String(localized: "freshness.offline"), time)
        case .offline(.none): String(localized: "schedule.offline")
        }
    }

    private var symbol: String? {
        switch mode {
        case .loading, .live, .stale: nil
        case .scheduledOnly: "clock"
        case .offline: "wifi.slash"
        }
    }
}

/// Short confirmation above the tab bar, as the canvas's `.toast`: an icon, one line such as "Alert on for the 7:32 AM
/// train", and an optional text action such as "Repeat". A surface card with the sheet shadow.
struct Toast: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: String
    var systemImage: String?
    var tint: Color = TTColor.accent
    var actionTitle: LocalizedStringKey?
    /// How it comes and goes.
    var transition: AnyTransition = .opacity.combined(with: .move(edge: .bottom)).animation(.easeOut(duration: 0.25))
    var action: () -> Void = {}

    /// The canvas toast's radius and padding.
    private static let radius: CGFloat = 14
    private static let insets = EdgeInsets(top: 10, leading: TTSpace.s4, bottom: 10, trailing: TTSpace.s3)

    var body: some View {
        HStack(spacing: TTSpace.s3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: TTSize.iconButtonGlyph))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            Text(message)
                .font(TTFont.subhead)
                .monospacedDigit()
                .foregroundStyle(TTColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle {
                Button(action: action) {
                    Text(actionTitle).font(TTFont.headline)
                }
                .buttonStyle(.ttText)
                .accessibilityIdentifier("toast.action")
            }
        }
        .frame(minHeight: TTSize.targetMin)
        .padding(Self.insets)
        .background(TTColor.surface, in: RoundedRectangle(cornerRadius: Self.radius))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.14), radius: 15, x: 0, y: -6)
        .transition(transition)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toast")
    }
}

struct EmptyStateCard: View {
    let systemImage: String
    let title: Text
    let message: Text
    var actionTitle: Text?
    /// The action as the primary pill ("Add alert" on the Alerts tab, TT-143) rather than accent text.
    var isPrimaryAction = false
    var action: () -> Void = {}

    init(
        systemImage: String, title: LocalizedStringKey, message: LocalizedStringKey, actionTitle: LocalizedStringKey? = nil,
        isPrimaryAction: Bool = false, action: @escaping () -> Void = {}
    ) {
        self.init(
            systemImage: systemImage, title: Text(title), message: Text(message), actionTitle: actionTitle.map { Text($0) },
            isPrimaryAction: isPrimaryAction, action: action
        )
    }

    /// Copy already formatted from `Localizable.strings`, such as "No direct trains on Sunday".
    init(
        systemImage: String, title: Text, message: Text, actionTitle: Text? = nil, isPrimaryAction: Bool = false,
        action: @escaping () -> Void = {}
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.isPrimaryAction = isPrimaryAction
        self.action = action
    }

    var body: some View {
        Card {
            VStack(spacing: TTSpace.s2) {
                Image(systemName: systemImage)
                    .font(.system(size: TTSize.iconMD + TTSpace.s2))
                    .foregroundStyle(TTColor.inkSecondary)
                    .padding(.bottom, TTSpace.s2)
                title.font(TTFont.headline).foregroundStyle(TTColor.ink)
                message.font(TTFont.subhead).foregroundStyle(TTColor.inkSecondary)
                if let actionTitle, isPrimaryAction {
                    Button(action: action) { actionTitle }
                        .buttonStyle(.ttPrimary)
                        .padding(.top, TTSpace.s2)
                        .accessibilityIdentifier("emptyState.action")
                } else if let actionTitle {
                    Button(action: action) { actionTitle }
                        .buttonStyle(.ttText)
                        .accessibilityIdentifier("emptyState.action")
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, TTSpace.s4)
        }
    }
}

/// Loading placeholder. Pulses gently; no pulse with Reduce Motion.
struct SkeletonCard: View {
    enum Layout {
        /// The loading row on the component sheet.
        case row
        /// A timeline card while the first timetable loads (TT-115, `schedule-loading.png`): time, arrival, badge row.
        case departure(isNext: Bool)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.skeletonPulses) private var pulsesEverywhere
    var layout = Layout.row
    /// Off in snapshots so the image is stable.
    var pulses = true
    @State private var dimmed = false

    var body: some View {
        Card {
            switch layout {
            case .row:
                VStack(alignment: .leading, spacing: TTSpace.s3) {
                    HStack {
                        bar(width: 64, height: TTSpace.s3)
                        Spacer()
                        bar(width: 96, height: TTSpace.s3)
                    }
                    HStack {
                        bar(width: 160, height: TTSpace.s8)
                        Spacer()
                        bar(width: 72, height: TTSpace.s5)
                    }
                }
            case .departure(let isNext):
                VStack(alignment: .leading, spacing: TTSpace.s1) {
                    HStack(alignment: .top, spacing: TTSpace.s3) {
                        bar(width: isNext ? 150 : 130, height: isNext ? TTSpace.s8 : 30)
                            .padding(.top, TTSpace.s1)
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: TTSpace.s2) {
                            bar(width: 96, height: TTSpace.s3)
                            bar(width: 70, height: 18)
                        }
                    }
                    HStack(spacing: TTSpace.s2) {
                        Capsule().fill(TTColor.surfaceRaised).frame(width: 90, height: TTSpace.s6)
                        bar(width: 70, height: TTSpace.s3)
                    }
                }
            }
        }
        .opacity(dimmed ? 0.6 : 1)
        .onAppear {
            guard pulses, pulsesEverywhere, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { dimmed = true }
        }
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: TTRadius.sm).fill(TTColor.surfaceRaised).frame(width: width, height: height)
    }
}

extension EnvironmentValues {
    /// Off in snapshot tests, so a skeleton drawn inside a screen (the Schedule loading state) gives a stable image.
    @Entry var skeletonPulses: Bool = true
}

#Preview("Surfaces") { SurfacesGallery() }
#Preview("Surfaces dark") { SurfacesGallery().preferredColorScheme(.dark) }
