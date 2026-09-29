import XCTest
@testable import ZonesCore

final class LicenseStoreTests: XCTestCase {
    private var store: LicenseStore!

    override func setUp() {
        super.setUp()
        store = LicenseStore()
    }

    func testConfiguredHostnamesAreFinalAndNotPlaceholders() {
        // ZONES-142 / ZONES-143: Assert final hostnames are compiled in
        XCTAssertEqual(ZonesStoreConfig.apiBase.host, "zones.pinyridgelabs.com")
        XCTAssertEqual(ZonesStoreConfig.apiBase.absoluteString, "https://zones.pinyridgelabs.com/api/licenses")
        XCTAssertEqual(ZonesStoreConfig.checkoutURL?.host, "zones.pinyridgelabs.com")
        XCTAssertEqual(ZonesStoreConfig.appcastURL?.host, "zones.pinyridgelabs.com")
        XCTAssertEqual(ZonesStoreConfig.appcastURL?.absoluteString, "https://zones.pinyridgelabs.com/appcast.xml")
    }

    func testLicenseURLActivationKeyExtraction() {
        // Valid zones URL
        let validURL = URL(string: "zones://activate?key=ZONE-ABCD-EF23-4567")!
        let key = LicenseURL.activationKey(from: validURL)
        XCTAssertEqual(key, "ZONE-ABCD-EF23-4567")

        // Case-insensitive scheme and host
        let mixedURL = URL(string: "ZONES://ACTIVATE?key=ZONE-ABCD-EF23-4567")!
        XCTAssertEqual(LicenseURL.activationKey(from: mixedURL), "ZONE-ABCD-EF23-4567")

        // Invalid scheme
        let wrongScheme = URL(string: "https://activate?key=ZONE-ABCD-EF23-4567")!
        XCTAssertNil(LicenseURL.activationKey(from: wrongScheme))

        // Non-empty path rejected
        let pathExploit = URL(string: "zones://activate/malicious?key=ZONE-ABCD-EF23-4567")!
        XCTAssertNil(LicenseURL.activationKey(from: pathExploit))

        // Invalid key shape
        let badKey = URL(string: "zones://activate?key=not-a-valid-key")!
        XCTAssertNil(LicenseURL.activationKey(from: badKey))
    }

    func testLicenseActivationSuccess() {
        var savedActivation: LicenseStore.Activation?
        store.readActivation = { savedActivation }
        store.writeActivation = { savedActivation = $0 }

        // Mock transport responding with success
        store.transport = { request, completion in
            let response = [
                "activated": true,
                "instance": ["id": "inst_12345"]
            ] as [String: Any]
            let data = try! JSONSerialization.data(withJSONObject: response)
            completion(data, nil)
        }

        let exp = expectation(description: "Activation succeeds")
        store.activate(key: "ZONE-ABCD-EF23-4567") { result in
            switch result {
            case .success:
                exp.fulfill()
            case .failure(let error):
                XCTFail("Activation failed: \(error)")
            }
        }
        waitForExpectations(timeout: 1)

        XCTAssertTrue(store.isActivated)
        XCTAssertEqual(savedActivation?.key, "ZONE-ABCD-EF23-4567")
        XCTAssertEqual(savedActivation?.instanceID, "inst_12345")
    }

    func testLicenseActivationRefusal() {
        var savedActivation: LicenseStore.Activation?
        store.readActivation = { savedActivation }
        store.writeActivation = { savedActivation = $0 }

        // Mock transport responding with refusal
        store.transport = { request, completion in
            let response = [
                "activated": false,
                "error": "License key has expired or reached seat limit"
            ] as [String: Any]
            let data = try! JSONSerialization.data(withJSONObject: response)
            completion(data, nil)
        }

        let exp = expectation(description: "Activation refused")
        store.activate(key: "ZONE-ABCD-EF23-4567") { result in
            switch result {
            case .success:
                XCTFail("Expected activation refusal")
            case .failure(let error):
                if case .refused(let reason) = error {
                    XCTAssertTrue(reason.contains("expired or reached seat limit"))
                    exp.fulfill()
                } else {
                    XCTFail("Unexpected error type: \(error)")
                }
            }
        }
        waitForExpectations(timeout: 1)

        XCTAssertFalse(store.isActivated)
        XCTAssertNil(savedActivation)
    }
}
