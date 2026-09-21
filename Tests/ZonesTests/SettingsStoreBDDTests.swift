import XCTest
@testable import ZonesCore

final class SettingsStoreBDDTests: BDDTestCase {
    private var steps: SettingsStoreSteps!

    override func registerSteps() {
        steps = SettingsStoreSteps()
        steps.register(in: registry)
    }

    func testSettingsStore() {
        runFeature("settings_store")
    }
}
