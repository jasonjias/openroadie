import Foundation

/// A user-made Nearby category: a name, an icon, and the search terms it
/// matches — "Landmarks (real)" for chipotle, in-n-out, raising canes.
/// Terms match OSM name and brand tags, case-insensitively.
struct CustomCategory: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var title: String
    var systemImage: String
    var terms: [String]

    init(id: UUID = UUID(), title: String, systemImage: String = "star.fill", terms: [String]) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.terms = terms
    }

    /// Brand names cluster in cities but you drive to them: search wide.
    var searchRadius: Double { 10_000 }

    /// Stable cache/order identity, distinct from built-in raw values.
    var key: String { "custom-\(id.uuidString)" }

    /// One Overpass regex matching any term, with regex metacharacters
    /// escaped so "In-N-Out (Lathrop)" can't hijack the query.
    var overpassRegex: String {
        terms
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { term in
                term.replacingOccurrences(
                    of: #"[\\.\[\]\(\)\*\+\?\^\$\|\{\}"]"#,
                    with: #"\\$0"#,
                    options: .regularExpression
                )
            }
            .joined(separator: "|")
    }

    // MARK: - Persistence

    static let defaultsKey = "customPlaceCategories"

    static func load() -> [CustomCategory] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([CustomCategory].self, from: data) else { return [] }
        return decoded
    }

    static func save(_ categories: [CustomCategory]) {
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    /// Symbols offered by the editor — enough range without a symbol browser.
    static let symbolChoices = [
        "star.fill", "heart.fill", "takeoutbag.and.cup.and.straw.fill",
        "fork.knife", "cup.and.saucer.fill", "cart.fill",
        "bag.fill", "pawprint.fill", "figure.run",
        "gamecontroller.fill", "building.2.fill", "mappin.and.ellipse",
    ]
}

/// One chip in the Nearby tab — a built-in category or a user-made one.
/// Ordering and visibility live here so customs interleave with built-ins
/// (Superchargers first, then Chipotle, then everything else).
enum NearbyChip: Identifiable, Equatable, Hashable {
    case builtin(PlaceCategory)
    case custom(CustomCategory)

    var id: String {
        switch self {
        case .builtin(let category): category.rawValue
        case .custom(let custom): custom.key
        }
    }

    var title: String {
        switch self {
        case .builtin(let category): category.title
        case .custom(let custom): custom.title
        }
    }

    var systemImage: String {
        switch self {
        case .builtin(let category): category.systemImage
        case .custom(let custom): custom.systemImage
        }
    }

    var searchRadius: Double {
        switch self {
        case .builtin(let category): category.searchRadius
        case .custom(let custom): custom.searchRadius
        }
    }

    /// All chips in the user's chosen order. Chips the stored order doesn't
    /// know (new built-ins, freshly created customs) keep default position:
    /// built-ins in declaration order, customs after.
    static var ordered: [NearbyChip] {
        let all: [NearbyChip] = PlaceCategory.allCases.map { .builtin($0) }
            + CustomCategory.load().map { .custom($0) }
        guard let stored = UserDefaults.standard.stringArray(forKey: PlaceCategory.orderDefaultsKey) else {
            return all
        }
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        let known = stored.compactMap { byID[$0] }
        return known + all.filter { !stored.contains($0.id) }
    }

    static func setOrder(_ chips: [NearbyChip]) {
        UserDefaults.standard.set(chips.map(\.id), forKey: PlaceCategory.orderDefaultsKey)
    }

    /// Ordered chips minus hidden built-ins. Customs are shown or deleted,
    /// never hidden. Falls back to everything if the user hides all of it.
    static var visible: [NearbyChip] {
        let shown = ordered.filter { chip in
            if case .builtin(let category) = chip {
                return !PlaceCategory.isHidden(category)
            }
            return true
        }
        return shown.isEmpty ? ordered : shown
    }
}
