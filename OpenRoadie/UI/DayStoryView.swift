import SwiftUI

/// The selected day as a story: each drive a line, each stop between them
/// a named pause. Composes trips, weather, and geocoded places the app
/// already has — nothing new is collected for it.
struct DayStorySection: View {
    /// Completed trips of the day, oldest first.
    let trips: [Trip]
    /// The day being told — walks come from iOS's own motion history,
    /// which reaches back about a week.
    let day: Date

    @State private var walks: [WalkHistory.Walk] = []
    @State private var walkHistory = WalkHistory()

    var body: some View {
        let entries = trips.map { trip -> (start: Date, end: Date, lastCoordinate: Coordinate?) in
            let last = trip.route.last
            return (
                trip.startDate,
                trip.endDate ?? trip.startDate,
                last.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
            )
        }
        let stops = DayStory.stops(between: entries)

        let shownWalks = DayStory.walksOutsideDrives(
            walks.map { ($0.start, $0.end) },
            drives: entries.map { ($0.start, $0.end) }
        )

        Section {
            ForEach(Array(trips.enumerated()), id: \.element.persistentModelID) { index, trip in
                driveRow(trip)
                if let stop = stops.first(where: { $0.afterTrip == index }) {
                    stopRow(stop)
                }
                // Walks that started during the pause after this drive.
                let gapEnd = index + 1 < trips.count ? trips[index + 1].startDate : Date.distantFuture
                ForEach(walksDuring(from: trip.endDate ?? trip.startDate, to: gapEnd, in: shownWalks), id: \.start) { walk in
                    walkRow(walk)
                }
            }
        } header: {
            SectionHeader("Story")
        }
        .task(id: day) {
            walks = await walkHistory.walks(on: day)
        }
    }

    private func walksDuring(from: Date, to: Date, in intervals: [(start: Date, end: Date)]) -> [(start: Date, end: Date)] {
        intervals.filter { $0.start >= from && $0.start < to }
    }

    private func walkRow(_ interval: (start: Date, end: Date)) -> some View {
        let walk = walks.first { $0.start == interval.start }
        return HStack(spacing: 10) {
            Image(systemName: "figure.walk")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            HStack(spacing: 6) {
                Text("walked \(DriveFormatting.compactDuration(interval.end.timeIntervalSince(interval.start)))")
                if let meters = walk?.meters {
                    Text("· \(DriveFormatting.shortDistance(fromMeters: meters))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func driveRow(_ trip: Trip) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "car.fill")
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(trip.startDate, format: .dateTime.hour().minute())
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let last = trip.route.last {
                        PlaceText(coordinate: Coordinate(latitude: last.latitude, longitude: last.longitude))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }
                }
                Text(DriveFormatting.miles(fromMeters: trip.distance))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let weather = trip.weather {
                Label(
                    "\(DriveFormatting.fahrenheit(fromCelsius: weather.temperatureC))°",
                    systemImage: WeatherCode.symbol(weather.wmoCode)
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func stopRow(_ stop: DayStory.Stop) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "parkingsign.circle")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            HStack(spacing: 6) {
                Text(DriveFormatting.compactDuration(stop.duration))
                if let coordinate = stop.coordinate {
                    PlaceText(coordinate: coordinate, prefix: "· ")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}
