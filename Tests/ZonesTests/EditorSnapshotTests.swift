import AppKit
import XCTest
@testable import ZonesCore

/// Renders the editor's windows to PNG for visual review.
///
/// Opt-in: set `ZONES_EDITOR_SNAPSHOT_DIR` to a directory and run
/// `swift test --filter EditorSnapshotTests`. Without it every test skips, so
/// the suite never writes files. The views are drawn offscreen with
/// `cacheDisplay`, which is the only way to look at them from a shell that
/// cannot capture the screen.
final class EditorSnapshotTests: XCTestCase {

    private var outputDirectory: URL!
    private var store: LayoutStore!
    private var settings: Settings!

    private let wide = EditorDisplay(
        identity: DisplayIdentity(key: "snapshot-wide", source: .uuid),
        frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1415),
        pixelSize: CGSize(width: 5120, height: 2880))
    private let laptop = EditorDisplay(
        identity: DisplayIdentity(key: "snapshot-laptop", source: .uuid),
        frame: CGRect(x: -1512, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: -1512, y: 0, width: 1512, height: 950),
        pixelSize: CGSize(width: 3024, height: 1964))
    /// A display small enough to make a readable editor snapshot.
    private let small = EditorDisplay(
        identity: DisplayIdentity(key: "snapshot-small", source: .uuid),
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
        pixelSize: CGSize(width: 2880, height: 1800))

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["ZONES_EDITOR_SNAPSHOT_DIR"] else {
            throw XCTSkip("set ZONES_EDITOR_SNAPSHOT_DIR to render editor snapshots")
        }
        outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        store = LayoutStore(storage: InMemorySettingsStorage())
        store.installBuiltInsIfEmpty()
        settings = Settings(storage: InMemorySettingsStorage(), notificationCenter: NotificationCenter())
    }

    private var appearances: [(String, NSAppearance)] {
        [("light", NSAppearance(named: .aqua)!), ("dark", NSAppearance(named: .darkAqua)!)]
    }

    private func customLayout() -> ZoneLayout {
        var layout = LayoutTemplate.columns(2)
        layout = LayoutEditing.split(zoneID: layout.zones[1].id, axis: .horizontal, at: 0.4, in: layout)
        layout = LayoutEditing.split(zoneID: layout.zones[0].id, axis: .horizontal, at: 0.65, in: layout)
        layout.name = "Coding"
        return layout
    }

    private func canvasLayout() -> ZoneLayout {
        ZoneLayout(name: "Floating", zones: [
            Zone(index: 0, rect: CGRect(x: 0.05, y: 0.08, width: 0.5, height: 0.6)),
            Zone(index: 1, rect: CGRect(x: 0.4, y: 0.3, width: 0.52, height: 0.6)),
            Zone(index: 2, rect: CGRect(x: 0.66, y: 0.06, width: 0.28, height: 0.3)),
        ], origin: .canvas)
    }

    // MARK: Rendering

    private func render(_ view: NSView, appearance: NSAppearance) -> NSBitmapImageRep {
        view.appearance = appearance
        view.window?.appearance = appearance
        view.layoutSubtreeIfNeeded()
        view.needsDisplay = true
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        appearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        return rep
    }

    private func write(_ rep: NSBitmapImageRep, _ name: String) throws {
        let url = outputDirectory.appendingPathComponent("\(name).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    /// The editor is translucent, so it is composited over a stand-in desktop
    /// to look the way it does on screen.
    private func writeOverDesktop(_ rep: NSBitmapImageRep, _ name: String) throws {
        let size = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.32, blue: 0.55, alpha: 1),
                                NSColor(calibratedRed: 0.62, green: 0.42, blue: 0.58, alpha: 1)])!
                .draw(in: rect, angle: 35)
            rep.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                     respectFlipped: false, hints: nil)
            return true
        }
        let out = NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))!
        try write(out, name)
    }

    // MARK: Snapshots

    func testPicker() throws {
        let custom = customLayout()
        store.save(custom)
        store.save(canvasLayout())
        store.assign(layoutID: custom.id, to: wide.identity)

        for (name, appearance) in appearances {
            let picker = LayoutPickerWindowController(store: store, settings: settings,
                                                      displays: [wide, laptop],
                                                      selected: wide.identity)
            let window = try XCTUnwrap(picker.window)
            window.setContentSize(NSSize(width: 920, height: 760))
            picker.templateCardsForTesting[2].setHoveredForTesting(true)
            try write(render(try XCTUnwrap(window.contentView), appearance: appearance),
                      "picker-\(name)")
        }
    }

    func testPickerSingleDisplay() throws {
        let picker = LayoutPickerWindowController(store: store, settings: settings,
                                                  displays: [small], selected: small.identity)
        let window = try XCTUnwrap(picker.window)
        window.setContentSize(NSSize(width: 720, height: 640))
        try write(render(try XCTUnwrap(window.contentView), appearance: appearances[1].1),
                  "picker-single-dark")
    }

    func testEditDialogs() throws {
        let custom = customLayout()
        store.save(custom)
        for (name, appearance) in appearances {
            let template = EditLayoutSheetController(layout: LayoutTemplate.columns(3),
                                                     settings: settings.current)
            try write(render(try XCTUnwrap(template.window?.contentView), appearance: appearance),
                      "edit-template-\(name)")
            let customSheet = EditLayoutSheetController(layout: custom, settings: settings.current)
            try write(render(try XCTUnwrap(customSheet.window?.contentView), appearance: appearance),
                      "edit-custom-\(name)")
            let create = CreateLayoutSheetController(suggestedName: "Custom layout 1")
            try write(render(try XCTUnwrap(create.window?.contentView), appearance: appearance),
                      "create-\(name)")
        }
    }

    func testGridZoneEditor() throws {
        for (name, appearance) in appearances {
            let editor = ZoneEditorWindowController(layout: customLayout(), display: small,
                                                    settings: settings.current)
            let grid = try XCTUnwrap(editor.gridView)
            let content = try XCTUnwrap(editor.window?.contentView)
            content.frame = CGRect(origin: .zero, size: small.visibleFrame.size)
            grid.frame = content.bounds
            editor.layoutToolbar()
            // Hover the big left zone so the split preview shows.
            grid.updateHover(at: CGPoint(x: 420, y: 520), shift: false)
            try writeOverDesktop(render(content, appearance: appearance), "grid-editor-\(name)")

            // A two-zone selection on the right, so the merge button shows.
            let right = Set(grid.layout.zones.filter { $0.rect.minX > 0.4 }.map(\.id))
            grid.setSelectionForTesting(right)
            try writeOverDesktop(render(content, appearance: appearance), "grid-editor-merge-\(name)")
        }
    }

    func testCanvasZoneEditor() throws {
        for (name, appearance) in appearances {
            let editor = ZoneEditorWindowController(layout: canvasLayout(), display: small,
                                                    settings: settings.current)
            let canvas = try XCTUnwrap(editor.canvasView)
            let content = try XCTUnwrap(editor.window?.contentView)
            content.frame = CGRect(origin: .zero, size: small.visibleFrame.size)
            canvas.frame = content.bounds
            editor.layoutToolbar()
            canvas.selectForTesting(canvas.layout.zones[1].id)
            try writeOverDesktop(render(content, appearance: appearance), "canvas-editor-\(name)")
        }
    }
}
