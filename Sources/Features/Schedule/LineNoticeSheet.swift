import SwiftUI

/// One line notice as the sheet shows it, copy and times already formatted.
struct LineNoticeRow: Identifiable, Equatable {
    let id: String
    /// "Lakeshore West notice".
    let title: String
    /// "Delays of up to 15 min near Port Credit".
    let text: String
    let details: String?
    /// "Reported at 7:12 AM".
    let reported: String
}

/// The line notice sheet (TT-132), opened from "Line notice" in the freshness row: each notice in full with the time it
/// was reported, in the canvas's disruption banner (`components.png`), and its dismiss button. The sheet closes once no
/// notice is left. The title bar follows Trip details.
struct LineNoticeSheet: View {
    let viewModel: ScheduleViewModel

    @Environment(\.timeFormatter) private var formatter
    @Environment(\.dismiss) private var dismiss

    /// Canvas `.sheet`: 10 pt padding, the 5 pt grabber and its 16 pt margin, then the 12 pt gap before the title row.
    private static let titleTop: CGFloat = 10 + 5 + TTSpace.s4 + TTSpace.s3
    /// The close button bleeds 10 pt into the side margin, as in Trip details.
    private static let closeBleed: CGFloat = 10
    /// Canvas `.banner .icon-btn`: the 44 pt dismiss button bleeds 10 pt above and below.
    private static let dismissBleed: CGFloat = 10

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            ScrollView {
                VStack(spacing: TTSpace.s3) {
                    ForEach(viewModel.noticeRows(formatter)) { row in
                        banner(row)
                    }
                }
                .padding(.horizontal, TTSpace.s5)
                .padding(.bottom, TTSpace.s4)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(TTColor.surface)
        .onChange(of: viewModel.todayNotices.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet.lineNotices")
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(TTRadius.sheet)
        .presentationBackground(TTColor.surface)
    }

    private var titleBar: some View {
        HStack {
            Text("schedule.line_notice")
                .font(TTFont.navTitle)
                .foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            IconButton(systemName: "xmark", label: "button.close") { dismiss() }
                .accessibilityIdentifier("notice.close")
        }
        .padding(.leading, TTSpace.s5)
        .padding(.trailing, TTSpace.s5 - Self.closeBleed)
        .padding(.top, Self.titleTop)
        .padding(.bottom, TTSpace.s3)
    }

    /// Canvas `.banner`: delay-fill, delay-ink, the notice icon, the headline and the notice, and a dismiss button.
    private func banner(_ row: LineNoticeRow) -> some View {
        HStack(alignment: .top, spacing: TTSpace.s3) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: TTSize.iconSM, weight: .semibold))
                .frame(height: TTSize.iconMD)
            VStack(alignment: .leading, spacing: TTSpace.s1) {
                Text(verbatim: row.title)
                    .font(TTFont.headline)
                Text(verbatim: row.text)
                    .font(TTFont.footnote)
                if let details = row.details {
                    Text(verbatim: details)
                        .font(TTFont.footnote)
                }
                Text(verbatim: row.reported)
                    .font(TTFont.footnote)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button {
                viewModel.dismissNotice(row.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: TTSize.iconButtonGlyph))
                    .frame(width: TTSize.targetMin, height: TTSize.targetMin)
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
            .padding(.vertical, -Self.dismissBleed)
            .accessibilityLabel(Text("notice.dismiss"))
            .accessibilityIdentifier("notice.dismiss")
        }
        .foregroundStyle(TTColor.delayInk)
        .padding(.vertical, TTSpace.s3)
        .padding(.leading, TTSpace.s4)
        .padding(.trailing, TTSpace.s2)
        .background(TTColor.delayFill, in: RoundedRectangle(cornerRadius: TTRadius.md))
    }
}

#Preview {
    let model = ScheduleViewModel.fixtures(scenario: .delayed)
    return LineNoticeSheet(viewModel: model).task { await model.loadIfNeeded() }
}
