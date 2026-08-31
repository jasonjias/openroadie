import Foundation
import Testing
@testable import OpenRoadie

struct LocationSessionJanitorTests {
    /// A previous incarnation died holding sessions → conclude them.
    @Test func dirtyFlagTriggersReconciliation() {
        #expect(LocationSessionJanitor.shouldReconcile(flag: true, isDriving: false, authorizationDetermined: true))
    }

    @Test func cleanShutdownNeedsNothing() {
        #expect(!LocationSessionJanitor.shouldReconcile(flag: false, isDriving: false, authorizationDetermined: true))
    }

    /// Upgrades from builds that never wrote the flag are exactly the
    /// population with pills already stuck — reconcile once.
    @Test func missingFlagReconcilesOnce() {
        #expect(LocationSessionJanitor.shouldReconcile(flag: nil, isDriving: false, authorizationDetermined: true))
    }

    /// A live drive owns its sessions; the janitor must not touch them.
    @Test func neverWhileDriving() {
        #expect(!LocationSessionJanitor.shouldReconcile(flag: true, isDriving: true, authorizationDetermined: true))
    }

    /// Reconciling creates location sessions, which would prompt a user
    /// who has never been asked — first launch stays quiet.
    @Test func neverBeforeAuthorizationIsDetermined() {
        #expect(!LocationSessionJanitor.shouldReconcile(flag: true, isDriving: false, authorizationDetermined: false))
    }
}
