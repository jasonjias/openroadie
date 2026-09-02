import ActivityKit
import SwiftUI
import WidgetKit

/// The live drive on the Lock Screen and in the Dynamic Island.
struct DriveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DriveActivityAttributes.self) { context in
            LockScreenDriveView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: context.state.isPaused ? "pause.circle.fill" : "car.fill")
                            .foregroundStyle(context.state.isPaused ? .orange : .green)
                        Text(speedText(context.state))
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(miles(context.state.distanceMeters))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.roadName ?? "OpenRoadie")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(context.attributes.startDate, style: .timer)
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .frame(maxWidth: 60, alignment: .trailing)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.circle.fill" : "car.fill")
                    .foregroundStyle(context.state.isPaused ? .orange : .green)
            } compactTrailing: {
                Text(context.state.speedMph.map { "\($0)" } ?? "–")
                    .monospacedDigit()
                    .foregroundStyle(.green)
            } minimal: {
                Image(systemName: "car.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private func speedText(_ state: DriveActivityAttributes.ContentState) -> String {
        state.speedMph.map { "\($0) mph" } ?? "— mph"
    }

    private func miles(_ meters: Double) -> String {
        String(format: "%.1f mi", meters / 1609.344)
    }
}

private struct LockScreenDriveView: View {
    let context: ActivityViewContext<DriveActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: context.state.isPaused ? "pause.circle.fill" : "car.fill")
                .font(.title2)
                .foregroundStyle(context.state.isPaused ? .orange : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.isPaused ? "Paused" : "Driving")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(context.state.speedMph.map { "\($0) mph" } ?? "— mph")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(context.attributes.startDate, style: .timer)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .frame(maxWidth: 60, alignment: .trailing)
                Text(String(format: "%.1f mi", context.state.distanceMeters / 1609.344))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .padding(14)
    }
}
