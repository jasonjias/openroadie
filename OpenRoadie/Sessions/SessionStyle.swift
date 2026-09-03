import SwiftUI

/// Sessions wear OpenRoadie's own palette — one color per kind of activity,
/// drawn from the app's existing vocabulary (blue drives like the all-drives
/// map, green for going on foot, teal like the pace bands, indigo like the
/// note pins) — rather than borrowing Apple Fitness's lime-on-black.
extension SessionItem.Kind {
    var tint: Color {
        switch self {
        case .drive: .blue
        case .walk: .green
        case .workout: .orange
        case .sleep: .indigo
        case .stop: .teal
        }
    }
}
