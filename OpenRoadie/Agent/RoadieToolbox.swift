import Foundation

/// The agent's capability layer: every fact Roadie can look up or setting it
/// can change lives here, independent of WHICH language model is asking.
/// Apple's on-device model calls in through FoundationModels tools; remote
/// models call in through the OpenAI-compatible provider. Same body,
/// swappable heads.
@MainActor
final class RoadieToolbox {
    let drive: DriveSessionManager
    let store: TripStore?
    let places = PlaceService()
    private let overpass = OverpassClient()

    init(drive: DriveSessionManager, store: TripStore?) {
        self.drive = drive
        self.store = store
    }

    // MARK: - Capabilities

    func currentDrive() -> String {
        RoadieToolFormatting.describeDrive(drive.context, isDriving: drive.isDriving)
    }

    func findNearby(category rawCategory: String, brandOrName: String?) async -> String {
        let category = PlaceCategory(rawValue: rawCategory.lowercased()) ?? .food

        guard let origin = await resolveOrigin() else {
            return "The driver's location is unavailable right now."
        }

        do {
            let found = try await places.places(near: origin, category: category)
            let sorted = PlaceGeometry.sortedByDistance(found, from: origin)

            if let keyword = brandOrName?.trimmingCharacters(in: .whitespaces), !keyword.isEmpty {
                let matching = sorted.filter { $0.place.matches(keyword: keyword) }
                if matching.isEmpty {
                    // Honest miss, but still useful: offer what IS around.
                    return "No \(category.singular) matching \"\(keyword)\" nearby. "
                        + RoadieToolFormatting.describePlaces(sorted, category: category, origin: origin)
                }
                return RoadieToolFormatting.describePlaces(matching, category: category, origin: origin)
            }
            return RoadieToolFormatting.describePlaces(sorted, category: category, origin: origin)
        } catch {
            return "The place search didn't respond — possibly offline. Suggest trying again."
        }
    }

    func speedLimitFor(road: String) async -> String {
        guard let origin = await resolveOrigin() else {
            return "The driver's location is unavailable, so nearby roads can't be searched."
        }
        let searchTerm = RoadLimitTool.searchTerm(from: road)
        do {
            let tags = try await overpass.speedLimitTags(matching: searchTerm, near: origin, radius: 15_000)
            let mphValues = tags
                .compactMap(RoadMatcher.speedLimit(fromMaxspeedTag:))
                .map { DriveFormatting.milesPerHour(fromMetersPerSecond: $0) }
            return RoadieToolFormatting.describeRoadLimits(road: road, mphValues: mphValues)
        } catch {
            return "The road lookup didn't respond — possibly offline."
        }
    }

    func tripHistory() -> String {
        guard let store else { return "Trip history is unavailable." }
        return RoadieToolFormatting.describeTrips(store.recentTrips(limit: 5))
    }

    func configureAlerts(
        alertOverPostedLimit: Bool?,
        extraAlertMphOverLimit: Int?,
        maxSpeedMph: Int?,
        autoEndDriveWhenParked: Bool?
    ) -> String {
        ConfigureAlertsTool.apply(
            alertOverPostedLimit: alertOverPostedLimit,
            extraAlertMphOverLimit: extraAlertMphOverLimit,
            maxSpeedMph: maxSpeedMph,
            autoEndDriveWhenParked: autoEndDriveWhenParked,
            defaults: .standard
        )
    }

    // MARK: - Shared

    /// Live drive position, else a one-shot fix for parked use.
    func resolveOrigin() async -> Coordinate? {
        if let coordinate = drive.context.coordinate {
            return coordinate
        }
        return await LocationService.currentFix()
    }
}
