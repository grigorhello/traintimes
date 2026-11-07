import SwiftUI

/// 18 pt radius surface. Light mode carries a 0 1 2 shadow at 6%; dark mode uses the canvas-to-surface step only.
struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(TTSpace.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TTColor.surface, in: RoundedRectangle(cornerRadius: TTRadius.lg))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 1, x: 0, y: 1)
    }
}

/// The one line that states the data mode (D14). Times are formatted by the one time formatter.
struct FreshnessLine: View {
    enum Mode: Hashable, Sendable {
        case live
        case scheduledOnly
        case stale(lastReported: String)
        case offline(lastUpdated: String)
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
        case .live: String(localized: "schedule.updated_just_now")
        case .scheduledOnly: String(localized: "freshness.scheduled_only")
        case .stale(let time): String(format: String(localized: "freshness.stale"), time)
        case .offline(let time): String(format: String(localized: "freshness.offline"), time)
        }
    }

    private var symbol: String? {
        switch mode {
        case .live, .stale: nil
        case .scheduledOnly: "clock"
        case .offline: "wifi.slash"
        }
    }
}

/// Short confirmation, e.g. "Alert on for the 7:32 AM train".
struct Toast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(TTFont.subhead)
            .monospacedDigit()
            .foregroundStyle(TTColor.surface)
            .padding(.horizontal, TTSpace.s4)
            .padding(.vertical, TTSpace.s3)
            .background(TTColor.ink, in: Capsule())
            .transition(.opacity.combined(with: .move(edge: .bottom)).animation(.easeOut(duration: 0.25)))
    }
}

struct EmptyStateCard: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: () -> Void = {}

    var body: some View {
        Card {
            VStack(spacing: TTSpace.s2) {
                Image(systemName: systemImage)
                    .font(.system(size: TTSize.iconMD + TTSpace.s2))
                    .foregroundStyle(TTColor.ink)
                    .padding(.bottom, TTSpace.s2)
                Text(title).font(TTFont.headline).foregroundStyle(TTColor.ink)
                Text(message).font(TTFont.subhead).foregroundStyle(TTColor.inkSecondary)
                if let actionTitle {
                    Button(actionTitle, action: action).buttonStyle(.ttText)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Off in snapshots so the image is stable.
    var pulses = true
    @State private var dimmed = false

    var body: some View {
        Card {
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
        }
        .opacity(dimmed ? 0.6 : 1)
        .onAppear {
            guard pulses, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { dimmed = true }
        }
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: TTRadius.sm).fill(TTColor.surfaceRaised).frame(width: width, height: height)
    }
}

#Preview("Surfaces") { SurfacesGallery() }
#Preview("Surfaces dark") { SurfacesGallery().preferredColorScheme(.dark) }
