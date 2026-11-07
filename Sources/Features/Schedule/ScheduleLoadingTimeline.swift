import SwiftUI

/// The first timetable loading (TT-115, `schedule-loading.png`): the rail, gridlines and Now line stay, with three skeleton
/// cards, grey pills and grey markers where the first trains will be. Same across geometry as `ScheduleTimeline`, and the
/// skeleton sits where the canvas board puts it. Decoration only: the freshness line says "Loading timetable".
struct ScheduleLoadingTimeline: View {
    let now: Date
    let formatter: any TimeFormatting

    private static let labelColumn = TTTimeline.leftInset + TimePill.railSize.width
    private static let railX = labelColumn + 10
    private static let railWidth: CGFloat = 2
    private static let markerSize: CGFloat = 12
    private static let nowDot: CGFloat = 10
    private static let cardX = railX + markerSize / 2 + TTTimeline.connectorLength
    /// Now sits 2 min below the top edge, as on the loaded timeline.
    private static let nowY = CGFloat(TTTimeline.nowOffsetFromTopMinutes) * TTTimeline.pointsPerMinute
    /// The canvas board's skeleton markers, and each skeleton card's top above its marker.
    private static let markerYs: [CGFloat] = [91, 273, 434]
    private static let cardAnchor: CGFloat = 34
    private static let height: CGFloat = 560

    private struct Gridline: Hashable {
        let time: Date
        let y: CGFloat
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(gridlines, id: \.time) { gridline in
                Rectangle()
                    .fill(TTColor.hairline)
                    .frame(height: 1)
                    .padding(.leading, Self.railX)
                    .padding(.trailing, TTSpace.s5)
                    .centred(y: gridline.y)
                if showsLabel(at: gridline.y) {
                    label(Text(formatter.railTime(gridline.time)), at: gridline.y)
                        .foregroundStyle(TTColor.inkSecondary)
                }
            }
            Rectangle()
                .fill(TTColor.hairline)
                .frame(width: Self.railWidth, height: Self.height)
                .offset(x: Self.railX - Self.railWidth / 2)
            ForEach(Array(Self.markerYs.enumerated()), id: \.offset) { index, y in
                Rectangle()
                    .fill(TTColor.hairline)
                    .frame(width: TTTimeline.connectorLength, height: Self.railWidth)
                    .offset(x: Self.railX + Self.markerSize / 2, y: y - Self.railWidth / 2)
                SkeletonCard(layout: .departure(isNext: index == 0))
                    .padding(.leading, Self.cardX)
                    .padding(.trailing, TTSpace.s5)
                    .offset(y: y - Self.cardAnchor)
                Capsule()
                    .fill(TTColor.surfaceRaised)
                    .frame(width: TimePill.railSize.width, height: TimePill.railSize.height)
                    .centred(x: TTTimeline.leftInset + TimePill.railSize.width / 2, y: y)
                Circle()
                    .fill(TTColor.surface)
                    .overlay(Circle().strokeBorder(TTColor.hairline, lineWidth: Self.railWidth))
                    .frame(width: Self.markerSize, height: Self.markerSize)
                    .centred(x: Self.railX, y: y)
            }
            nowLine
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: Self.height, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Every 15 min of Toronto wall-clock time from the top edge down; Toronto's offset is whole hours, so steps from
    /// the reference date land on :00, :15, :30 and :45 (as in `TimelineLayout`).
    private var gridlines: [Gridline] {
        let step = TimeInterval(TTTimeline.gridlineEveryMinutes * 60)
        let top = now.addingTimeInterval(-TimeInterval(TTTimeline.nowOffsetFromTopMinutes * 60))
        var time = Date(timeIntervalSinceReferenceDate: (top.timeIntervalSinceReferenceDate / step).rounded(.up) * step)
        var lines: [Gridline] = []
        while true {
            let y = Self.nowY + CGFloat(time.timeIntervalSince(now) / 60) * TTTimeline.pointsPerMinute
            guard y <= Self.height else { return lines }
            lines.append(Gridline(time: time, y: y))
            time = time.addingTimeInterval(step)
        }
    }

    /// A gridline label hides near a pill or the "Now" label, as on the loaded timeline.
    private func showsLabel(at y: CGFloat) -> Bool {
        !(Self.markerYs + [Self.nowY]).contains { abs($0 - y) <= TTTimeline.pillLabelHideDistance }
    }

    @ViewBuilder private var nowLine: some View {
        Rectangle()
            .fill(TTColor.accent)
            .frame(height: Self.railWidth)
            .padding(.leading, Self.railX)
            .padding(.trailing, TTSpace.s5)
            .centred(y: Self.nowY)
        Circle()
            .fill(TTColor.accent)
            .frame(width: Self.nowDot, height: Self.nowDot)
            .centred(x: Self.railX, y: Self.nowY)
        label(Text("button.now"), at: Self.nowY, weight: .semibold)
            .foregroundStyle(TTColor.accent)
    }

    /// Footnote text, right-aligned in the label column and centred on `y`.
    private func label(_ text: Text, at y: CGFloat, weight: Font.Weight = .regular) -> some View {
        text
            .font(TTFont.footnote.weight(weight))
            .monospacedDigit()
            .lineLimit(1)
            .frame(width: Self.labelColumn, alignment: .trailing)
            .centred(y: y)
    }
}

private extension View {
    /// Centres the view on a point of the timeline whatever its size: on `y`, and on `x` when given.
    func centred(x: CGFloat? = nil, y: CGFloat) -> some View {
        frame(width: x == nil ? nil : 0, height: 0)
            .offset(x: x ?? 0, y: y)
    }
}
