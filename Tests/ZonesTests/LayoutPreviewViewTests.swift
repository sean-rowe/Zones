import XCTest
@testable import ZonesCore

/// The preview's geometry: letterboxing, and the coordinate conversion that
/// turns a mouse point into a normalized model point.
final class LayoutPreviewViewTests: XCTestCase {

    private func view(size: CGSize, aspect: CGFloat) -> LayoutPreviewView {
        let view = LayoutPreviewView(layout: LayoutTemplate.columns(2), targetAspectRatio: aspect)
        view.frame = CGRect(origin: .zero, size: size)
        return view
    }

    func testPreviewMatchesTheTargetAspectNotTheViewAspect() {
        // A tall view showing a wide display must letterbox, not stretch:
        // otherwise the user designs against the wrong shape.
        let view = self.view(size: CGSize(width: 400, height: 800), aspect: 16.0 / 9.0)
        let rect = view.previewRect
        XCTAssertEqual(rect.width / rect.height, 16.0 / 9.0, accuracy: 0.01)
        XCTAssertLessThanOrEqual(rect.height, 800)
    }

    func testPreviewIsLetterboxedWhenTheViewIsWiderThanTheDisplay() {
        let view = self.view(size: CGSize(width: 1600, height: 400), aspect: 4.0 / 3.0)
        let rect = view.previewRect
        XCTAssertEqual(rect.width / rect.height, 4.0 / 3.0, accuracy: 0.01)
        XCTAssertLessThanOrEqual(rect.width, 1600)
    }

    func testPreviewIsCentred() {
        let view = self.view(size: CGSize(width: 600, height: 600), aspect: 16.0 / 9.0)
        let rect = view.previewRect
        XCTAssertEqual(rect.midX, view.bounds.midX, accuracy: 0.01)
        XCTAssertEqual(rect.midY, view.bounds.midY, accuracy: 0.01)
    }

    func testAZeroSizedViewYieldsAnEmptyPreviewRatherThanAnInvertedRect() {
        let view = self.view(size: .zero, aspect: 16.0 / 9.0)
        XCTAssertEqual(view.previewRect, .zero)
    }

    func testNormalizedPointFlipsTheYAxis() {
        let view = self.view(size: CGSize(width: 800, height: 500), aspect: 16.0 / 9.0)
        let rect = view.previewRect

        // The view's top edge (largest AppKit y) is the model's y = 0.
        let top = view.normalizedPoint(for: CGPoint(x: rect.midX, y: rect.maxY))
        XCTAssertEqual(top?.y ?? .nan, 0, accuracy: 0.01)

        let bottom = view.normalizedPoint(for: CGPoint(x: rect.midX, y: rect.minY))
        XCTAssertEqual(bottom?.y ?? .nan, 1, accuracy: 0.01)
    }

    func testAPointOnTheLeftEdgeNormalizesToZeroX() {
        let view = self.view(size: CGSize(width: 800, height: 500), aspect: 16.0 / 9.0)
        let rect = view.previewRect
        let left = view.normalizedPoint(for: CGPoint(x: rect.minX, y: rect.midY))
        XCTAssertEqual(left?.x ?? .nan, 0, accuracy: 0.01)
    }

    func testTheVerticalSplitterIsHitNearItsLineAndMissedAwayFromIt() {
        let view = self.view(size: CGSize(width: 800, height: 500), aspect: 16.0 / 9.0)
        let rect = view.previewRect
        let splitterX = rect.minX + 0.5 * rect.width

        XCTAssertNotNil(view.splitter(at: CGPoint(x: splitterX, y: rect.midY)),
                        "the divider must be grabbable on its line")
        XCTAssertNil(view.splitter(at: CGPoint(x: splitterX + 40, y: rect.midY)),
                     "40pt away is not the divider")
    }

    func testTheSplitterGrabAreaIsWiderThanASinglePoint() {
        // A 1pt target cannot be hit reliably, which is why AppKit gives
        // NSSplitView dividers a larger hit area than they draw.
        let view = self.view(size: CGSize(width: 800, height: 500), aspect: 16.0 / 9.0)
        let rect = view.previewRect
        let splitterX = rect.minX + 0.5 * rect.width
        XCTAssertNotNil(view.splitter(at: CGPoint(x: splitterX + 3, y: rect.midY)))
        XCTAssertNotNil(view.splitter(at: CGPoint(x: splitterX - 3, y: rect.midY)))
    }

    func testASplitterIsNotHitOutsideItsSpan() {
        // In an L-shaped layout the divider only exists along part of the edge,
        // so a point beyond its span must not grab it.
        let tall = Zone(index: 0, rect: CGRect(x: 0, y: 0, width: 0.5, height: 1))
        let upper = Zone(index: 1, rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.4))
        let view = LayoutPreviewView(layout: ZoneLayout(name: "L", zones: [tall, upper]),
                                     targetAspectRatio: 16.0 / 9.0)
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 500)
        let rect = view.previewRect
        let x = rect.minX + 0.5 * rect.width

        // Within the span (normalized y ≈ 0.2 → near the top of the preview).
        XCTAssertNotNil(view.splitter(at: CGPoint(x: x, y: rect.maxY - 0.2 * rect.height)))
        // Below it (normalized y ≈ 0.8), where the two zones no longer meet.
        XCTAssertNil(view.splitter(at: CGPoint(x: x, y: rect.maxY - 0.8 * rect.height)))
    }

    func testZoneHitTestingFindsTheZoneUnderThePoint() {
        let view = self.view(size: CGSize(width: 800, height: 500), aspect: 16.0 / 9.0)
        let rect = view.previewRect
        let left = view.zone(at: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.midY))
        let right = view.zone(at: CGPoint(x: rect.minX + rect.width * 0.75, y: rect.midY))
        XCTAssertEqual(left?.index, 0)
        XCTAssertEqual(right?.index, 1)
    }
}
