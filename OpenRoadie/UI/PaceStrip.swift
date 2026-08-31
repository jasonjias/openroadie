import SwiftUI

/// Where a drive's time went, as one stacked bar plus a legend.
///
/// The bar is the tie-out made visible: the segments are the drive's whole
/// duration, so a drive that felt like it was mostly sitting still looks
/// like that. When the standing-still share is big enough to be the story,
/// `TrafficCallout` says so in words above it.
struct PaceStrip: View {
    let breakdown: PaceBands.Breakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(breakdown.presentBands) { band in
                        Rectangle()
                            .fill(RouteColoring.paceBands[band.rawValue].color)
                            .frame(width: width(for: band, in: geometry.size.width))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)

            // Only the bands this drive actually visited — an all-highway
            // run gets one entry, not five with four zeros.
            FlowRow(spacing: 12) {
                ForEach(breakdown.presentBands) { band in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(RouteColoring.paceBands[band.rawValue].color)
                            .frame(width: 7, height: 7)
                        Text(band.title)
                        Text(DriveFormatting.compactDuration(breakdown.seconds(band)))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Segment widths from the band's share of the total. A band with a
    /// nonzero share never renders thinner than a hairline — dropping it to
    /// invisible would make the bar stop tying out to the eye.
    private func width(for band: PaceBands.Band, in total: CGFloat) -> CGFloat {
        guard breakdown.total > 0 else { return 0 }
        let share = breakdown.seconds(band) / breakdown.total
        return max(3, total * CGFloat(share))
    }
}

/// The headline when a drive spent real time going nowhere.
struct TrafficCallout: View {
    let breakdown: PaceBands.Breakdown

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "car.side.rear.and.collision.and.car.side.front")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(DriveFormatting.compactDuration(breakdown.slowSeconds)) in traffic")
                    .font(.subheadline.weight(.semibold))
                Text("\(Int((breakdown.slowShare * 100).rounded()))% of this drive was under 15 mph")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// A wrapping HStack — the pace legend can carry five entries, which won't
/// fit on one line on a narrow phone, and labels must never truncate.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, in: width)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in layout(subviews: subviews, in: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, in width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += rows[rows.count - 1].indices.count == 1 ? size.width : size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
