import XCTest
@testable import ZonesCore

final class MoveToApplicationsSteps {
    private var bundleURL = URL(fileURLWithPath: "/")

    func register(in registry: StepRegistry) {
        registry.given("the bundle is at \"(.+)\"") { args in
            self.bundleURL = URL(fileURLWithPath: args[0])
        }
        registry.then("Zones offers to move itself") { _ in
            XCTAssertTrue(MoveToApplications.shouldOfferMove(from: self.bundleURL))
        }
        registry.then("Zones does not offer to move itself") { _ in
            XCTAssertFalse(MoveToApplications.shouldOfferMove(from: self.bundleURL))
        }
        registry.then("the location is reported as a mounted disk image") { _ in
            XCTAssertEqual(MoveToApplications.location(of: self.bundleURL), .mountedDiskImage)
        }
        registry.then("the location is reported as translocated") { _ in
            XCTAssertEqual(MoveToApplications.location(of: self.bundleURL), .translocated)
        }
        registry.then("the location is reported as already in Applications") { _ in
            XCTAssertEqual(MoveToApplications.location(of: self.bundleURL), .alreadyInApplications)
        }
        registry.then("the location is reported as elsewhere") { _ in
            XCTAssertEqual(MoveToApplications.location(of: self.bundleURL), .elsewhere)
        }
    }
}
