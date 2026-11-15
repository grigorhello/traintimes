import SwiftUI

/// Where the first launch draws things (TT-206), from the screen's size and safe area: positions on the boards are screen
/// points on a 390 × 844 pt phone, converted here to the safe-area space the views are laid out in. The launch still puts
/// the mark's centre 22 pt above the screen's middle (y 400 of 844), and the welcome's hub sits 64 pt below that.
struct WelcomeLayout {
    let size: CGSize
    let insets: EdgeInsets

    init(_ proxy: GeometryProxy) {
        size = proxy.size
        insets = proxy.safeAreaInsets
    }

    var screenHeight: CGFloat { size.height + insets.top + insets.bottom }
    /// The picture scales from the screen's width.
    var scale: CGFloat { size.width / 390 }

    /// A screen y in the safe-area space.
    func y(_ screenY: CGFloat) -> CGFloat { screenY - insets.top }

    /// The splash's mark: where the launch still has it.
    var splashHub: CGPoint { CGPoint(x: size.width / 2, y: y(screenHeight / 2 - 22)) }
    /// The welcome's hub, after the glide.
    static let glide: CGFloat = 64
    var welcomeHub: CGPoint { CGPoint(x: splashHub.x, y: splashHub.y + Self.glide) }

    /// A distance from the screen's bottom edge as a y in the safe-area space.
    func fromBottom(_ distance: CGFloat) -> CGFloat { y(screenHeight - distance) }
}

/// The welcome's picture of GO's network (TT-206): the hub (Union, under the app mark) and seven lines fanning from
/// Lakeshore West on the left round to Lakeshore East on the right. Board 3's points, hub to tip, in its 390 pt hero box.
struct NetworkGeometry {
    static let designHub = CGPoint(x: 195, y: 400)
    /// In `GOLineColor.lines` order: LW, MI, KI, BR, RH, ST, LE.
    static let lines: [[CGPoint]] = [
        [CGPoint(x: 195, y: 412), CGPoint(x: 38, y: 412)],
        [CGPoint(x: 195, y: 388), CGPoint(x: 132, y: 388), CGPoint(x: 62, y: 318), CGPoint(x: 38, y: 318)],
        [CGPoint(x: 195, y: 390), CGPoint(x: 100, y: 295), CGPoint(x: 100, y: 184)],
        [CGPoint(x: 195, y: 400), CGPoint(x: 195, y: 66)],
        [CGPoint(x: 195, y: 390), CGPoint(x: 290, y: 295), CGPoint(x: 290, y: 184)],
        [CGPoint(x: 195, y: 388), CGPoint(x: 258, y: 388), CGPoint(x: 328, y: 318), CGPoint(x: 352, y: 318)],
        [CGPoint(x: 195, y: 412), CGPoint(x: 352, y: 412)],
    ]
    /// A line's distance from the centre line: the lines draw from the centre out.
    static func order(_ index: Int) -> Int { abs(index - 3) }
    private static let cornerRadius: CGFloat = 16
    /// Two station rings, this far back from the tip, where they clear the hub.
    private static let ringsBack: [CGFloat] = [42, 78]

    let hub: CGPoint
    let scale: CGFloat

    func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: hub.x + (p.x - Self.designHub.x) * scale, y: hub.y + (p.y - Self.designHub.y) * scale)
    }

    func tip(_ index: Int) -> CGPoint {
        point(Self.lines[index][Self.lines[index].count - 1])
    }

    /// Hub to tip, the corners rounded with a 16 pt radius.
    func path(_ index: Int) -> Path {
        let points = Self.lines[index].map(point)
        var path = Path()
        path.move(to: points[0])
        for k in 1..<max(points.count - 1, 1) {
            let (p0, p1, p2) = (points[k - 1], points[k], points[k + 1])
            let l1 = hypot(p1.x - p0.x, p1.y - p0.y)
            let l2 = hypot(p2.x - p1.x, p2.y - p1.y)
            let u1 = CGPoint(x: (p1.x - p0.x) / l1, y: (p1.y - p0.y) / l1)
            let u2 = CGPoint(x: (p2.x - p1.x) / l2, y: (p2.y - p1.y) / l2)
            let r = min(Self.cornerRadius * scale, l1 / 2, l2 / 2)
            path.addLine(to: CGPoint(x: p1.x - u1.x * r, y: p1.y - u1.y * r))
            path.addQuadCurve(to: CGPoint(x: p1.x + u2.x * r, y: p1.y + u2.y * r), control: p1)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    /// The line's length, for the glint's 16 pt dash.
    func length(_ index: Int) -> CGFloat {
        let points = Self.lines[index]
        return zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) } * scale
    }

    /// The station rings, 42 and 78 pt back from the tip, left out where they would sit on the hub.
    func rings(_ index: Int) -> [CGPoint] {
        let reversed = Array(Self.lines[index].reversed())
        return Self.ringsBack.compactMap { back -> CGPoint? in
            var distance = back
            for (a, b) in zip(reversed, reversed.dropFirst()) {
                let l = hypot(b.x - a.x, b.y - a.y)
                if distance <= l {
                    let p = CGPoint(x: a.x + (b.x - a.x) * distance / l, y: a.y + (b.y - a.y) * distance / l)
                    guard hypot(p.x - Self.designHub.x, p.y - Self.designHub.y) > 70 else { return nil }
                    return point(p)
                }
                distance -= l
            }
            return nil
        }
    }
}

/// The app mark: the train glyph on the accent tile, with its accent glow (`.fl-app`). 96 pt on the splash, 76 on the
/// welcome; the corner radius scales with it.
struct AppMarkTile: View {
    let size: CGFloat

    var body: some View {
        Image("TrainTimesSymbol")
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(TTColor.onAccent)
            .frame(width: size, height: size)
            .background(TTColor.accent, in: RoundedRectangle(cornerRadius: size * 21.5 / 96))
            .shadow(color: TTColor.accent.opacity(0.28), radius: 17 * size / 96, x: 0, y: 14 * size / 96)
            .shadow(color: Color(red: 17 / 255, green: 24 / 255, blue: 39 / 255).opacity(0.10), radius: 1, x: 0, y: 1)
            .accessibilityHidden(true)
    }
}

/// The splash and the welcome's picture (board 1, board 3): the seven lines, their rings, the mark on the hub, and the name
/// under it on the splash. Laid out with the hub at `hub`; the welcome moves it down as a whole. `bloomed` draws it (each
/// part on its own delay), `folded` takes the lines back into the mark. Tiles are drawn by the caller when they fly (the
/// welcome); `drawsTiles` draws them here (the saved route's splash).
struct BloomStage: View {
    let layout: WelcomeLayout
    var markSize: CGFloat = 96
    let bloomed: Bool
    var folded = false
    var showsName = true
    var drawsTiles = false
    /// The glint's clock start (the welcome settled), nil for none.
    var glintFrom: Date?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var geometry: NetworkGeometry { NetworkGeometry(hub: layout.splashHub, scale: layout.scale) }
    private var drawn: Bool { bloomed && !folded }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<GOLineColor.lines.count, id: \.self) { index in
                line(index)
            }
            if let glintFrom, !reduceMotion {
                Glint(geometry: geometry, from: glintFrom)
            }
            if drawsTiles {
                ForEach(Array(GOLineColor.lines.enumerated()), id: \.offset) { index, entry in
                    LineTile(line: Line(id: entry.id, name: entry.name, colorHex: nil))
                        .scaleEffect(drawn || reduceMotion ? 1 : 0.6)
                        .opacity(drawn ? 1 : 0)
                        .animation(tileAnimation(index), value: drawn)
                        .position(geometry.tip(index))
                }
            }
            AppMarkTile(size: markSize)
                .scaleEffect(bloomed || reduceMotion ? 1 : 0.9)
                .animation(reduceMotion ? nil : LaunchMotion.mark, value: bloomed)
                .position(geometry.hub)
            Text("app.name")
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(TTColor.ink)
                .frame(height: 28)
                .opacity(showsName && drawn ? 1 : 0)
                .offset(y: bloomed || reduceMotion ? 0 : 10)
                .animation(nameAnimation, value: bloomed)
                .animation(LaunchMotion.nameOut, value: showsName)
                .animation(LaunchMotion.fold, value: folded)
                .position(x: geometry.hub.x, y: geometry.hub.y + 66 + 14)
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func stroke(_ index: Int) -> Color {
        let entry = GOLineColor.lines[index]
        return GOLineColor.color(
            for: Line(id: entry.id, name: entry.name, colorHex: nil), towardWhite: colorScheme == .dark ? 0.42 : 0
        )
    }

    @ViewBuilder private func line(_ index: Int) -> some View {
        let order = NetworkGeometry.order(index)
        let colour = stroke(index)
        geometry.path(index)
            .trim(from: 0, to: drawn ? 1 : 0)
            .stroke(colour, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            .animation(reduceMotion ? LaunchMotion.fade : folded ? LaunchMotion.fold : LaunchMotion.draw(order), value: drawn)
        ForEach(Array(geometry.rings(index).enumerated()), id: \.offset) { _, point in
            Circle()
                .fill(TTColor.canvas)
                .overlay(Circle().strokeBorder(colour, lineWidth: 2.5))
                .frame(width: 11.5, height: 11.5)
                .position(point)
                .opacity(drawn ? 1 : 0)
                .animation(reduceMotion ? LaunchMotion.fade : folded ? LaunchMotion.fold : LaunchMotion.rings(order), value: drawn)
        }
    }

    private func tileAnimation(_ index: Int) -> Animation {
        reduceMotion ? LaunchMotion.fade : folded ? LaunchMotion.fold : LaunchMotion.tile(NetworkGeometry.order(index))
    }

    private var nameAnimation: Animation {
        reduceMotion ? LaunchMotion.fade : folded ? LaunchMotion.fold : LaunchMotion.name
    }
}

/// One glint at a time runs down a line from its tip to the hub, a line every 1.3 s from 2.4 s after the welcome settles,
/// Lakeshore West first (the connector glint of D80).
private struct Glint: View {
    let geometry: NetworkGeometry
    let from: Date

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(from) - LaunchMotion.glintFirst
            if elapsed > 0 {
                let cycle = Int(elapsed / LaunchMotion.glintEvery)
                let index = cycle % GOLineColor.lines.count
                let within = elapsed - Double(cycle) * LaunchMotion.glintEvery
                if within < LaunchMotion.glintDuration {
                    let dash = LaunchMotion.glintLength / max(geometry.length(index), 1)
                    // Tip to hub: the dash's far end runs from the tip (1) down to the hub (0).
                    let head = 1 - within / LaunchMotion.glintDuration * (1 + dash)
                    geometry.path(index)
                        .trim(from: max(0, head), to: min(1, max(0, head + dash)))
                        .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A cold start with a saved route (TT-206): Bloom, then the lines and tiles fold back into the mark, the mark fades and
/// Schedule shows under it with its own cascade (D61). Never on return from the background: `RootView` shows it once.
struct LaunchSplash: View {
    /// The splash's last frame, still (snapshots).
    var atRest = false
    var onFinish: () -> Void = {}

    @State private var bloomed = false
    @State private var folded = false
    @State private var gone = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                TTColor.canvas.ignoresSafeArea()
                BloomStage(layout: WelcomeLayout(proxy), bloomed: bloomed || atRest, folded: folded, drawsTiles: true)
            }
        }
        .opacity(gone ? 0 : 1)
        .animation(LaunchMotion.markFade, value: gone)
        .allowsHitTesting(!folded)
        .task {
            guard !atRest else { return }
            // One frame at the launch still's pose first, so the motion starts from it.
            try? await Task.sleep(for: .milliseconds(16))
            bloomed = true
            try? await Task.sleep(for: LaunchMotion.bloomDuration)
            folded = true
            gone = true
            try? await Task.sleep(for: LaunchMotion.foldDuration)
            onFinish()
        }
    }
}
