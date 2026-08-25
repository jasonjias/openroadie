import SwiftUI

/// The app's type scale, modeled on Apple Fitness: large bold page titles
/// (system navigation titles), title3-semibold card headers, big rounded
/// stat numbers over quiet caption labels, footnote descriptions.
/// One vocabulary, every tab.
enum AppFont {
    /// Card / section titles ("Drives", "Factors") — Fitness-style,
    /// not the tiny uppercase list default.
    static let cardTitle = Font.title3.weight(.semibold)
    /// Big stat values (miles, time, max speed).
    static let metricValue = Font.system(.title3, design: .rounded).weight(.semibold)
    /// The quiet label above a stat.
    static let metricLabel = Font.caption
    /// Row titles in lists.
    static let rowTitle = Font.body.weight(.medium)
    /// Secondary descriptions under rows and cards.
    static let rowDetail = Font.caption
    /// Footers and fine print.
    static let footnote = Font.footnote
}

/// Fitness-style section header for List sections.
struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(AppFont.cardTitle)
            .foregroundStyle(.primary)
            .textCase(nil)
    }
}
