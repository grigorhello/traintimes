import SwiftUI

// Every component state on one screen per group, for #Previews and the snapshot tests.
// Times are illustrative fixtures (D20), already formatted.

struct BadgesGallery: View {
    var body: some View {
        GalleryPage {
            FlowRow {
                StatusBadge(status: .onTime)
                StatusBadge(status: .delayed(minutes: 9))
                StatusBadge(status: .cancelled)
                StatusBadge(status: .stopSkipped)
                StatusBadge(status: .scheduled)
                StatusBadge(status: .lastReported(time: "7:29 AM"))
                StatusBadge(status: .offline)
            }
            HStack {
                ExpressTag()
                ExpressTag(iconOnly: true)
            }
            HStack {
                TimePill(time: "7:32", style: .slipped)
                TimePill(time: "7:41", style: .next)
                TimePill(time: "7:58", style: .later)
                TimePill(time: "8:05", style: .cancelled)
            }
            VStack(alignment: .leading, spacing: TTSpace.s3) {
                FreshnessLine(mode: .live)
                FreshnessLine(mode: .scheduledOnly)
                FreshnessLine(mode: .stale(lastReported: "7:29 AM"))
                FreshnessLine(mode: .offline(lastUpdated: "6:52 AM"))
            }
        }
    }
}

struct ButtonsGallery: View {
    var body: some View {
        GalleryPage {
            HStack {
                Button("button.add_alert") {}.buttonStyle(.ttPrimary)
                Button("button.repeat") {}.buttonStyle(.ttSecondary)
            }
            Button("button.open_settings") {}.buttonStyle(.ttText)
            HStack {
                Button("button.show_trains") {}.buttonStyle(.ttPrimary)
                Button("button.show_trains") {}.buttonStyle(.ttPrimary).disabled(true)
            }
            HStack(spacing: TTSpace.s2) {
                IconButton(systemName: "bell", label: "button.add_alert") {}
                IconButton(systemName: "bell.fill", label: "button.add_alert") {}
                IconButton(systemName: "arrow.up.arrow.down", label: "route.choose") {}
                IconButton(systemName: "star", label: "stations.yours") {}
                IconButton(systemName: "star.fill", label: "stations.yours") {}
                IconButton(systemName: "gearshape", label: "nav.settings") {}
                IconButton(systemName: "magnifyingglass", label: "route.choose_station", isSelected: true) {}
            }
            IconButton(systemName: "xmark", label: "button.now") {}
        }
    }
}

struct ControlsGallery: View {
    @State private var segment = 0

    var body: some View {
        GalleryPage {
            HStack(spacing: TTSpace.s2) {
                DayCell(weekday: "Today", day: "5", isSelected: true) {}
                DayCell(weekday: "Fri", day: "6") {}
                DayCell(weekday: "Sat", day: "7") {}
                DayCell(weekday: "Sun", day: "8") {}
                DayCell(weekday: "Mon", day: "9") {}
                DayCell(weekday: "Tue", day: "10") {}
                DayCell(weekday: "Wed", day: "11") {}
            }
            HStack(spacing: TTSpace.s1) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { index, letter in
                    DayChip(letter: letter, isOn: index < 5) {}
                }
            }
            SegmentedControl(selection: $segment, options: [(0, "alert.this_trip"), (1, "alert.repeat")])
        }
    }
}

struct SurfacesGallery: View {
    var body: some View {
        GalleryPage {
            Card {
                VStack(alignment: .leading, spacing: TTSpace.s1) {
                    Text("schedule.scheduled_arrival").font(TTFont.subhead).foregroundStyle(TTColor.inkSecondary)
                    Text(verbatim: "7:32 AM").font(TTFont.timeRow).monospacedDigit().foregroundStyle(TTColor.ink)
                    StatusBadge(status: .onTime)
                }
            }
            EmptyStateCard(
                systemImage: "exclamationmark.triangle",
                title: "schedule.empty.title",
                message: "schedule.empty.body",
                actionTitle: "route.choose"
            )
            SkeletonCard(pulses: false)
            Toast(message: String(format: String(localized: "alert.toast_on"), "7:32 AM"))
        }
    }
}

private struct GalleryPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: TTSpace.s6) { content }
            .padding(TTSpace.s5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(TTColor.canvas)
    }
}

/// Wraps badges onto more lines when they do not fit.
private struct FlowRow: Layout {
    var spacing: CGFloat = TTSpace.s2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in rows.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (origins: [CGPoint], width: CGFloat, height: CGFloat) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return (origins, maxX, y + rowHeight)
    }
}
