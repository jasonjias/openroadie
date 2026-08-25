import Foundation
import Testing
@testable import OpenRoadie

@MainActor
struct ConfigureAlertsTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "configure-alerts-tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func setsMaxSpeedFromNaturalLanguageIntent() {
        let defaults = freshDefaults()
        let summary = ConfigureAlertsTool.apply(
            alertOverPostedLimit: nil, extraAlertMphOverLimit: nil,
            maxSpeedMph: 80, autoEndDriveWhenParked: nil, defaults: defaults
        )
        #expect(defaults.double(forKey: AlertCenter.maxSpeedKey) == 80)
        #expect(summary.contains("80 mph"))
        #expect(summary.contains("Settings updated"))
    }

    @Test func clampsAbsurdValues() {
        let defaults = freshDefaults()
        _ = ConfigureAlertsTool.apply(
            alertOverPostedLimit: nil, extraAlertMphOverLimit: 200,
            maxSpeedMph: 500, autoEndDriveWhenParked: nil, defaults: defaults
        )
        #expect(defaults.double(forKey: AlertCenter.marginKey) == 30)
        #expect(defaults.double(forKey: AlertCenter.maxSpeedKey) == 120)
    }

    @Test func zeroDisablesARule() {
        let defaults = freshDefaults()
        _ = ConfigureAlertsTool.apply(
            alertOverPostedLimit: nil, extraAlertMphOverLimit: 10,
            maxSpeedMph: nil, autoEndDriveWhenParked: nil, defaults: defaults
        )
        let summary = ConfigureAlertsTool.apply(
            alertOverPostedLimit: nil, extraAlertMphOverLimit: 0,
            maxSpeedMph: nil, autoEndDriveWhenParked: nil, defaults: defaults
        )
        #expect(defaults.double(forKey: AlertCenter.marginKey) == 0)
        #expect(summary.contains("Extra alert: off"))
    }

    @Test func omittedFieldsStayUntouched() {
        let defaults = freshDefaults()
        _ = ConfigureAlertsTool.apply(
            alertOverPostedLimit: true, extraAlertMphOverLimit: 5,
            maxSpeedMph: nil, autoEndDriveWhenParked: nil, defaults: defaults
        )
        _ = ConfigureAlertsTool.apply(
            alertOverPostedLimit: nil, extraAlertMphOverLimit: nil,
            maxSpeedMph: 75, autoEndDriveWhenParked: nil, defaults: defaults
        )
        #expect(defaults.string(forKey: AlertCenter.overLimitStyleKey) == AlertCenter.OverLimitStyle.chime.rawValue)
        #expect(defaults.double(forKey: AlertCenter.marginKey) == 5)
        #expect(defaults.double(forKey: AlertCenter.maxSpeedKey) == 75)
    }

    @Test func noArgumentsJustReads() {
        let defaults = freshDefaults()
        let summary = ConfigureAlertsTool.apply(
            alertOverPostedLimit: nil, extraAlertMphOverLimit: nil,
            maxSpeedMph: nil, autoEndDriveWhenParked: nil, defaults: defaults
        )
        #expect(summary.hasPrefix("Current speed alerts"))
        #expect(!summary.contains("Settings updated"))
    }
}
