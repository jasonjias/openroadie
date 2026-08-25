import Foundation

/// Roadie's coaching voice: turns a deterministic alert event into the nudge
/// the driver actually hears — in a tone they chose, or their own words.
/// Pure string building, fully tested; the rules engine stays the judge.
enum CoachStyle: String, CaseIterable, Identifiable {
    case gentle
    case direct
    case coach
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gentle: "Gentle"
        case .direct: "Direct"
        case .coach: "Coach"
        case .custom: "Custom"
        }
    }

    /// Template tokens: {name}, {speed}, {limit}.
    var template: String {
        switch self {
        case .gentle:
            "{name}, you're at {speed} — consider easing off a little."
        case .direct:
            "{speed} in a {limit}. Slow down."
        case .coach:
            "Hey {name}, {speed} is past {limit}. Let's bring it back down."
        case .custom:
            "" // supplied by the user
        }
    }
}

enum Coach {
    static let styleKey = "coachingStyle"
    static let customTemplateKey = "coachingCustomTemplate"
    static let spokenKey = "coachingSpokenEnabled"
    static let nameKey = "driverName"

    static var style: CoachStyle {
        CoachStyle(rawValue: UserDefaults.standard.string(forKey: styleKey) ?? "") ?? .gentle
    }

    static var spokenEnabled: Bool {
        UserDefaults.standard.bool(forKey: spokenKey)
    }

    /// Builds the nudge for an alert event.
    /// - Parameters:
    ///   - occurrence: how many alerts this drive, for gentle escalation.
    static func message(
        for event: SpeedAlertEngine.Event,
        speedMph: Int?,
        name rawName: String?,
        style: CoachStyle,
        customTemplate: String,
        occurrence: Int
    ) -> String {
        let template = style == .custom && !customTemplate.trimmingCharacters(in: .whitespaces).isEmpty
            ? customTemplate
            : (style == .custom ? CoachStyle.gentle.template : style.template)

        let limitMph: Int = switch event {
        case .overPostedLimit(let limit): limit
        case .overPostedMargin(let limit, _): limit
        case .approachingMaxSpeed(let max): max
        case .overMaxSpeed(let max): max
        }

        let name = rawName?.trimmingCharacters(in: .whitespaces)
        var text = template
            .replacingOccurrences(of: "{name}", with: name?.isEmpty == false ? name! : "there")
            .replacingOccurrences(of: "{speed}", with: speedMph.map { "\($0) mph" } ?? "your speed")
            .replacingOccurrences(of: "{limit}", with: "\(limitMph) mph")

        // Approaching your own max is a heads-up, not a scold.
        if case .approachingMaxSpeed(let max) = event {
            text = name?.isEmpty == false
                ? "\(name!), you're getting close to your \(max) mph max."
                : "You're getting close to your \(max) mph max."
        }

        // Third-plus alert of the drive: say so. Tesla revokes; we escalate
        // tone — there's nothing to take away from someone using their own
        // app, and there shouldn't be.
        if occurrence >= 3 {
            text += " That's the \(ordinal(occurrence)) time this drive."
        }
        return text
    }

    static func fromSettings(
        for event: SpeedAlertEngine.Event,
        speedMph: Int?,
        occurrence: Int
    ) -> String {
        let defaults = UserDefaults.standard
        return message(
            for: event,
            speedMph: speedMph,
            name: defaults.string(forKey: nameKey),
            style: style,
            customTemplate: defaults.string(forKey: customTemplateKey) ?? "",
            occurrence: occurrence
        )
    }

    private static func ordinal(_ number: Int) -> String {
        switch number {
        case 3: "third"
        case 4: "fourth"
        case 5: "fifth"
        default: "\(number)th"
        }
    }
}
