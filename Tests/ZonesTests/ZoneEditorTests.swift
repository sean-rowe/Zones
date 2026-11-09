import XCTest
@testable import ZonesCore

final class ZoneEditorTests: XCTestCase {

    private var store: LayoutStore!
    private var settings: Settings!
    private let display = DisplayIdentity(key: "test-display", source: .uuid)
    private let size = CGSize(width: 1600, height: 900)
    /// Held so the canvas's weak callbacks reach it.
    private var editors: [ZoneEditor] = []

    override func setUp() {
        super.setUp()
        store = LayoutStore(storage: InMemorySettingsStorage())
        settings = Settings(storage: InMemorySettingsStorage(), notificationCenter: NotificationCenter())
    }

    private func editor() -> (ZoneEditor, ZoneEditorCanvas) {
        let editor = ZoneEditor(store: store, settings: settings)
        let canvas = editor.makeCanvas(for: display, size: size)
        editors.append(editor)
        return (editor, canvas)
    }

    func testOpensWithTheDisplaysCurrentLayout() {
        let layout = LayoutTemplate.grid(rows: 2, columns: 2)
        store.save(layout)
        store.assign(layoutID: layout.id, to: display)
        XCTAssertEqual(editor().1.tree.leafCount, 4)
    }

    func testOpensWithOneZoneWhenNothingIsAssigned() {
        XCTAssertEqual(editor().1.tree, .leaf)
    }

    func testNumberKeysLoadPresets() {
        let (_, canvas) = editor()
        XCTAssertTrue(canvas.handleKey(keyCode: 20, characters: "3"))
        XCTAssertEqual(canvas.tree, SplitTree(preset: .quarters))
        XCTAssertFalse(canvas.handleKey(keyCode: 23, characters: "5"))
    }

    func testReturnAppliesAsCustomLayoutForTheDisplay() {
        let builtIn = LayoutTemplate.columns(2)
        store.save(builtIn)
        store.assign(layoutID: builtIn.id, to: display)
        let (_, canvas) = editor()
        canvas.load(.thirds)
        canvas.setGap(12)
        canvas.handleKey(keyCode: 36, characters: "\r")

        let applied = store.assignedLayout(for: display)!
        XCTAssertNotEqual(applied.id, builtIn.id, "a built-in must not be overwritten")
        XCTAssertEqual(applied.origin, .custom)
        XCTAssertEqual(applied.zones.count, 3)
        XCTAssertEqual(store.layout(id: builtIn.id)?.zones.count, 2)
        XCTAssertEqual(settings.current.zoneGap, 12)
    }

    func testApplyingAgainOverwritesTheSameCustomLayout() {
        var (_, canvas) = editor()
        canvas.load(.halves)
        canvas.handleKey(keyCode: 36, characters: "\r")
        let first = store.assignedLayout(for: display)!.id

        (_, canvas) = editor()
        canvas.load(.quarters)
        canvas.handleKey(keyCode: 76, characters: "\u{3}")
        XCTAssertEqual(store.assignedLayout(for: display)?.id, first)
        XCTAssertEqual(store.assignedLayout(for: display)?.zones.count, 4)
        XCTAssertEqual(store.layouts.filter { $0.name == "Custom" }.count, 1)
    }

    func testEscapeSavesNothing() {
        let (_, canvas) = editor()
        canvas.load(.quarters)
        canvas.setGap(30)
        canvas.handleKey(keyCode: 53, characters: "\u{1b}")
        XCTAssertNil(store.assignedLayout(for: display))
        XCTAssertEqual(settings.current.zoneGap, AppSettings().zoneGap)
    }

    func testClickSplitsAndDragPlacesTheNewDivider() {
        let (_, canvas) = editor()
        canvas.press(at: CGPoint(x: 0.5, y: 0.5), shift: false)
        canvas.drag(to: CGPoint(x: 0.7, y: 0.5))
        let rects = canvas.tree.zoneRects()
        XCTAssertEqual(rects.count, 2)
        XCTAssertEqual(rects[0].width, 0.7, accuracy: 1e-9)
    }

    func testRightClickMerges() {
        let (_, canvas) = editor()
        canvas.load(.halves)
        canvas.merge(at: CGPoint(x: 0.75, y: 0.5))
        XCTAssertEqual(canvas.tree, .leaf)
    }

    func testGapIsClampedToPineOSRange() {
        let (_, canvas) = editor()
        canvas.setGap(500)
        XCTAssertEqual(canvas.gap, 64)
        canvas.setGap(-4)
        XCTAssertEqual(canvas.gap, 0)
    }

    func testDimensionsAreTheSnappedWindowSize() {
        settings.update { $0.outerPadding = 0 }
        let (_, canvas) = editor()
        canvas.load(.halves)
        canvas.setGap(8)
        let rects = canvas.resolvedZoneRects()
        XCTAssertEqual(rects[0].width, 796, accuracy: 0.5)
        XCTAssertEqual(rects[1].minX, 804, accuracy: 0.5)
    }

    func testHorizontalSplitPutsZoneOneOnTop() {
        settings.update { $0.outerPadding = 0 }
        let (_, canvas) = editor()
        canvas.setGap(0)
        canvas.press(at: CGPoint(x: 0.5, y: 0.25), shift: true)
        let rects = canvas.resolvedZoneRects()
        // AppKit is Y-up: the top zone sits at the top of the view.
        XCTAssertEqual(rects[0].height, 225, accuracy: 0.5)
        XCTAssertEqual(rects[0].maxY, 900, accuracy: 0.5)
        XCTAssertEqual(rects[1].minY, 0, accuracy: 0.5)
    }

    func testNaNGapIsIgnored() {
        let (_, canvas) = editor()
        canvas.setGap(10)
        canvas.setGap(.nan)
        XCTAssertEqual(canvas.gap, 10)
    }

    /// Writes PNGs of the editor over a desktop-like backdrop when
    /// ZONES_EDITOR_SNAPSHOT_DIR is set, for checking against PineOS.
    func testRenderSnapshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["ZONES_EDITOR_SNAPSHOT_DIR"] else {
            throw XCTSkip("set ZONES_EDITOR_SNAPSHOT_DIR to render")
        }
        for preset in SplitTree.Preset.allCases {
            let (_, canvas) = editor()
            canvas.load(preset)
            canvas.layoutSubtreeIfNeeded()
            canvas.layout()
            let backdrop = NSView(frame: CGRect(origin: .zero, size: size))
            backdrop.wantsLayer = true
            backdrop.layer?.backgroundColor = NSColor(srgbRed: 0.35, green: 0.3, blue: 0.55, alpha: 1).cgColor
            backdrop.addSubview(canvas)
            let rep = backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds)!
            backdrop.cacheDisplay(in: backdrop.bounds, to: rep)
            let url = URL(fileURLWithPath: dir).appendingPathComponent("editor-\(preset.title).png")
            try rep.representation(using: .png, properties: [:])!.write(to: url)
        }
    }
}
