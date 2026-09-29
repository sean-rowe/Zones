import XCTest
import AppKit
@testable import ZonesCore

final class KeyComboTests: XCTestCase {
    func testShadowingWarningDetectsBrowserTabKeys() {
        // ⌘1 is keyCode 18 with .command
        let cmd1 = KeyCombo(keyCode: 18, modifierFlags: NSEvent.ModifierFlags.command.rawValue)
        let warning = KeyCombo.shadowingWarning(for: cmd1)
        XCTAssertNotNil(warning, "⌘1 must produce a shadowing warning")
    }

    func testShadowingWarningDetectsTabCyclingKey() {
        // ⌃Tab is keyCode 48 with .control
        let ctrlTab = KeyCombo(keyCode: 48, modifierFlags: NSEvent.ModifierFlags.control.rawValue)
        let warning = KeyCombo.shadowingWarning(for: ctrlTab)
        XCTAssertNotNil(warning, "⌃Tab must produce a shadowing warning")
    }

    func testSafeChordHasNoShadowingWarning() {
        // ⌃⌥⌘1 has [.control, .option, .command]
        let safeChord = KeyCombo(
            keyCode: 18,
            modifierFlags: NSEvent.ModifierFlags([.control, .option, .command]).rawValue
        )
        let warning = KeyCombo.shadowingWarning(for: safeChord)
        XCTAssertNil(warning, "⌃⌥⌘1 is safe and must not produce a shadowing warning")
    }

    func testDisplayStringFormatsModifiers() {
        let combo = KeyCombo(
            keyCode: 18,
            modifierFlags: NSEvent.ModifierFlags([.control, .option, .command]).rawValue
        )
        XCTAssertEqual(combo.displayString, "⌃⌥⌘1")
    }
}
