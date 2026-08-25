import SwiftData
import SwiftUI
import UIKit

/// Permit-practice math, pure and tested: how much of a drive counts as
/// night driving (8 PM – 6 AM, the common DMV definition — verify local
/// rules), and the running totals a supervisor signs off on.
enum PracticeMath {
    /// Seconds of [start, end] that fall between 20:00 and 06:00.
    static func nightSeconds(start: Date, end: Date, calendar: Calendar = .current) -> TimeInterval {
        guard end > start else { return 0 }
        var total: TimeInterval = 0
        // Walk each calendar day the drive touches (drives are hours, not weeks).
        var dayStart = calendar.startOfDay(for: start)
        while dayStart < end {
            let morning = calendar.date(byAdding: .hour, value: 6, to: dayStart)!
            let evening = calendar.date(byAdding: .hour, value: 20, to: dayStart)!
            let midnight = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            // Non-overlapping windows per day: [00:00, 06:00) and
            // [20:00, 24:00) — the next iteration covers past midnight.
            total += overlap(start, end, dayStart, morning)
            total += overlap(start, end, evening, midnight)
            dayStart = midnight
        }
        return total
    }

    private static func overlap(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> TimeInterval {
        max(0, min(aEnd, bEnd).timeIntervalSince(max(aStart, bStart)))
    }
}

/// The teen/permit practice log: total and night hours against DMV-style
/// goals, every logged drive, and a printable PDF a supervisor can sign.
/// All computed from the trips already recorded — nothing extra to track.
struct PracticeLogView: View {
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @AppStorage("practiceTotalHoursGoal") private var totalGoal = 50.0
    @AppStorage("practiceNightHoursGoal") private var nightGoal = 10.0
    @State private var pdfURL: URL?

    private var completed: [Trip] { trips.filter { $0.endDate != nil } }

    private var totalHours: Double {
        completed.compactMap(\.duration).reduce(0, +) / 3600
    }

    private var nightHours: Double {
        completed.reduce(0) { sum, trip in
            guard let end = trip.endDate else { return sum }
            return sum + PracticeMath.nightSeconds(start: trip.startDate, end: end)
        } / 3600
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 24) {
                    progressRing("Total", hours: totalHours, goal: totalGoal, color: .blue)
                    progressRing("Night", hours: nightHours, goal: nightGoal, color: .indigo)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            } footer: {
                Text("Night = 8 PM–6 AM. Goals are estimates — always verify your state's requirements with your DMV.")
            }

            Section {
                Stepper("Total goal: \(Int(totalGoal)) hrs", value: $totalGoal, in: 10...100, step: 5)
                Stepper("Night goal: \(Int(nightGoal)) hrs", value: $nightGoal, in: 0...50, step: 5)
            } header: {
                Text("Goals")
            }

            Section {
                if let pdfURL {
                    ShareLink("Share signed log (PDF)", item: pdfURL)
                } else {
                    Button("Generate DMV-style PDF") {
                        pdfURL = PracticePDF.render(trips: completed, totalHours: totalHours, nightHours: nightHours)
                    }
                }
            } footer: {
                Text("A printable log of every drive with totals and supervisor signature lines.")
            }

            Section {
                ForEach(completed.prefix(100)) { trip in
                    let night = PracticeMath.nightSeconds(start: trip.startDate, end: trip.endDate ?? trip.startDate)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trip.startDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                                .font(.subheadline.weight(.medium))
                            Text("\(DriveFormatting.duration(trip.duration ?? 0)) · \(DriveFormatting.miles(fromMeters: trip.distance))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if night > 60 {
                            Label("Night", systemImage: "moon.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.indigo)
                        } else {
                            Label("Day", systemImage: "sun.max.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            } header: {
                Text("Drives (\(completed.count))")
            }
        }
        .navigationTitle("Practice Log")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { pdfURL = nil }
    }

    private func progressRing(_ label: String, hours: Double, goal: Double, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color(.systemFill), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: min(1, goal > 0 ? hours / goal : 0))
                    .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", hours))
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                    Text("of \(Int(goal))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 92, height: 92)
            Text("\(label) hours")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

/// Renders the practice log as a paginated US-Letter PDF: header, totals,
/// a drive table, and signature lines for driver and supervisor.
@MainActor
enum PracticePDF {
    static func render(trips: [Trip], totalHours: Double, nightHours: Double) -> URL? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenRoadie Practice Log.pdf")

        let title = [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 20)]
        let heading = [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 11)]
        let body = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 10)]
        let small = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 8),
                     .foregroundColor: UIColor.gray]

        do {
            try renderer.writePDF(to: url) { context in
                var y: CGFloat = 0
                func page() {
                    context.beginPage()
                    y = 40
                }
                page()

                "Supervised Driving Practice Log".draw(at: CGPoint(x: 40, y: y), withAttributes: title)
                y += 28
                "Generated by OpenRoadie on \(Date.now.formatted(date: .abbreviated, time: .shortened)) · Night = 8 PM–6 AM · Verify requirements with your DMV"
                    .draw(at: CGPoint(x: 40, y: y), withAttributes: small)
                y += 22
                String(format: "Total practice: %.1f hours   ·   Night practice: %.1f hours   ·   Drives: %d",
                       totalHours, nightHours, trips.count)
                    .draw(at: CGPoint(x: 40, y: y), withAttributes: heading)
                y += 26

                // Table header
                func tableHeader() {
                    "Date".draw(at: CGPoint(x: 40, y: y), withAttributes: heading)
                    "Start–End".draw(at: CGPoint(x: 170, y: y), withAttributes: heading)
                    "Duration".draw(at: CGPoint(x: 300, y: y), withAttributes: heading)
                    "Miles".draw(at: CGPoint(x: 380, y: y), withAttributes: heading)
                    "Night".draw(at: CGPoint(x: 450, y: y), withAttributes: heading)
                    y += 16
                }
                tableHeader()

                for trip in trips.reversed() {
                    if y > 700 {
                        page()
                        tableHeader()
                    }
                    guard let end = trip.endDate else { continue }
                    let night = PracticeMath.nightSeconds(start: trip.startDate, end: end)
                    trip.startDate.formatted(.dateTime.year().month(.abbreviated).day())
                        .draw(at: CGPoint(x: 40, y: y), withAttributes: body)
                    "\(trip.startDate.formatted(.dateTime.hour().minute())) – \(end.formatted(.dateTime.hour().minute()))"
                        .draw(at: CGPoint(x: 170, y: y), withAttributes: body)
                    DriveFormatting.duration(trip.duration ?? 0)
                        .draw(at: CGPoint(x: 300, y: y), withAttributes: body)
                    DriveFormatting.miles(fromMeters: trip.distance)
                        .draw(at: CGPoint(x: 380, y: y), withAttributes: body)
                    (night > 60 ? String(format: "%.1f h", night / 3600) : "—")
                        .draw(at: CGPoint(x: 450, y: y), withAttributes: body)
                    y += 14
                }

                // Signature block on the last page.
                if y > 640 { page() }
                y = max(y + 40, 660)
                for label in ["Driver signature", "Supervising adult signature"] {
                    let line = UIBezierPath()
                    line.move(to: CGPoint(x: 40, y: y + 14))
                    line.addLine(to: CGPoint(x: 300, y: y + 14))
                    UIColor.black.setStroke()
                    line.stroke()
                    "\(label) / date".draw(at: CGPoint(x: 40, y: y + 18), withAttributes: small)
                    y += 46
                }
            }
            return url
        } catch {
            return nil
        }
    }
}
