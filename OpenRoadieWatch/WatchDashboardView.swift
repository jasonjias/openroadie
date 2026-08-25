import SwiftUI

/// The wrist view of the drive: glanceable speed against the limit.
struct WatchDashboardView: View {
    let model: WatchSessionModel

    var body: some View {
        VStack(spacing: 2) {
            if let speed = model.speedMph {
                Text("\(speed)")
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(model.isOverLimit ? .red : .primary)
                    .contentTransition(.numericText())
                Text("mph")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(model.isDriving ? "—" : "No drive")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                if !model.isDriving {
                    Text("Start one on your iPhone")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 6) {
                if let limit = model.limitMph {
                    Text("LIMIT \(limit)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.white, in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.black, lineWidth: 1))
                }
                if let road = model.road {
                    Text(road)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }

            if model.isDriving {
                Text("\(model.distanceMiles, format: .number.precision(.fractionLength(1))) mi · \(formattedDuration)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            if let alert = model.lastAlert {
                Text(alert)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 4)
    }

    private var formattedDuration: String {
        let minutes = model.durationSeconds / 60
        if minutes >= 60 {
            return "\(minutes / 60):\(String(format: "%02d", minutes % 60)) hr"
        }
        return "\(minutes) min"
    }
}
