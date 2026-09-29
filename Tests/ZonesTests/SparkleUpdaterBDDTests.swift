import XCTest
@testable import ZonesCore

final class SparkleUpdaterBDDTests: BDDTestCase {
    private var steps: SparkleUpdaterSteps!

    override func registerSteps() {
        steps = SparkleUpdaterSteps()
        steps.register(in: registry)
    }

    override func tearDown() {
        steps?.tearDown()
        super.tearDown()
    }

    func testSparkleUpdater() {
        runFeature("sparkle_updater")
    }
}
