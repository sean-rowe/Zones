import XCTest
@testable import ZonesCore

final class AccessibilityPermissionBDDTests: BDDTestCase {
    private var steps: AccessibilityPermissionSteps!

    override func registerSteps() {
        steps = AccessibilityPermissionSteps()
        steps.register(in: registry)
    }

    func testAccessibilityPermission() {
        runFeature("accessibility_permission")
    }
}
