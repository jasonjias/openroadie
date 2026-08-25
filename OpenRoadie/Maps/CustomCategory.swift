import Foundation

/// A user-made Nearby category: a name, an icon, and the search terms it
/// looks for — "Landmarks (real)" for chipotle, in-n-out, raising canes.
/// Terms are Apple Maps searches (the same engine as the search bar, which
/// is the point: if the search bar finds it, the chip finds it), with
/// results cached to disk like every other category.
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

    /// The custom category a spoken request refers to, if any — matched by
    /// title ("landmarks (real)") or by one of its terms ("chipotle").
    static func matching(_ query: String) -> CustomCategory? {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return nil }
        let all = load()
        if let byTitle = all.first(where: { $0.title.lowercased() == q }) { return byTitle }
        if let byTerm = all.first(where: { custom in
            custom.terms.contains { $0.lowercased() == q }
        }) { return byTerm }
        // Loose title match ("my landmarks" → "Landmarks (real)") needs a
        // word long enough to not swallow built-ins like "food".
        guard q.count >= 4 else { return nil }
        return all.first { $0.title.lowercased().contains(q) || q.contains($0.title.lowercased()) }
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

    /// Where this chip's results come from — shown in error/empty states.
    var sourceName: String {
        switch self {
        case .builtin: "OpenStreetMap"
        case .custom: "Apple Maps"
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
