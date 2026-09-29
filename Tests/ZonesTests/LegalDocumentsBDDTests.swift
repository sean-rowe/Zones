import XCTest
@testable import ZonesCore

final class LegalDocumentsBDDTests: BDDTestCase {
    private var steps: LegalDocumentsSteps!

    override func registerSteps() {
        steps = LegalDocumentsSteps()
        steps.register(in: registry)
    }

    override func tearDown() {
        steps?.tearDown()
        super.tearDown()
    }

    func testLegalDocuments() {
        runFeature("legal_documents")
    }
}
