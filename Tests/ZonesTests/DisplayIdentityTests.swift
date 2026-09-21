import XCTest
@testable import ZonesCore

final class DisplayIdentityTests: XCTestCase {

    func testGeometryKeyIsStableAcrossFractionalJitter() {
        // Reported geometry can differ by a fraction of a point between reads.
        // If that produced a new identity, a display would lose its layout
        // without anything actually changing.
        let a = DisplayIdentity.geometryKey(for: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let b = DisplayIdentity.geometryKey(for: CGRect(x: 0.4, y: -0.3,
                                                        width: 1920.2, height: 1079.8))
        XCTAssertEqual(a, b)
    }

    func testGeometryKeyDistinguishesDifferentPositions() {
        let a = DisplayIdentity.geometryKey(for: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let b = DisplayIdentity.geometryKey(for: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        XCTAssertNotEqual(a, b)
    }

    func testIdentitiesCompareAndHashByKey() {
        let a = DisplayIdentity(key: "abc", source: .uuid)
        let b = DisplayIdentity(key: "abc", source: .uuid)
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set([a, b]).count, 1)
    }

    func testSourceRecordsHowTheIdentityWasDerived() {
        // A geometry identity is weaker than a UUID one — two identical
        // monitors in the same position are indistinguishable — so callers
        // are able to tell which they are holding.
        let fallback = DisplayIdentity(key: DisplayIdentity.geometryKey(for: .zero),
                                       source: .geometry)
        XCTAssertEqual(fallback.source, .geometry)
    }

    func testRealScreensProduceIdentitiesWithoutCrashing() throws {
        let screens = NSScreen.screens
        try XCTSkipIf(screens.isEmpty, "no attached displays in this environment")
        for screen in screens {
            let identity = DisplayIdentity.forScreen(screen)
            XCTAssertFalse(identity.key.isEmpty)
        }
    }
}

/// A source-level guard, in the spirit of Tack's "never compare frames for
/// equality" rule.
///
/// The risk this epic exists to avoid is keying persisted layouts on
/// `CGDirectDisplayID`, which macOS recycles across reconnects. That mistake
/// compiles, passes every behavioural test on a single-display machine, and
/// only shows up as "my external monitor came back with the laptop's layout".
/// So it is asserted against the source itself.
final class DisplayIdentityKeyGuardTests: XCTestCase {

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ZonesTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/ZonesCore")
    }

    func testPersistenceLayerNeverMentionsCGDirectDisplayID() throws {
        // DisplayIdentity.swift is the one place allowed to touch the raw ID,
        // because converting it to a UUID is precisely its job.
        let offenders = try swiftFiles()
            .filter { $0.lastPathComponent != "DisplayIdentity.swift" }
            .filter { url in
                let source = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                return source.contains("CGDirectDisplayID")
            }
            .map(\.lastPathComponent)

        XCTAssertTrue(offenders.isEmpty,
                      "CGDirectDisplayID is recycled by macOS and must not leak out of "
                      + "DisplayIdentity. Found in: \(offenders.joined(separator: ", "))")
    }

    func testLayoutStoreKeysAssignmentsByIdentityKey() throws {
        let url = sourceRoot.appendingPathComponent("Layout/LayoutStore.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("display.key"),
                      "assignments must be keyed by DisplayIdentity.key")
        XCTAssertFalse(source.contains("displayID"),
                       "LayoutStore must not see a raw display ID")
    }

    private func swiftFiles() throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: sourceRoot, includingPropertiesForKeys: nil) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
