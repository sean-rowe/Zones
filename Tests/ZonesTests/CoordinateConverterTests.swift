import XCTest
import AppKit
@testable import ZonesCore

final class CoordinateConverterTests: XCTestCase {
    func testConversion() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 200)
        let converted = CoordinateConverter.cgToAppKit(rect, primaryHeight: 1000)
        let back = CoordinateConverter.appKitToCG(converted, primaryHeight: 1000)

        XCTAssertEqual(rect.width, back.width)
        XCTAssertEqual(rect.height, back.height)
        XCTAssertEqual(rect.origin.x, back.origin.x)
        XCTAssertEqual(rect.origin.y, back.origin.y)
    }

    func testPointConversion() {
        let point = CGPoint(x: 150, y: 250)
        let converted = CoordinateConverter.cgToAppKit(point, primaryHeight: 1000)
        let back = CoordinateConverter.appKitToCG(converted, primaryHeight: 1000)

        XCTAssertEqual(point.x, back.x)
        XCTAssertEqual(point.y, back.y)
    }

    func testDisplayPositionedAbovePrimary() {
        // Primary screen: 1920x1080, primaryHeight = 1080
        // Screen above: origin (0, 1080), size (1920, 1080) in AppKit
        let primaryHeight: CGFloat = 1080
        let screenAboveAppKit = NSRect(x: 0, y: 1080, width: 1920, height: 1080)
        let screenAboveCG = CoordinateConverter.appKitToCG(screenAboveAppKit, primaryHeight: primaryHeight)

        // In CG, y is negative: 1080 - 1080 - 1080 = -1080
        XCTAssertEqual(screenAboveCG.origin.x, 0)
        XCTAssertEqual(screenAboveCG.origin.y, -1080)
        XCTAssertEqual(screenAboveCG.width, 1920)
        XCTAssertEqual(screenAboveCG.height, 1080)

        // Top-left zone on screen above:
        // In AppKit, top-left quadrant is x: 0..960, y: 1620..2160
        let topLeftAppKit = NSRect(x: 0, y: 1620, width: 960, height: 540)
        let topLeftCG = CoordinateConverter.appKitToCG(topLeftAppKit, primaryHeight: primaryHeight)

        // CG rect is x: 0, y: -1080, width: 960, height: 540
        XCTAssertEqual(topLeftCG.origin.x, 0)
        XCTAssertEqual(topLeftCG.origin.y, -1080)

        // Verify it is completely within screenAboveCG and not off-screen
        XCTAssertTrue(screenAboveCG.contains(topLeftCG), "Top-left zone must land inside the above display's bounds")
    }

    func testDisplayPositionedLeftOfPrimary() {
        // Primary screen: 1920x1080, primaryHeight = 1080
        // Screen left: origin (-1920, 0), size (1920, 1080) in AppKit
        let primaryHeight: CGFloat = 1080
        let screenLeftAppKit = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        let screenLeftCG = CoordinateConverter.appKitToCG(screenLeftAppKit, primaryHeight: primaryHeight)

        XCTAssertEqual(screenLeftCG.origin.x, -1920)
        XCTAssertEqual(screenLeftCG.origin.y, 0)
        XCTAssertEqual(screenLeftCG.width, 1920)
        XCTAssertEqual(screenLeftCG.height, 1080)

        // Any zone on screen left:
        let zoneAppKit = NSRect(x: -1920, y: 540, width: 960, height: 540)
        let zoneCG = CoordinateConverter.appKitToCG(zoneAppKit, primaryHeight: primaryHeight)

        XCTAssertEqual(zoneCG.origin.x, -1920)
        XCTAssertEqual(zoneCG.origin.y, 0)
        XCTAssertTrue(screenLeftCG.contains(zoneCG), "Zone must land inside the left display's bounds")
    }

    func testMixedHeightDisplays1080pBeside4K() {
        // Primary: 1080p (height 1080), Secondary: 4K (height 2160, width 3840) at x: 1920, y: 0
        let primaryHeight: CGFloat = 1080
        CoordinateConverter.primaryScreenHeightProvider = { primaryHeight }
        defer { CoordinateConverter.primaryScreenHeightProvider = nil }

        let screen1080AppKit = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let screen4KAppKit = NSRect(x: 1920, y: 0, width: 3840, height: 2160)

        let cg1080 = CoordinateConverter.appKitToCG(screen1080AppKit)
        let cg4K = CoordinateConverter.appKitToCG(screen4KAppKit)

        // 1080p CG bounds: (0, 0, 1920, 1080)
        XCTAssertEqual(cg1080, CGRect(x: 0, y: 0, width: 1920, height: 1080))
        // 4K CG bounds: (1920, -1080, 3840, 2160)
        XCTAssertEqual(cg4K, CGRect(x: 1920, y: -1080, width: 3840, height: 2160))

        // Conversion is invariant to which screen has focus: both use the same primaryHeight
        let zone4KAppKit = NSRect(x: 1920, y: 1080, width: 1920, height: 1080)
        let zone4KCG = CoordinateConverter.appKitToCG(zone4KAppKit)
        XCTAssertEqual(zone4KCG, CGRect(x: 1920, y: -1080, width: 1920, height: 1080))
        XCTAssertTrue(cg4K.contains(zone4KCG))
    }

    func testLintNSScreenMainNeverUsedInSnapOrDragPaths() throws {
        // ZONES-107: Assert NSScreen.main appears nowhere in snap or drag paths
        let sourcesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ZonesCore")

        let pathsToCheck = ["Snapping", "Drag", "Overlay", "HotKey", "Geometry", "Utilities"]
        let fm = FileManager.default

        for sub in pathsToCheck {
            let dir = sourcesDir.appendingPathComponent(sub)
            guard fm.fileExists(atPath: dir.path) else { continue }
            let enumerator = fm.enumerator(atPath: dir.path)
            while let file = enumerator?.nextObject() as? String {
                guard file.hasSuffix(".swift") else { continue }
                let filePath = dir.appendingPathComponent(file).path
                let content = try String(contentsOfFile: filePath, encoding: .utf8)
                for (index, line) in content.components(separatedBy: .newlines).enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") || trimmed.hasPrefix("*") {
                        continue
                    }
                    if trimmed.contains("NSScreen.main") {
                        XCTFail("Forbidden NSScreen.main found in \(sub)/\(file):\(index + 1): \(line)")
                    }
                }
            }
        }
    }
}
