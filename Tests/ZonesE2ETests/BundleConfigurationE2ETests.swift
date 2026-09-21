import XCTest

/// The shipping Info.plist is a contract with macOS, and getting it wrong is
/// invisible until the app is bundled and installed. These assertions guard the
/// keys that decide what kind of app Zones is.
final class BundleConfigurationE2ETests: XCTestCase {

    private func loadInfoPlist() throws -> [String: Any] {
        // Tests/ZonesE2ETests/ -> repository root -> packaging/Info.plist
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("packaging/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }

    func testDeclaresItselfAsAMenuBarAccessory() throws {
        let plist = try loadInfoPlist()
        // Without LSUIElement the bundled app gets a Dock icon and takes focus
        // on launch — the opposite of what Zones is.
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
    }

    func testBundleIdentifierMatchesTheOneUsedInCode() throws {
        let plist = try loadInfoPlist()
        // Settings keys, the log subsystem and the defaults domain all hang off
        // this identifier. Changing it orphans every user's saved settings.
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.pinyridgelabs.Zones")
    }

    func testMinimumSystemVersionMatchesThePackageManifest() throws {
        let plist = try loadInfoPlist()
        // Package.swift declares .macOS(.v13); a higher or lower floor here
        // means the bundle and the build disagree about who can run Zones.
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "13.0")
    }

    func testPrincipalClassIsSet() throws {
        let plist = try loadInfoPlist()
        XCTAssertEqual(plist["NSPrincipalClass"] as? String, "NSApplication")
    }
}
