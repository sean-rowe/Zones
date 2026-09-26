import XCTest
@testable import ZonesCore

/// The menu is the only way into Zones, so its wiring is worth asserting. A menu
/// item with a nil target silently does nothing when clicked, which looks
/// identical to a broken feature.
final class ZonesControllerMenuTests: XCTestCase {

    /// Held for the duration of each test.
    ///
    /// `NSMenuItem.target` is a WEAK reference, so a menu outliving its
    /// controller has nil targets and every item silently does nothing. In the
    /// app `AppDelegate` holds the controller for the process lifetime; a test
    /// has to hold it deliberately or it is asserting against a dead object.
    private var retained: ZonesController?

    override func tearDown() {
        retained = nil
        super.tearDown()
    }

    private func controller(trusted: Bool) -> ZonesController {
        let center = NotificationCenter()
        let controller = ZonesController(
            permission: AccessibilityPermission(notificationCenter: center,
                                                trustProvider: { trusted }),
            settings: Settings(storage: InMemorySettingsStorage(),
                               notificationCenter: center),
            layouts: LayoutStore(storage: InMemorySettingsStorage()),
            displays: DisplayObserver(sourceCenter: center, notificationCenter: center)
        )
        retained = controller
        return controller
    }

    func testTheMenuOffersTheEditorAndQuit() {
        let titles = controller(trusted: true).menuForTesting().items.map(\.title)
        XCTAssertTrue(titles.contains { $0.hasPrefix("Edit Layout") },
                      "no way to reach the editor; have \(titles)")
        XCTAssertTrue(titles.contains { $0.hasPrefix("Quit") })
    }

    func testTheEditorItemHasATargetAndAnAction() {
        let menu = controller(trusted: true).menuForTesting()
        guard let item = menu.items.first(where: { $0.title.hasPrefix("Edit Layout") }) else {
            return XCTFail("no editor menu item")
        }
        // Both are required: an item with an action but no target sends to the
        // responder chain and quietly does nothing here.
        XCTAssertNotNil(item.action)
        XCTAssertNotNil(item.target)
    }

    func testTheStatusLineReportsWhenAccessibilityIsMissing() {
        let untrusted = controller(trusted: false).menuForTesting()
        let first = untrusted.items.first?.title ?? ""
        XCTAssertTrue(first.lowercased().contains("accessibility"),
                      "an untrusted launch must say so in the menu; got \(first)")
    }

    func testTheStatusLineReportsWhenActive() {
        let trusted = controller(trusted: true).menuForTesting()
        XCTAssertEqual(trusted.items.first?.title, "Zones is active")
    }

    func testTheStatusLineIsNotClickable() {
        let menu = controller(trusted: true).menuForTesting()
        XCTAssertFalse(menu.items[0].isEnabled, "the status line is a label, not an action")
    }
}
