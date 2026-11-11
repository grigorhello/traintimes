import SwiftUI

/// The glyph at the start of an alert capsule (TT-191, D71).
enum CapsuleGlyph: Equatable {
    /// The filled bell in accent: an alert on.
    case bellOn
    /// The outline bell in ink-secondary: an alert off, or the hint.
    case bellOff
    /// The crossed bell in the cancel ink: notifications are off.
    case notificationsOff
    /// The exclamation mark in the cancel ink: a save that failed.
    case failed
    /// The tick in accent: notifications are on again (D58).
    case confirmed

    var systemName: String {
        switch self {
        case .bellOn: "bell.fill"
        case .bellOff: "bell"
        case .notificationsOff: "bell.slash.fill"
        case .failed: "exclamationmark.circle.fill"
        case .confirmed: "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .bellOn, .confirmed: TTColor.accent
        case .bellOff: TTColor.inkSecondary
        case .notificationsOff, .failed: TTColor.cancelInk
        }
    }
}

/// The glass capsule above the tab bar (TT-191, D71; the canvas's `.acap`): 52 pt tall and as wide as its words, a 20 pt
/// glyph, one line in 15 pt semibold and at most one action, as a pill. Its glass is denser than the tab bar's.
///
/// With `panel` set it grows in place into the day panel: `panelWidth` wide (the tab bar's), 120 pt tall with the same 26 pt
/// corners, the panel's line, a tick that closes it and seven day tiles. The shape grows on `TTMotion.morph` with no
/// overshoot (the stage keeps its bottom edge fixed); the capsule's words and action leave in 70 ms and the panel's line and
/// tick arrive over 140 ms from 110 ms, so text never crosses; the tiles arrive once the shape is most of the way open,
/// each rising 6 pt from 0.94 on `TTMotion.cascade` and fading in, 20 ms apart from 160 ms. Reduce Motion: fades only.
struct AlertCapsuleView: View {
    struct Action {
        let title: LocalizedStringKey
        let perform: () -> Void
    }

    struct Panel {
        /// "7:32 AM · Mon to Fri".
        let words: String
        /// ISO weekdays lit, 1 is Monday.
        let days: [Int]
        let onToggle: (Int) -> Void
        let onDone: () -> Void
    }

    let glyph: CapsuleGlyph
    let words: String
    var action: Action?
    var panel: Panel?
    /// The day panel's width: the tab bar's, the screen less 20 pt on each side.
    var panelWidth: CGFloat = 350

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 52
    static let panelHeight: CGFloat = 120
    static let radius: CGFloat = 26
    /// The panel's top row: its line and the tick. The tiles start 4 pt inside it.
    private static let panelRowHeight: CGFloat = 68
    /// The panel's leading inset, and the glyph's box.
    private static let panelLeading: CGFloat = TTSpace.s4
    private static let glyphSize: CGFloat = 20
    private static let font = Font.system(size: 15, weight: .semibold)
    /// Words that give way leave in 70 ms; the words that take their place arrive over 140 ms from 110 ms.
    private static let leave = Animation.easeIn(duration: 0.07)
    private static let arrive = Animation.easeOut(duration: 0.14).delay(0.11)

    private var isOpen: Bool { panel != nil }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        row
            .frame(width: isOpen ? panelWidth : nil, height: isOpen ? Self.panelHeight : Self.height, alignment: .topLeading)
            // The panel's line, tick and tiles are laid out at the panel's size whether it is open or not, from the bottom
            // edge and centre the stage keeps still, so they never travel with the shape: the clip reveals them.
            .overlay(alignment: .bottom) { panelParts }
            .clipShape(shape)
            .modifier(CapsuleSurface(shape: shape))
            .contentShape(shape)
            // The shape and the glyph, which have no timing of their own; every fade below is scoped to its opacity.
            .animation(reduceMotion ? TTMotion.fade : TTMotion.morph, value: isOpen)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(isOpen ? "alert.panel" : "alert.capsule")
    }

    private var row: some View {
        HStack(spacing: 0) {
            Image(systemName: glyph.systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(glyph.tint)
                .frame(width: Self.glyphSize, height: Self.glyphSize)
                .padding(.trailing, TTSpace.s2)
                .accessibilityHidden(true)
            line(words)
                .animation(isOpen ? Self.leave : Self.arrive) { $0.opacity(isOpen ? 0 : 1) }
                .accessibilityHidden(isOpen)
            if let action {
                pill(action)
                    .padding(.leading, TTSpace.s3)
                    .animation(isOpen ? Self.leave : Self.arrive) { $0.opacity(isOpen ? 0 : 1) }
                    .allowsHitTesting(!isOpen)
                    .accessibilityHidden(isOpen)
            }
        }
        .padding(.leading, isOpen ? Self.panelLeading : 18)
        .padding(.trailing, action == nil ? 18 : TTSpace.s1)
        .frame(height: isOpen ? Self.panelRowHeight : Self.height)
    }

    private func line(_ text: String) -> some View {
        Text(verbatim: text)
            .font(Self.font)
            .tracking(-0.2)
            .monospacedDigit()
            .foregroundStyle(TTColor.ink)
            .lineLimit(1)
            .fixedSize()
    }

    /// The panel at its full size: the line after the glyph, the tick at the top right and the tiles under them.
    private var panelParts: some View {
        Color.clear
            .frame(width: panelWidth, height: Self.panelHeight)
            .allowsHitTesting(false)
            .overlay(alignment: .topLeading) { panelLine }
            .overlay(alignment: .topLeading) { tiles }
            .overlay(alignment: .topTrailing) { doneButton }
    }

    /// The panel's line, where the glyph ends up; it cross-fades when a day changes.
    private var panelLine: some View {
        line(panel?.words ?? "")
            .contentTransition(.opacity)
            .animation(TTMotion.fade, value: panel?.words)
            .animation(isOpen ? Self.arrive : Self.leave) { $0.opacity(isOpen ? 1 : 0) }
            .frame(height: Self.panelRowHeight)
            .padding(.leading, Self.panelLeading + Self.glyphSize + TTSpace.s2)
            .accessibilityHidden(!isOpen)
            .accessibilityIdentifier("alert.panel.days")
    }

    /// The canvas's `.apill`: 44 pt, 16 pt sides, the capsule's pill fill and accent words.
    private func pill(_ action: Action) -> some View {
        Button(action: action.perform) {
            Text(action.title)
                .font(Self.font)
                .tracking(-0.2)
                .foregroundStyle(TTColor.accent)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, TTSpace.s4)
                .frame(height: TTSize.targetMin)
                .background(TTColor.capsulePill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityIdentifier("alert.capsule.action")
    }

    /// The tick: a 36 pt accent circle 16 pt from the panel's top and 12 pt from its trailing edge, in a 44 pt target.
    private var doneButton: some View {
        Button { panel?.onDone() } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(TTColor.onAccent)
                .frame(width: 36, height: 36)
                .background(TTColor.accent, in: Circle())
                .frame(width: TTSize.targetMin, height: TTSize.targetMin)
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .padding(.top, TTSpace.s3)
        .padding(.trailing, TTSpace.s2)
        .animation(isOpen ? Self.arrive : .easeOut(duration: 0.1)) { $0.opacity(isOpen ? 1 : 0) }
        .allowsHitTesting(isOpen)
        .accessibilityLabel(Text("button.done"))
        .accessibilityIdentifier("alert.panel.done")
        .accessibilityHidden(!isOpen)
    }

    /// Seven tiles, Monday first, 4 pt apart inside 12 pt sides, starting 64 pt from the panel's top.
    private var tiles: some View {
        HStack(spacing: TTSpace.s1) {
            ForEach(Array(AlertDays.week.enumerated()), id: \.element) { index, day in
                DayTile(day: day, isOn: panel?.days.contains(day) ?? false) { panel?.onToggle(day) }
                    .modifier(TileArrival(isOpen: isOpen, order: index, reduceMotion: reduceMotion))
            }
        }
        .padding(.horizontal, TTSpace.s3)
        .padding(.top, Self.panelRowHeight - TTSpace.s1)
        .frame(width: panelWidth, alignment: .topLeading)
        .modifier(ArrivalGate(isOpen: isOpen))
        .accessibilityHidden(!isOpen)
    }
}

/// The day tiles take taps only once they have arrived, 300 ms after the panel opens: they stand at their place from the
/// first frame, under where Repeat was, so a quick second tap on Repeat would otherwise light a day the rider never saw.
private struct ArrivalGate: ViewModifier {
    let isOpen: Bool
    @State private var arrived = false

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(isOpen && arrived)
            .task(id: isOpen) {
                arrived = false
                guard isOpen else { return }
                try? await Task.sleep(for: .milliseconds(300))
                if !Task.isCancelled { arrived = true }
            }
    }
}

/// A day tile arriving in the panel: from 6 pt down and 0.94 on `TTMotion.cascade`, fading in over 120 ms, `order` × 20 ms
/// after the first at 160 ms. Reduce Motion: the fade alone. Each animation is scoped to its own properties, so the tile's
/// place never moves on them.
private struct TileArrival: ViewModifier {
    let isOpen: Bool
    let order: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let delay = 0.16 + 0.02 * Double(order)
        let moves = !isOpen && !reduceMotion
        content
            .animation(isOpen ? TTMotion.cascade.delay(delay) : nil) {
                $0.scaleEffect(moves ? 0.94 : 1).offset(y: moves ? 6 : 0)
            }
            .animation(isOpen ? .easeOut(duration: reduceMotion ? 0.18 : 0.12).delay(delay) : .easeIn(duration: 0.07)) {
                $0.opacity(isOpen ? 1 : 0)
            }
    }
}

/// A day tile (TT-191, D71; the canvas's `.dtile`): 44 pt tall with 12 pt corners and the short day name. On: solid accent
/// with a semibold white label, as the chosen day on Schedule; it fills in 120 ms and presses in from 0.92 on
/// `TTMotion.tilePress`. Off: the recessed fill (`offFill`), and only the colour fades, over 150 ms. In the panel the tiles
/// are plain fills on the glass.
struct DayTile: View {
    let day: Int
    let isOn: Bool
    let action: () -> Void
    var offFill: Color = TTColor.capsuleTile

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Each time the tile is lit it presses again.
    @State private var presses = 0

    var body: some View {
        Button(action: action) {
            Text(verbatim: AlertDays.shortName(day))
                .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                .tracking(-0.1)
                .foregroundStyle(isOn ? TTColor.onAccent : TTColor.inkSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: TTSize.targetMin)
                .background(isOn ? TTColor.accent : offFill, in: RoundedRectangle(cornerRadius: TTRadius.md, style: .continuous))
                .animation(.easeOut(duration: isOn ? 0.12 : 0.15), value: isOn)
                .contentShape(RoundedRectangle(cornerRadius: TTRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyframeAnimator(initialValue: 1.0, trigger: presses) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            MoveKeyframe(0.92)
            SpringKeyframe(1.0, duration: 0.5, spring: TTMotion.tilePressCurve.spring)
        }
        .onChange(of: isOn) { _, isOn in
            if isOn, !reduceMotion { presses += 1 }
        }
        .accessibilityLabel(Text(verbatim: AlertDays.fullName(day)))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("alert.day.\(day)")
    }
}

/// The capsule's glass: Liquid Glass under the capsule's dense fill on iOS 26; before it, and when `rendersGlass` is off
/// (snapshots), the same fill over the regular material with the canvas's glass shadow.
private struct CapsuleSurface<S: Shape>: ViewModifier {
    @Environment(\.rendersGlass) private var rendersGlass
    @Environment(\.colorScheme) private var colorScheme
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26, *), rendersGlass {
            content
                .background(TTColor.capsuleGlass, in: shape)
                .glassEffect(.regular, in: shape)
        } else {
            content
                .background(TTColor.capsuleGlass, in: shape)
                .background(.regularMaterial, in: shape)
                .shadow(color: colorScheme == .dark ? .black.opacity(0.45) : TTColor.ink.opacity(0.14), radius: 15, x: 0, y: 10)
        }
    }
}

/// How a capsule came on screen: at rest (already up at the first draw, as in snapshots), rising (none was up), or taking
/// the place of one that was.
enum CapsuleArrival: Equatable {
    case rest
    case rise
    case swap
}

/// How a capsule leaves: dropping away (it timed out or was dismissed), fading in place under the one that takes its place,
/// or, for the day panel, fading from 0.96 with no travel so its tiles never lie across the cards.
enum CapsuleExit: Equatable {
    case drop
    case swap
    case fade
}

/// Where alert capsules come and go (TT-191, D71; the spec board's Motion): one at a time, at the bottom of its space. A
/// capsule rises 12 pt from 0.94 on `TTMotion.toast` while it fades in over 150 ms, so it never crosses the tab bar, and
/// leaves 8 pt down over 160 ms. A new item while one is up takes its place: the old one fades out in 120 ms and the new one
/// fades in over 180 ms from 60 ms, nothing rising again. An item with the same id changes in place (Repeat growing the
/// capsule into the day panel). `isPanel` says which items leave as the panel does. Reduce Motion: 180 ms fades.
///
/// Driven from its own state, each property with its own `.animation(_:value:)`, not by transitions (TT-166: a custom
/// transition left the opacity unanimated on the simulator).
struct GlassCapsuleStage<Item: Identifiable & Equatable, Content: View>: View {
    let item: Item?
    let isPanel: (Item) -> Bool
    let content: (Item) -> Content

    /// What is on screen: the item and any that are leaving.
    @State private var entries: [Entry]

    /// An item already there at the first draw stands at rest; later ones rise.
    init(item: Item?, isPanel: @escaping (Item) -> Bool = { _ in false }, @ViewBuilder content: @escaping (Item) -> Content) {
        self.item = item
        self.isPanel = isPanel
        self.content = content
        _entries = State(initialValue: item.map { [Entry(item: $0, arrival: .rest)] } ?? [])
    }

    private struct Entry: Identifiable {
        var item: Item
        let arrival: CapsuleArrival
        var exit: CapsuleExit?
        var id: Item.ID { item.id }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(entries) { entry in
                CapsuleMotion(arrival: entry.arrival, exit: entry.exit) { content(entry.item) }
                    .zIndex(entry.exit == nil ? 1 : 0)
            }
        }
        .onChange(of: item) { _, new in update(new) }
        // Off screen once the exits have run.
        .task(id: entries.filter { $0.exit != nil }.map(\.id)) {
            guard entries.contains(where: { $0.exit != nil }) else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            entries.removeAll { $0.exit != nil }
        }
    }

    private func update(_ new: Item?) {
        let current = entries.lastIndex { $0.exit == nil }
        if let new, let current, entries[current].id == new.id {
            entries[current].item = new
            return
        }
        if let current {
            let leaving = entries[current].item
            entries[current].exit = new != nil ? .swap : isPanel(leaving) ? .fade : .drop
        }
        if let new {
            entries.append(Entry(item: new, arrival: current == nil ? .rise : .swap))
        }
    }
}

/// One capsule's arrival and exit.
private struct CapsuleMotion<Content: View>: View {
    let arrival: CapsuleArrival
    let exit: CapsuleExit?
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived: Bool

    init(arrival: CapsuleArrival, exit: CapsuleExit?, @ViewBuilder content: () -> Content) {
        self.arrival = arrival
        self.exit = exit
        self.content = content()
        _arrived = State(initialValue: arrival == .rest)
    }

    private enum Pose: Equatable {
        /// Waiting to rise: 12 pt low at 0.94, unseen.
        case below
        /// Waiting to fade in where it stands.
        case unseen
        case rest
        case dropped
        case swappedOut
        case faded
    }

    private var pose: Pose {
        switch exit {
        case .drop: .dropped
        case .swap: .swappedOut
        case .fade: .faded
        case nil: arrived ? .rest : arrival == .rise ? .below : .unseen
        }
    }

    var body: some View {
        content
            .scaleEffect(scale, anchor: .bottom)
            .offset(y: offset)
            .animation(transformAnimation, value: pose)
            .opacity(pose == .rest ? 1 : 0)
            .animation(opacityAnimation, value: pose)
            // The screen's animations stop here; the two above run inside it.
            .transaction { $0.animation = nil }
            .allowsHitTesting(exit == nil)
            .onAppear { arrived = true }
    }

    private var scale: CGFloat {
        guard !reduceMotion else { return 1 }
        return switch pose {
        case .below: 0.94
        case .faded: 0.96
        case .unseen, .rest, .dropped, .swappedOut: 1
        }
    }

    private var offset: CGFloat {
        guard !reduceMotion else { return 0 }
        return switch pose {
        case .below: 12
        case .dropped: 8
        case .unseen, .rest, .swappedOut, .faded: 0
        }
    }

    private var transformAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return switch pose {
        case .rest: TTMotion.toast
        case .dropped: .easeIn(duration: 0.16)
        case .faded: .easeIn(duration: 0.12)
        case .below, .unseen, .swappedOut: nil
        }
    }

    private var opacityAnimation: Animation? {
        guard !reduceMotion else { return TTMotion.fade }
        return switch pose {
        case .rest: arrival == .swap ? .easeOut(duration: 0.18).delay(0.06) : .easeOut(duration: 0.15)
        case .dropped: .easeIn(duration: 0.16)
        case .swappedOut, .faded: .easeIn(duration: 0.12)
        case .below, .unseen: nil
        }
    }
}

/// The timeline fades under a capsule (the canvas's `.acap-veil`), as it does under the tab bar, so no card shows through
/// the words: the canvas from clear to 82 % at 46 % to 90 %, 200 pt up from the screen's bottom edge and 300 pt under the
/// day panel. It fades in over 200 ms and out 100 ms later; its height changes only while it shows.
struct CapsuleVeil: View {
    let isShown: Bool
    let isTall: Bool
    @State private var tall: Bool

    init(isShown: Bool, isTall: Bool) {
        self.isShown = isShown
        self.isTall = isTall
        _tall = State(initialValue: isTall)
    }

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: TTColor.canvas.opacity(0), location: 0),
                .init(color: TTColor.canvas.opacity(0.82), location: 0.46),
                .init(color: TTColor.canvas.opacity(0.9), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: tall ? 300 : 200)
        .opacity(isShown ? 1 : 0)
        .animation(isShown ? .easeOut(duration: 0.2) : .easeOut(duration: 0.2).delay(0.1), value: isShown)
        .onChange(of: isTall) { _, isTall in
            if isShown { tall = isTall }
        }
        .onChange(of: isShown) { _, isShown in
            if isShown { tall = isTall }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
