import SwiftUI

/// The ride strip under the day strip while a ride runs (TT-172; one line since TT-205, D93, *Live-Schedule*): the Live dot,
/// the ride screen's line ("Clarkson in", "Clarkson is next", "Arriving at Clarkson", "This is Clarkson"), the minutes in
/// the accent, a chevron. A tap opens Trip details in ride mode.
struct RideStripView: View {
    let strip: RideStrip
    var onOpen: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: TTSpace.s2) {
                LiveDot(isLive: strip.isLive)
                Text(strip.line)
                    .font(TTFont.headline)
                    .tracking(-0.4)
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(1)
                Spacer(minLength: TTSpace.s2)
                Text(strip.countdown)
                    .font(TTFont.stripMinutes)
                    .tracking(-0.4)
                    .monospacedDigit()
                    .foregroundStyle(TTColor.accent)
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeOut(duration: 0.15), value: strip.countdown)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TTColor.inkTertiary)
                    .accessibilityHidden(true)
            }
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 12))
            .background(TTColor.accentSoft, in: RoundedRectangle(cornerRadius: TTRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: TTRadius.lg)
                    .strokeBorder(TTColor.accent.opacity(colorScheme == .dark ? 0.20 : 0.14), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: TTRadius.lg))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("schedule.ride")
    }
}

/// What the strip under the day strip shows (TT-175; TT-205, D93): the ride strip, train detection's question, or the
/// watched-trip strip. Nothing shows while the matcher checks (no checking strip), and no countdown before departure: the
/// train's own card says it.
enum RideStripContent: Equatable {
    case riding, asking, otherwise

    init(isRiding: Bool, detection: TrainMatcher.State) {
        if isRiding {
            self = .riding
        } else if case .asking = detection {
            self = .asking
        } else {
            self = .otherwise
        }
    }

    @MainActor init(_ onBoard: OnBoard?) {
        self.init(isRiding: onBoard?.activeRide != nil, detection: onBoard?.detection ?? .idle)
    }
}

/// The strip under the day strip: the ride strip while a ride runs, train detection's question (TT-175), else `otherwise`
/// (the watched-trip strip). The ride strip drops in 12 pt from under the day strip, from 0.97, on `RideMotion.rise`; the
/// question lands from −10 pt and 0.97 on `RideMotion.press`, and its Yes folds it into the ride strip on `RideMotion.fold`.
/// Reduce Motion fades. The ride strip's digits follow its clock each second.
///
/// The strips share one top-aligned `ZStack`, which stays while one replaces another, so the leaving strip fades where it
/// was and the arriving one lands over it (the animation is on the stack, which a `Group` would have handed to the
/// inserted strip, too late for its transition). `otherwise` stays a direct child of the header, as before. Schedule
/// moves the timeline with the strip (`rideStripMotion(_:)`).
struct RideStripSlot<Otherwise: View>: View {
    let onBoard: OnBoard?
    var onOpen: () -> Void = {}
    @ViewBuilder var otherwise: Otherwise

    @Environment(\.timeFormatter) private var formatter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The question was showing before this change: its Yes folds into the ride strip.
    @State private var wasAsking = false

    var body: some View {
        let detection = onBoard?.detection ?? .idle
        let content = RideStripContent(isRiding: onBoard?.activeRide != nil, detection: detection)
        Group {
            if content == .otherwise {
                otherwise
            } else {
                ZStack(alignment: .top) {
                    strip(content, detection: detection)
                }
                .padding(.horizontal, TTSpace.s5)
                .padding(.top, -2)
                .transition(drop(by: -12))
            }
        }
        .animation(animation(for: content), value: content)
        .onChange(of: content, initial: true) { wasAsking = content == .asking }
    }

    @ViewBuilder
    private func strip(_ content: RideStripContent, detection: TrainMatcher.State) -> some View {
        switch content {
        case .riding:
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                if let strip = onBoard?.strip(formatter: formatter) {
                    RideStripView(strip: strip, onOpen: onOpen)
                }
            }
            .transition(drop(by: -12))
        case .asking:
            if case .asking(let question) = detection, let shown = TrainQuestion(question) {
                TrainQuestionCard(
                    question: shown,
                    onYes: { train in Task { if await onBoard?.accept(train) == true { onOpen() } } },
                    onNo: { onBoard?.decline() }
                )
                .transition(drop(by: -10))
            }
        case .otherwise:
            EmptyView()
        }
    }

    private func drop(by offset: CGFloat) -> AnyTransition {
        reduceMotion ? .opacity : .offset(y: offset).combined(with: .scale(scale: 0.97, anchor: .top)).combined(with: .opacity)
    }

    private func animation(for content: RideStripContent) -> Animation {
        if reduceMotion { return TTMotion.fade }
        switch content {
        case .riding: return wasAsking ? RideMotion.fold : RideMotion.rise
        case .asking: return RideMotion.press
        case .otherwise: return RideMotion.rise
        }
    }
}

extension View {
    /// Moves what sits under the header (the timeline) with the strip under the day strip when it changes, on
    /// `RideMotion.fold` (a fade with Reduce Motion), so a strip or the question no longer pushes the timeline down in one
    /// frame. The strip itself keeps its own spring (`RideStripSlot`). Only this modifier reads the strip's state, so a change
    /// does not redraw the screen it wraps.
    func rideStripMotion(_ onBoard: OnBoard?) -> some View {
        modifier(RideStripMotion(onBoard: onBoard))
    }
}

private struct RideStripMotion: ViewModifier {
    let onBoard: OnBoard?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? TTMotion.fade : RideMotion.fold, value: RideStripContent(onBoard))
    }
}
