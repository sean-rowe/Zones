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

    /// Opens the real overlay window on the main screen and drives it with
    /// real events. Runs when ZONES_EDITOR_LIVE is set, since it briefly
    /// covers the screen.
    func testLiveWindowOnARealScreen() throws {
        guard ProcessInfo.processInfo.environment["ZONES_EDITOR_LIVE"] != nil else {
            throw XCTSkip("set ZONES_EDITOR_LIVE to open the editor on screen")
        }
        let screen = try XCTUnwrap(NSScreen.main)
        let identity = DisplayIdentity.forScreen(screen)
        let editor = ZoneEditor(store: store, settings: settings)
        editors.append(editor)
        editor.present(on: screen)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        let window = try XCTUnwrap(editor.window)
        let canvas = try XCTUnwrap(editor.canvas)
        XCTAssertEqual(window.frame, screen.visibleFrame, "covers the work area, not the menu bar or Dock")
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(window.firstResponder === canvas, "keys must reach the canvas")
        XCTAssertGreaterThan(canvas.toolbar.frame.width, 300)
        XCTAssertEqual(canvas.toolbar.frame.midX, canvas.bounds.midX, accuracy: 1)
        XCTAssertEqual(canvas.toolbar.frame.maxY, canvas.bounds.maxY - 12, accuracy: 1)

        func mouse(_ type: NSEvent.EventType, _ p: CGPoint, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags,
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil,
                                             eventNumber: 0, clickCount: 1, pressure: 1))
        }
        let size = canvas.bounds.size
        // Click in the middle splits; dragging places the divider at 30%.
        window.sendEvent(try mouse(.leftMouseDown, CGPoint(x: size.width * 0.5, y: size.height * 0.5)))
        window.sendEvent(try mouse(.leftMouseDragged, CGPoint(x: size.width * 0.3, y: size.height * 0.5)))
        window.sendEvent(try mouse(.leftMouseUp, CGPoint(x: size.width * 0.3, y: size.height * 0.5)))
        XCTAssertEqual(canvas.tree.zoneRects().first?.width ?? 0, 0.3, accuracy: 0.005)
        // Shift-click the right zone splits it top/bottom.
        window.sendEvent(try mouse(.leftMouseDown, CGPoint(x: size.width * 0.7, y: size.height * 0.5), flags: .shift))
        window.sendEvent(try mouse(.leftMouseUp, CGPoint(x: size.width * 0.7, y: size.height * 0.5)))
        XCTAssertEqual(canvas.tree.leafCount, 3)
        // Right-click the bottom-right zone merges it away.
        window.sendEvent(try mouse(.rightMouseDown, CGPoint(x: size.width * 0.7, y: size.height * 0.2)))
        XCTAssertEqual(canvas.tree.leafCount, 2)
        // The toolbar's Quarters button is what a click there hits, and it
        // loads the preset. performClick, because a synthesized mouse-down
        // on an NSButton waits for a real mouse-up.
        let quarters = try XCTUnwrap(canvas.toolbar.subviews.first?.subviews
            .compactMap { $0 as? ToolbarButton }.first { $0.attributedTitle.string == "3: Quarters" })
        let inCanvas = quarters.convert(CGPoint(x: quarters.bounds.midX, y: quarters.bounds.midY), to: canvas)
        XCTAssertTrue(canvas.hitTest(inCanvas) === quarters, "toolbar clicks must not reach the canvas")
        quarters.performClick(nil)
        XCTAssertEqual(canvas.tree, SplitTree(preset: .quarters))

        if let dir = ProcessInfo.processInfo.environment["ZONES_EDITOR_SNAPSHOT_DIR"],
           let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) {
            canvas.cacheDisplay(in: canvas.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("editor-live.png"))
        }

        let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil,
                                                 characters: "\r", charactersIgnoringModifiers: "\r",
                                                 isARepeat: false, keyCode: 36))
        window.sendEvent(key)
        XCTAssertNil(editor.window, "Return applies and closes")
        XCTAssertEqual(store.assignedLayout(for: identity)?.zones.count, 4)
    }
}
