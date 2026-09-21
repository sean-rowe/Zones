import XCTest
@testable import ZonesCore

final class AccessibilityPermissionSteps {
    private var trusted = false
    private var permission: AccessibilityPermission!
    private var center: NotificationCenter!
    private var observer: NSObjectProtocol?
    private var notificationCount = 0

    deinit {
        if let observer { center?.removeObserver(observer) }
    }

    private func makePermission(trusted: Bool) {
        self.trusted = trusted
        center = NotificationCenter()
        notificationCount = 0
        // Weak throughout: the steps object owns the permission, which owns the
        // trust closure, which would otherwise own the steps object back.
        permission = AccessibilityPermission(notificationCenter: center,
                                             trustProvider: { [weak self] in self?.trusted ?? false })
        observer = center.addObserver(forName: .accessibilityTrustDidChange,
                                      object: nil, queue: nil) { [weak self] _ in
            self?.notificationCount += 1
        }
    }

    func register(in registry: StepRegistry) {
        registry.given("the process is not trusted") { _ in self.makePermission(trusted: false) }
        registry.given("the process is trusted") { _ in self.makePermission(trusted: true) }

        registry.when("accessibility is granted") { _ in self.trusted = true }
        registry.when("accessibility is revoked") { _ in self.trusted = false }
        registry.when("the permission check runs") { _ in self.permission.checkForChange() }

        registry.then("a trust change notification was posted") { _ in
            XCTAssertEqual(self.notificationCount, 1)
        }
        registry.then("no trust change notification was posted") { _ in
            XCTAssertEqual(self.notificationCount, 0)
        }
        registry.then("the permission reports that it is trusted") { _ in
            XCTAssertTrue(self.permission.isTrusted)
        }
        registry.then("the permission reports that it is not trusted") { _ in
            XCTAssertFalse(self.permission.isTrusted)
        }
    }
}
