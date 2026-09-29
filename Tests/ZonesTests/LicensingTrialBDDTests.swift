import XCTest
@testable import ZonesCore

final class LicensingTrialBDDTests: BDDTestCase {
    private var steps: LicensingTrialSteps!

    override func registerSteps() {
        steps = LicensingTrialSteps()
        steps.register(in: registry)
    }

    func testLicensingTrial() {
        runFeature("licensing_trial")
    }
}
