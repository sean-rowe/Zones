import XCTest
@testable import ZonesCore

final class LayoutModelBDDTests: BDDTestCase {
    private var steps: LayoutModelSteps!
    override func registerSteps() {
        steps = LayoutModelSteps()
        steps.register(in: registry)
    }
    func testLayoutModel() { runFeature("layout_model") }
}

final class LayoutTemplateBDDTests: BDDTestCase {
    private var steps: LayoutTemplateSteps!
    override func registerSteps() {
        steps = LayoutTemplateSteps()
        steps.register(in: registry)
    }
    func testLayoutTemplates() { runFeature("layout_templates") }
}

final class LayoutPersistenceBDDTests: BDDTestCase {
    private var steps: LayoutPersistenceSteps!
    override func registerSteps() {
        steps = LayoutPersistenceSteps()
        steps.register(in: registry)
    }
    func testLayoutPersistence() { runFeature("layout_persistence") }
}
