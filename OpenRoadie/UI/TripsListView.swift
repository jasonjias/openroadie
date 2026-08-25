import MapKit
import SwiftData
import SwiftUI

/// The Fitness-style driving log: a week strip of Drive Score rings, one
/// day's metrics and drives, and a month calendar for time travel.
/// Everything shown here lives only on this device.
struct TripsListView: View {
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @Query(sort: \DriveNote.timestamp, order: .reverse) private var notes: [DriveNote]
    @Query private var events: [DriveEvent]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var showsCalendar = false
    @State private var showsSafetyDetail = false
    @State private var showsSettings = false

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    weekStrip
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }

                Section {
                    dayCard
                }

                daySection

                dayNotesSection

                Section {
                    if !dayTrips.isEmpty {
                        NavigationLink {
                            DayDrivesMap(trips: dayTrips, title: dayTitle)
                        } label: {
                            Label("Map for this day", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                    }
                    NavigationLink {
                        AllDrivesMap(trips: trips)
                            .navigationTitle("All drives")
                            .navigationBarTitleDisplayMode(.inline)
                            .ignoresSafeArea(edges: .bottom)
                    } label: {
                        Label("All drives map", systemImage: "map")
                    }
                }
            }
            .navigationTitle(dayTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            showsCalendar = true
                        } label: {
                            Image(systemName: "calendar")
                        }
                        // Fitness-style profile entry: settings live under it.
                        Button {
                            showsSettings = true
                        } label: {
                            ProfileAvatar(size: 32)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showsCalendar) {
                MonthCalendarView(selectedDay: $selectedDay, statsFor: stats(on:))
            }
            .fullScreenCover(isPresented: $showsSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showsSafetyDetail) {
                SafetyDetailView(
                    dayTitle: dayTitle,
                    stats: stats(on: selectedDay),
                    dayEvents: events
                        .filter { calendar.isDate($0.timestamp, inSameDayAs: selectedDay) }
                        .sorted { $0.timestamp < $1.timestamp },
                    overallScore: overallScore
                )
            }
            .navigationDestination(for: PersistentIdentifier.self) { id in
                if let trip = modelContext.model(for: id) as? Trip {
                    TripDetailView(trip: trip)
                }
            }
        }
    }

    // MARK: - Data

    private func stats(on day: Date) -> DayStats {
        DayStats.compute(trips: trips, events: events, on: day, calendar: calendar)
    }

    /// Average of the last 30 days that had any driving — the overall score.
    private var overallScore: Int? {
        let today = calendar.startOfDay(for: .now)
        let scores = (0..<30).compactMap { offset -> Int? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return stats(on: day).score
        }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / scores.count
    }

    private var dayTrips: [Trip] {
        trips.filter { calendar.isDate($0.startDate, inSameDayAs: selectedDay) }
    }

    private var dayNotes: [DriveNote] {
        notes.filter { calendar.isDate($0.timestamp, inSameDayAs: selectedDay) }
    }

    private var dayTitle: String {
        if calendar.isDateInToday(selectedDay) { return "Today" }
        if calendar.isDateInYesterday(selectedDay) { return "Yesterday" }
        return selectedDay.formatted(.dateTime.weekday(.abbreviated).month().day())
    }

    // MARK: - Week strip

    private var weekStrip: some View {
        let week = calendar.dateInterval(of: .weekOfYear, for: selectedDay) ?? .init(start: selectedDay, duration: 0)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }

        return HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
                let isFuture = day > .now
                VStack(spacing: 5) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(isSelected ? .bold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    ScoreRing(score: isFuture ? nil : stats(on: day).score, lineWidth: 4)
                        .frame(width: 30, height: 30)
                        .overlay {
                            if calendar.isDateInToday(day) {
                                Circle().fill(.tint).frame(width: 5, height: 5)
                            }
                        }
                        .padding(3)
                        .background(
                            Circle().stroke(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5)
                        )
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isFuture { selectedDay = calendar.startOfDay(for: day) }
                }
            }
        }
    }

    // MARK: - Day card

    private var dayCard: some View {
        let stats = stats(on: selectedDay)
        let eventCount = stats.hardEvents + stats.overLimitCrossings + stats.wellOverCrossings
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                metric("Miles", stats.tripCount > 0 ? String(format: "%.1f", stats.miles) : "—", tint: .blue)
                metric("Time", stats.tripCount > 0 ? DriveFormatting.duration(stats.duration) : "—", tint: .green)
                metric("Max speed", stats.maxSpeedMph.map { "\($0) mph" } ?? "—", tint: .orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showsSafetyDetail = true
            } label: {
                VStack(spacing: 4) {
                    SemicircleGauge(
                        fraction: Double(stats.score ?? 0) / 100,
                        color: scoreColor(stats.score),
                        lineWidth: 10
                    ) {
                        if let score = stats.score {
                            Text("\(score)")
                                .font(.title.bold())
                                .monospacedDigit()
                        } else {
                            Text("—").font(.title3).foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: 130)
                    Text("Drive Score")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(stats.tripCount > 0 ? (eventCount > 0 ? "\(eventCount) events ›" : "clean day ›") : "no drives")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
    }

    private func scoreColor(_ score: Int?) -> Color {
        switch score ?? 0 {
        case 90...: .green
        case 70..<90: .yellow
        default: .red
        }
    }

    private func metric(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(AppFont.metricLabel)
                .foregroundStyle(.secondary)
            Text(value)
                .font(AppFont.metricValue)
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }

    // MARK: - Day drives & notes

    @ViewBuilder
    private var daySection: some View {
        Section {
            if dayTrips.isEmpty {
                Text(calendar.isDateInToday(selectedDay) ? "No drives yet today." : "No drives this day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dayTrips) { trip in
                    if trip.endDate == nil {
                        TripRow(trip: trip)
                    } else {
                        NavigationLink(value: trip.persistentModelID) {
                            TripRow(trip: trip)
                        }
                    }
                }
                .onDelete(perform: deleteTrips)
            }
        } header: {
            SectionHeader("Drives")
        }
    }

    @ViewBuilder
    private var dayNotesSection: some View {
        if !dayNotes.isEmpty {
            Section {
                ForEach(dayNotes) { note in
                    VStack(alignment: .leading, spacing: 3) {
                        Label(note.text, systemImage: "quote.bubble")
                            .font(.subheadline)
                        Text(note.timestamp, format: .dateTime.hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: deleteNotes)
            } header: {
                SectionHeader("Notes")
            }
        }
    }

    private func deleteTrips(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(dayTrips[index])
        }
    }

    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(dayNotes[index])
        }
    }
}

/// The Drive Score as a ring: red → yellow → green, like it means something.
struct ScoreRing: View {
    let score: Int? // 0–100; nil = no driving that day
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            if let score {
                Circle()
                    .trim(from: 0, to: max(0.03, CGFloat(score) / 100))
                    .stroke(color(for: score), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    private func color(for score: Int) -> Color {
        switch score {
        case 90...: .green
        case 70..<90: .yellow
        default: .red
        }
    }
}

/// Month grid with a mini Drive Score ring per day — tap a day to jump to it.
struct MonthCalendarView: View {
    @Binding var selectedDay: Date
    let statsFor: (Date) -> DayStats

    @Environment(\.dismiss) private var dismiss
    @State private var displayedMonth = Calendar.current.startOfDay(for: .now)

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 14) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(0..<leadingBlanks, id: \.self) { _ in
                        Color.clear.frame(height: 44)
                    }
                    ForEach(daysInMonth, id: \.self) { day in
                        let isFuture = day > .now
                        VStack(spacing: 3) {
                            Text("\(calendar.component(.day, from: day))")
                                .font(.caption2)
                                .foregroundStyle(calendar.isDateInToday(day) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            ScoreRing(score: isFuture ? nil : statsFor(day).score, lineWidth: 3.5)
                                .frame(width: 26, height: 26)
                        }
                        .frame(height: 44)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !isFuture else { return }
                            selectedDay = calendar.startOfDay(for: day)
                            dismiss()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(displayedMonth.formatted(.dateTime.month(.wide).year()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            shiftMonth(-1)
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        Button {
                            shiftMonth(1)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                    }
                }
            }
        }
    }

    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
    }

    private var daysInMonth: [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: monthStart) }
    }

    private var leadingBlanks: Int {
        let weekday = calendar.component(.weekday, from: monthStart)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func shiftMonth(_ delta: Int) {
        if let shifted = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = shifted
        }
    }
}

/// One day's drives overlaid, colored by speed or actual-vs-limit —
/// the "how did I actually drive today" view.
struct DayDrivesMap: View {
    let trips: [Trip]
    let title: String

    @State private var colorMode: RouteColorMode = .vsLimit

    var body: some View {
        let allRuns = trips.flatMap { RouteColoring.runs(for: $0.route, mode: colorMode) }

        VStack(spacing: 0) {
            Map(initialPosition: .automatic) {
                ForEach(trips) { trip in
                    ColoredRoute(route: trip.route, mode: colorMode)
                }
            }
            .mapStyle(.standard(elevation: .flat))

            Picker("Coloring", selection: $colorMode) {
                ForEach(RouteColorMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            RouteLegend(runs: allRuns, mode: colorMode)
                .padding(.vertical, 8)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Every recorded drive overlaid on one map — the "everywhere I've driven" view.
struct AllDrivesMap: View {
    let trips: [Trip]

    /// Cap the overlay work for very large histories; newest drives win.
    private static let maxTrips = 50

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(trips.prefix(Self.maxTrips)) { trip in
                let coordinates = trip.route.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                if coordinates.count >= 2 {
                    MapPolyline(coordinates: coordinates)
                        .stroke(
                            .blue.opacity(0.65),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                        )
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
    }
}

private struct TripRow: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trip.startDate, format: .dateTime.hour().minute())
                .font(.headline)
            HStack(spacing: 12) {
                if let duration = trip.duration {
                    Label(DriveFormatting.duration(duration), systemImage: "clock")
                    Label(DriveFormatting.miles(fromMeters: trip.distance), systemImage: "road.lanes")
                    if let maxSpeed = trip.maxSpeed {
                        Label("\(DriveFormatting.milesPerHour(fromMetersPerSecond: maxSpeed)) mph max", systemImage: "gauge.high")
                    }
                } else {
                    Label("Recording…", systemImage: "record.circle")
                        .foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    TripsListView()
        .modelContainer(try! TripStore.inMemory().container)
}
