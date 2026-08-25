import Foundation
import FoundationModels

/// Natural-language rule creation: the model translates "warn me if I go 10
/// over" into a settings change, and the deterministic SpeedAlertEngine
/// enforces it. The AI configures; it never judges speed itself.
struct ConfigureAlertsTool: Tool {
    let name = "configureSpeedAlerts"
    let description = """
    Read or change the driver's speed alert rules. Pass only the fields to \
    change; pass nothing to just read the current settings. The app enforces \
    these rules deterministically and mirrors alerts to Apple Watch.
    """

    @Generable
    struct Arguments {
        @Guide(description: "true to alert when crossing the posted speed limit, false to turn that alert off. Omit to leave unchanged.")
        var alertOverPostedLimit: Bool?

        @Guide(description: "Extra alert this many mph over the posted limit, e.g. 5 or 10. 0 turns it off. Omit to leave unchanged.")
        var extraAlertMphOverLimit: Int?

        @Guide(description: "The driver's personal max speed in mph, e.g. 80 — warns when approaching and when over. 0 turns it off. Omit to leave unchanged.")
        var maxSpeedMph: Int?

        @Guide(description: "true to automatically end and save the drive after 10 minutes parked. Omit to leave unchanged.")
        var autoEndDriveWhenParked: Bool?
    }

    private let toolbox: RoadieToolbox

    init(toolbox: RoadieToolbox) {
        self.toolbox = toolbox
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.configureAlerts(
            alertOverPostedLimit: arguments.alertOverPostedLimit,
            extraAlertMphOverLimit: arguments.extraAlertMphOverLimit,
            maxSpeedMph: arguments.maxSpeedMph,
            autoEndDriveWhenParked: arguments.autoEndDriveWhenParked
        )
    }

    /// Applies the requested changes with deterministic clamping and returns
    /// the resulting settings summary. Separated (and defaults-injectable)
    /// for unit testing.
    @MainActor
    static func apply(
        alertOverPostedLimit: Bool?,
        extraAlertMphOverLimit: Int?,
        maxSpeedMph: Int?,
        autoEndDriveWhenParked: Bool?,
        defaults: UserDefaults
    ) -> String {
        var changed = false

        if let overLimit = alertOverPostedLimit {
            // "Alert me at the limit" via Roadie means the chime tier; off is off.
            defaults.set(
                (overLimit ? AlertCenter.OverLimitStyle.chime : .off).rawValue,
                forKey: AlertCenter.overLimitStyleKey
            )
            changed = true
        }
        if let extra = extraAlertMphOverLimit {
            let clamped = extra <= 0 ? 0 : min(max(extra, 3), 30)
            defaults.set(Double(clamped), forKey: AlertCenter.marginKey)
            changed = true
        }
        if let maxSpeed = maxSpeedMph {
            let clamped = maxSpeed <= 0 ? 0 : min(max(maxSpeed, 30), 120)
            defaults.set(Double(clamped), forKey: AlertCenter.maxSpeedKey)
            changed = true
        }
        if let autoEnd = autoEndDriveWhenParked {
            defaults.set(autoEnd, forKey: AlertCenter.autoEndKey)
            changed = true
        }

        if changed, defaults === UserDefaults.standard {
            AlertCenter.requestAuthorization()
        }

        return RoadieToolFormatting.describeAlertSettings(
            overLimit: defaults.bool(forKey: AlertCenter.overLimitKey),
            marginMph: Int(defaults.double(forKey: AlertCenter.marginKey)),
            maxSpeedMph: Int(defaults.double(forKey: AlertCenter.maxSpeedKey)),
            autoEnd: defaults.object(forKey: AlertCenter.autoEndKey) as? Bool ?? true,
            changed: changed
        )
    }
}
