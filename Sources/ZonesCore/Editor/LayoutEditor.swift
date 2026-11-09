import AppKit

/// The layout editor, end to end: the picker window, its dialogs, and the
/// full-screen zone editor it hands off to.
///
/// This is the one type the rest of Zones talks to. The menu item, a hotkey or
/// the status item all call `present`, and everything after that — which
/// window is showing, what gets saved — is handled here.
public final class LayoutEditor {

    private let store: LayoutStore
    private let settings: Settings
    private let displayProvider: () -> [EditorDisplay]

    private(set) var picker: LayoutPickerWindowController?
    private(set) var zoneEditor: ZoneEditorWindowController?

    /// - Parameter displays: the attached displays. Injectable so a test can
    ///   drive the editor with an arrangement the test machine does not have.
    public init(store: LayoutStore = .shared,
                settings: Settings = .shared,
                displays: @escaping () -> [EditorDisplay] = EditorDisplay.current) {
        self.store = store
        self.settings = settings
        self.displayProvider = displays
    }

    /// Whether any editor window is on screen.
    public var isPresented: Bool {
        (picker?.window?.isVisible ?? false) || zoneEditor != nil
    }

    /// Open the layout picker for the display under the mouse pointer.
    public func present() {
        present(display: Self.displayUnderMouse())
    }

    /// Open the layout picker for a screen.
    public func present(on screen: NSScreen) {
        present(display: DisplayIdentity.forScreen(screen))
    }

    /// Open the layout picker with a display selected. Nil selects the first.
    ///
    /// If the zone editor is already open it is brought forward instead: a
    /// second entry point (a hotkey pressed mid-edit) must not silently
    /// abandon the layout being drawn.
    public func present(display identity: DisplayIdentity?) {
        if let zoneEditor {
            zoneEditor.present()
            return
        }
        let displays = displayProvider()
        if let picker {
            picker.update(displays: displays, selecting: identity)
        } else {
            let picker = LayoutPickerWindowController(store: store, settings: settings,
                                                      displays: displays, selected: identity)
            picker.onEditZones = { [weak self] layout, display in
                self?.openZoneEditor(for: layout, on: display)
            }
            picker.onCreate = { [weak self] layout, display in
                self?.openZoneEditor(for: layout, on: display)
            }
            self.picker = picker
        }
        picker?.present()
    }

    /// Close every editor window without saving.
    public func dismiss() {
        zoneEditor?.cancel()
        picker?.close()
    }

    // MARK: Zone editor

    func openZoneEditor(for layout: ZoneLayout, on display: EditorDisplay) {
        let editor = ZoneEditorWindowController(layout: layout, display: display,
                                                settings: settings.current)
        editor.onSave = { [weak self] edited in
            guard let self else { return }
            LayoutCatalog.saveEdited(edited, for: display.identity, in: self.store)
            self.closeZoneEditor()
        }
        editor.onCancel = { [weak self] in self?.closeZoneEditor() }
        zoneEditor = editor
        // FancyZones hides its main window while zones are being edited, so
        // the full-screen editor is the only thing asking for attention.
        picker?.window?.orderOut(nil)
        editor.present()
    }

    private func closeZoneEditor() {
        zoneEditor?.close()
        zoneEditor = nil
        picker?.reload()
        picker?.present()
    }

    static func displayUnderMouse() -> DisplayIdentity? {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        return screen.map(DisplayIdentity.forScreen)
    }
}
