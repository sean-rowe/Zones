import XCTest
import Foundation
@testable import ZonesCore

final class LicensingTrialSteps {
    private var trialManager: TrialManager!
    private var simulatedDate: Date!
    private var trialDefaults: UserDefaults!
    private var keychainDate: Date?

    private var licenseStore: LicenseStore!
    private var activationSaved: LicenseStore.Activation?
    private var licenseKeyToActivate: String = ""
    private var activationError: LicenseStore.ActivationError?
    private var activationSuccess: Bool = false

    func register(in registry: StepRegistry) {
        registry.given("a fresh install") { _ in
            self.trialManager = TrialManager()
            self.trialDefaults = UserDefaults(suiteName: "LicensingTrialSteps_\(UUID().uuidString)")!
            self.trialManager.defaults = self.trialDefaults
            self.simulatedDate = Date()
            self.trialManager.now = { [weak self] in self?.simulatedDate ?? Date() }
            self.keychainDate = nil
            self.trialManager.readKeychainAnchor = { [weak self] in self?.keychainDate }
            self.trialManager.writeKeychainAnchor = { [weak self] date in self?.keychainDate = date }
            self.trialManager.isLicensed = { false }
        }

        registry.then("a trial period begins") { _ in
            XCTAssertEqual(self.trialManager.state, .trial(daysRemaining: 14))
            XCTAssertTrue(self.trialManager.canSnap)
        }

        registry.then("I am reminded as it nears expiry") { _ in
            self.simulatedDate = self.simulatedDate.addingTimeInterval(11 * 86400) // 3 days left
            XCTAssertEqual(self.trialManager.state, .trial(daysRemaining: 3))
            let moment = TrialReminder.moment(for: self.trialManager.state)
            XCTAssertEqual(moment, .threeDaysLeft)
        }

        registry.then("an expired trial degrades predictably rather than crashing") { _ in
            self.simulatedDate = self.simulatedDate.addingTimeInterval(4 * 86400) // 15 days total -> expired
            XCTAssertEqual(self.trialManager.state, .trialExpired)
            XCTAssertFalse(self.trialManager.canSnap, "Expired trial must block snapping gracefully")
            XCTAssertEqual(self.trialManager.menuLine, "Trial expired — Buy Zones…")
        }

        registry.given("a valid licence key") { _ in
            self.licenseStore = LicenseStore()
            self.activationSaved = nil
            self.licenseStore.readActivation = { self.activationSaved }
            self.licenseStore.writeActivation = { self.activationSaved = $0 }
            self.licenseKeyToActivate = "ZONE-ABCD-EF23-4567"

            self.licenseStore.transport = { _, completion in
                let response = [
                    "activated": true,
                    "instance": ["id": "inst_valid_999"]
                ] as [String: Any]
                let data = try! JSONSerialization.data(withJSONObject: response)
                completion(data, nil)
            }
        }

        registry.when("I activate it") { _ in
            let exp = XCTestExpectation(description: "activate")
            self.activationSuccess = false
            self.activationError = nil
            self.licenseStore.activate(key: self.licenseKeyToActivate) { result in
                switch result {
                case .success:
                    self.activationSuccess = true
                case .failure(let err):
                    self.activationError = err
                }
                exp.fulfill()
            }
            _ = XCTWaiter.wait(for: [exp], timeout: 1.0)
        }

        registry.then("the app is licensed") { _ in
            XCTAssertTrue(self.activationSuccess)
            XCTAssertTrue(self.licenseStore.isActivated)
        }

        registry.then("it is still licensed after relaunch") { _ in
            XCTAssertNotNil(self.activationSaved)
            XCTAssertEqual(self.activationSaved?.key, "ZONE-ABCD-EF23-4567")
        }

        registry.given("an invalid key") { _ in
            self.licenseStore = LicenseStore()
            self.activationSaved = nil
            self.licenseStore.readActivation = { self.activationSaved }
            self.licenseStore.writeActivation = { self.activationSaved = $0 }
            self.licenseKeyToActivate = "ZONE-BADK-EY99-0000"

            self.licenseStore.transport = { _, completion in
                let response = [
                    "activated": false,
                    "error": "This license key has been revoked"
                ] as [String: Any]
                let data = try! JSONSerialization.data(withJSONObject: response)
                completion(data, nil)
            }
        }

        registry.then("I am told why it was refused") { _ in
            XCTAssertFalse(self.activationSuccess)
            guard let error = self.activationError else {
                XCTFail("Expected activation error")
                return
            }
            if case .refused(let reason) = error {
                XCTAssertEqual(reason, "This license key has been revoked")
            } else {
                XCTFail("Expected refused error")
            }
        }

        registry.given("a release build") { _ in
            // Target is Zones
        }

        registry.then("its licence API host is the final agreed hostname") { _ in
            XCTAssertEqual(ZonesStoreConfig.apiBase.host, "zones.pinyridgelabs.com")
        }

        registry.then("its appcast URL is the final agreed hostname") { _ in
            XCTAssertEqual(ZonesStoreConfig.appcastURL?.host, "zones.pinyridgelabs.com")
        }

        registry.then("neither is a placeholder") { _ in
            XCTAssertFalse(ZonesStoreConfig.apiBase.absoluteString.contains("localhost"))
            XCTAssertFalse(ZonesStoreConfig.apiBase.absoluteString.contains("example.com"))
            XCTAssertFalse(ZonesStoreConfig.appcastURL?.absoluteString.contains("localhost") ?? true)
            XCTAssertFalse(ZonesStoreConfig.appcastURL?.absoluteString.contains("example.com") ?? true)
        }
    }
}
