import AppKit
import XCTest
@testable import ZonesCore

/// The editor's windows and views, driven without putting them on screen.
final class LayoutEditorWindowTests: XCTestCase {

    private var store: LayoutStore!
    private var settings: Settings!

    private let main = EditorDisplay(
        identity: DisplayIdentity(key: "window-main", source: .uuid),
        frame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
        visibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
        pixelSize: CGSize(width: 3200, height: 2000))
    private let side = EditorDisplay(
        identity: DisplayIdentity(key: "window-side", source: .uuid),
        frame: CGRect(x: 1600, y: 0, width: 1280, height: 800),
        visibleFrame: CGRect(x: 1600, y: 0, width: 1280, height: 800),
        pixelSize: CGSize(width: 1280, height: 800))

    override func setUp() {
        super.setUp()
        store = LayoutStore(storage: InMemorySettingsStorage())
        store.installBuiltInsIfEmpty()
        settings = Settings(storage: InMemorySettingsStorage(), notificationCenter: NotificationCenter())
    }

    private func picker(_ displays: [EditorDisplay], selected: EditorDisplay? = nil)
        -> LayoutPickerWindowController {
        LayoutPickerWindowController(store: store, settings: settings, displays: displays,
                                     selected: (selected ?? displays.first)?.identity)
    }

    // MARK: Picker

    func testThePickerShowsEveryTemplateAndTheCustomLayouts() {
        let controller = picker([main])
        XCTAssertEqual(controller.templateCardsForTesting.map(\.title),
                       TemplateKind.allCases.map(\.title))
        XCTAssertEqual(controller.customCardsForTesting.map(\.title), ["3 Columns"])
    }

    func testOneDisplayHidesTheMonitorStrip() {
        XCTAssertTrue(picker([main]).monitorViewsForTesting.isEmpty)
        XCTAssertEqual(picker([side, main]).monitorViewsForTesting.map(\.number), [1, 2])
    }

    func testClickingACardAppliesItToTheSelectedDisplay() throws {
        let controller = picker([main, side], selected: side)
        let rows = try XCTUnwrap(controller.templateCardsForTesting.first { $0.title == "Rows" })
        rows.onSelect?()

        XCTAssertEqual(store.assignedLayout(for: side.identity)?.origin, .rows(count: 3))
        XCTAssertNil(store.assignedLayout(for: main.identity), "only the selected display changes")
        XCTAssertTrue(controller.templateCardsForTesting.first { $0.title == "Rows" }?.isApplied ?? false,
                      "the applied card is marked after the click")
    }

    func testSelectingAnotherMonitorShowsItsLayout() throws {
        let columns = try XCTUnwrap(store.layouts.first)
        store.assign(layoutID: columns.id, to: side.identity)
        let controller = picker([main, side], selected: main)
        XCTAssertFalse(controller.templateCardsForTesting.contains { $0.isApplied })

        controller.selectDisplay(side.identity)
        XCTAssertEqual(controller.templateCardsForTesting.first { $0.isApplied }?.title, "Columns")
        XCTAssertTrue(controller.monitorViewsForTesting[1].isSelected)
    }

    func testCardsPreviewTheSelectedDisplaysShape() {
        let controller = picker([main, side], selected: side)
        XCTAssertEqual(controller.templateCardsForTesting[0].aspectRatio, 1.6, accuracy: 0.001)
    }

    // MARK: Dialogs

    func testTheEditDialogSavesAZoneCountChange() throws {
        let columns = try XCTUnwrap(store.layouts.first)
        let sheet = EditLayoutSheetController(layout: columns, settings: settings.current)
        var saved: LayoutEditDraft?
        sheet.onSave = { saved = $0 }
        sheet.setDraftForTesting { $0.zoneCount = 4 }
        sheet.save()
        XCTAssertEqual(saved?.editedLayout.zones.count, 4)
        XCTAssertEqual(saved?.editedLayout.id, columns.id)
    }

    func testTheCreateDialogReportsTheChosenType() {
        let sheet = CreateLayoutSheetController(suggestedName: "Custom layout 1")
        var result: (String, Bool)?
        sheet.onCreate = { result = ($0, $1) }
        sheet.selectCanvasForTesting(true)
        sheet.create()
        XCTAssertEqual(result?.0, "Custom layout 1")
        XCTAssertEqual(result?.1, true)
    }

    // MARK: Grid editor

    private func gridEditor(_ layout: ZoneLayout) -> GridZoneEditorView {
        let view = GridZoneEditorView(layout: layout, spacing: ZoneSpacing(outerPadding: 0, gap: 0))
        view.frame = CGRect(x: 0, y: 0, width: 1000, height: 500)
        return view
    }

    func testClickingAZoneSplitsItAtThePointer() {
        let view = gridEditor(LayoutTemplate.columns(1))
        view.simulateClick(at: CGPoint(x: 300, y: 250))
        XCTAssertEqual(view.layout.zones.count, 2)
        XCTAssertEqual(view.layout.zones[0].rect.width, 0.3, accuracy: 0.001)
    }

    func testShiftClickSplitsHorizontally() {
        let view = gridEditor(LayoutTemplate.columns(1))
        // View y = 400 is 100pt from the top: normalized y 0.2.
        view.simulateClick(at: CGPoint(x: 300, y: 400), shift: true)
        XCTAssertEqual(view.layout.zones[0].rect.height, 0.2, accuracy: 0.001)
        XCTAssertEqual(view.layout.zones[0].rect.width, 1, accuracy: 0.001)
    }

    func testClickingOnADividerDoesNotSplit() {
        let view = gridEditor(LayoutTemplate.columns(2))
        XCTAssertNotNil(view.splitter(at: CGPoint(x: 501, y: 250)))
        view.simulateClick(at: CGPoint(x: 501, y: 250))
        XCTAssertEqual(view.layout.zones.count, 2)
    }

    func testMergingASelection() {
        let layout = LayoutTemplate.grid(rows: 2, columns: 2)
        let view = gridEditor(layout)
        var reported: Set<UUID> = []
        view.onSelectionChanged = { ids, _ in reported = ids }
        view.setSelectionForTesting([layout.zones[0].id, layout.zones[1].id])
        XCTAssertEqual(reported.count, 2)
        view.mergeSelection()
        XCTAssertEqual(view.layout.zones.count, 3)
        XCTAssertTrue(reported.isEmpty, "the merge button goes away after merging")
    }

    // MARK: Zone editor window

    func testSaveHandsBackTheEditedLayout() throws {
        let editor = ZoneEditorWindowController(layout: LayoutTemplate.columns(2), display: main,
                                                settings: settings.current)
        var saved: ZoneLayout?
        editor.onSave = { saved = $0 }
        let grid = try XCTUnwrap(editor.gridView)
        grid.frame = CGRect(origin: .zero, size: main.visibleFrame.size)
        grid.simulateClick(at: CGPoint(x: 200, y: 500))
        editor.save()
        XCTAssertEqual(saved?.zones.count, 3)
        XCTAssertNil(editor.canvasView)
    }

    func testCancelSavesNothingAndOnlyFiresOnce() {
        let editor = ZoneEditorWindowController(layout: LayoutTemplate.columns(2), display: main,
                                                settings: settings.current)
        var cancels = 0
        var saves = 0
        editor.onCancel = { cancels += 1 }
        editor.onSave = { _ in saves += 1 }
        editor.cancelOperation(nil)
        editor.cancel()
        editor.save()
        XCTAssertEqual(cancels, 1)
        XCTAssertEqual(saves, 0)
    }

    func testACanvasLayoutOpensTheCanvasEditor() throws {
        let layout = LayoutCatalog.newLayout(name: "C", canvas: true)
        let editor = ZoneEditorWindowController(layout: layout, display: main, settings: settings.current)
        let canvas = try XCTUnwrap(editor.canvasView)
        XCTAssertNotNil(editor.toolbar.addZoneButton)
        canvas.addZone()
        canvas.addZone()
        XCTAssertEqual(editor.layout.zones.count, 3)
        canvas.deleteZone(editor.layout.zones[0].id)
        XCTAssertEqual(editor.layout.zones.map(\.index), [0, 1])
    }

    func testTheEditorCoversTheVisibleFrame() {
        let editor = ZoneEditorWindowController(layout: LayoutTemplate.columns(2), display: side,
                                                settings: settings.current)
        XCTAssertEqual(editor.window?.frame, side.visibleFrame)
    }
}
