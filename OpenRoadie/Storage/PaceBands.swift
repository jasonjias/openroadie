import Foundation

/// Where a drive's time actually went, by pace.
///
/// The bands partition the drive's span exactly — every second between the
/// first and last recorded point lands in one band and no second lands in
/// two — so the breakdown ties out against the trip duration instead of
/// approximating it. A figure that won't tie out is a bug, not a caption.
///
/// Pace is measured from the *gap between* recorded points (distance ÷
/// elapsed), not from the GPS speed stamped on them. That is both simpler
/// and truer: nothing is recorded while a car sits still, so a twenty-minute
/// stop shows up as twenty minutes of almost no distance, which is exactly
/// what it was.
enum PaceBands {
    enum Band: Int, CaseIterable, Identifiable, Sendable {
        /// Under ~3 mph: stopped. Lights, jams, gas stops, drive-thrus.
        case stopped
        /// ~3–15 mph: crawling. Parking lots and traffic that isn't moving.
        case crawling
        /// ~15–40 mph: surface streets at a normal pace.
        case city
        /// ~40 mph and up: highway.
        case highway
        /// Time nothing was recorded for — the app was killed, or location
        /// was cut off. Its own band, never folded into "stopped", because
        /// we genuinely don't know what happened.
        case unknown

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .stopped: "Stopped"
            case .crawling: "Crawling"
            case .city: "City"
            case .highway: "Highway"
            case .unknown: "Unrecorded"
            }
        }

        /// Short label for a legend, in mph.
        var range: String {
            switch self {
            case .stopped: "<3"
            case .crawling: "3–15"
            case .city: "15–40"
            case .highway: "40+"
            case .unknown: "—"
            }
        }
    }

    struct Config: Equatable {
        /// Band boundaries in m/s ≈ 3 / 15 / 40 mph.
        var crawlingAbove: Double = 1.4
        var cityAbove: Double = 6.7
        var highwayAbove: Double = 17.9
        /// An interval longer than this isn't a stop, it's a hole in the
        /// record. A drive ends itself after 25 minutes stopped, so any
        /// longer gap inside one trip is missing data.
        var unknownAfter: TimeInterval = 1800
        /// Time under 15 mph beyond this is a drive with a traffic story.
        var trafficThreshold: TimeInterval = 600
    }

    struct Breakdown: Equatable, Sendable {
        /// Seconds per band, indexed by `Band.rawValue`. Sums to `total`.
        var seconds: [TimeInterval]
        /// Distance (meters) covered in each band, same indexing.
        var meters: [Double]

        init(
            seconds: [TimeInterval] = Array(repeating: 0, count: Band.allCases.count),
            meters: [Double] = Array(repeating: 0, count: Band.allCases.count)
        ) {
            self.seconds = seconds
            self.meters = meters
        }

        func seconds(_ band: Band) -> TimeInterval { seconds[band.rawValue] }
        func meters(_ band: Band) -> Double { meters[band.rawValue] }

        /// The drive's whole span, by construction of the bands.
        var total: TimeInterval { seconds.reduce(0, +) }

        /// Time under 15 mph: stopped plus crawling. The traffic number.
        var slowSeconds: TimeInterval { seconds(.stopped) + seconds(.crawling) }

        var slowShare: Double { total > 0 ? slowSeconds / total : 0 }

        /// Time the vehicle was actually getting somewhere — what an
        /// average speed should be measured over once drives survive
        /// their own stops.
        var movingSeconds: TimeInterval { seconds(.city) + seconds(.highway) + seconds(.crawling) }

        var movingMeters: Double { meters(.city) + meters(.highway) + meters(.crawling) }

        /// Average speed while moving, in m/s. `nil` when nothing moved.
        var movingSpeed: Double? {
            guard movingSeconds > 0, movingMeters > 0 else { return nil }
            return movingMeters / movingSeconds
        }

        /// The bands that actually occurred, in band order.
        var presentBands: [Band] {
            Band.allCases.filter { seconds($0) > 0 }
        }
    }

    /// Which band an interval belongs to, from the distance covered over it.
    static func band(meters: Double, seconds: TimeInterval, config: Config = Config()) -> Band {
        guard seconds > 0 else { return .stopped }
        if seconds > config.unknownAfter { return .unknown }
        let speed = meters / seconds
        if speed < config.crawlingAbove { return .stopped }
        if speed < config.cityAbove { return .crawling }
        if speed < config.highwayAbove { return .city }
        return .highway
    }

    /// The per-band breakdown of a recorded route.
    static func compute(_ samples: [RouteSample], config: Config = Config()) -> Breakdown {
        var breakdown = Breakdown()
        guard samples.count >= 2 else { return breakdown }
        for (previous, next) in zip(samples, samples.dropFirst()) {
            let seconds = next.timestamp.timeIntervalSince(previous.timestamp)
            guard seconds > 0 else { continue }
            let meters = TripTracker.distance(from: previous.coordinate, to: next.coordinate)
            let band = band(meters: meters, seconds: seconds, config: config)
            breakdown.seconds[band.rawValue] += seconds
            breakdown.meters[band.rawValue] += meters
        }
        return breakdown
    }

    /// True when the drive spent long enough under 15 mph to be worth
    /// calling out rather than burying in a chart.
    static func isTrafficHeavy(_ breakdown: Breakdown, config: Config = Config()) -> Bool {
        breakdown.slowSeconds >= config.trafficThreshold
    }

    /// Which band each route point belongs to — the interval ending at it,
    /// so the first point borrows the second's. Feeds map coloring.
    static func bandIndices(_ samples: [RouteSample], config: Config = Config()) -> [Int] {
        guard samples.count >= 2 else { return Array(repeating: Band.stopped.rawValue, count: samples.count) }
        var indices: [Int] = []
        for (previous, next) in zip(samples, samples.dropFirst()) {
            let seconds = next.timestamp.timeIntervalSince(previous.timestamp)
            let meters = TripTracker.distance(from: previous.coordinate, to: next.coordinate)
            indices.append(band(meters: meters, seconds: seconds, config: config).rawValue)
        }
        return [indices[0]] + indices
    }
}
