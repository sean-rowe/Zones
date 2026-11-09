import AppKit

/// The zone editor: a full-screen overlay on the display under the pointer.
///
/// A port of PineOS's `zone_editor.c`. The desktop is dimmed, the zones are
/// drawn over it, and a toolbar along the top offers the presets, the gap,
/// Cancel and Apply. Click splits a zone, Shift-click splits it the other
/// way, dividers drag, right-click merges, Return applies, Escape cancels.
public final class ZoneEditor {

    private let store: LayoutStore
    private let settings: Settings
    private(set) var window: ZoneEditorWindow?
    private(set) var canvas: ZoneEditorCanvas?
    private var display: DisplayIdentity?

    /// Called after Apply has saved the layout.
    public var onApply: ((DisplayIdentity, ZoneLayout) -> Void)?
    /// Called whenever the editor closes, applied or not.
    public var onClose: (() -> Void)?

    public init(store: LayoutStore = .shared, settings: Settings = .shared) {
        self.store = store
        self.settings = settings
    }

    public var isPresented: Bool { window != nil }

    /// Open on the display under the pointer.
    public func present() {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
            ?? NSScreen.main ?? NSScreen.screens.first else { return }
        present(on: screen)
    }

    /// Open on a screen. If the editor is already open it is brought forward
    /// instead, so a second shortcut press cannot discard the edit.
    public func present(on screen: NSScreen) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let identity = DisplayIdentity.forScreen(screen)
        let frame = screen.visibleFrame
        let canvas = makeCanvas(for: identity, size: frame.size)
        let window = ZoneEditorWindow(frame: frame, canvas: canvas)
        self.display = identity
        self.canvas = canvas
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        ZonesLog.info("Editor", "opened on \(identity.key) — \(canvas.tree.leafCount) zones")
    }

    /// Build the canvas without a window, for tests and offscreen renders.
    func makeCanvas(for identity: DisplayIdentity, size: CGSize) -> ZoneEditorCanvas {
        let existing = store.assignedLayout(for: identity)
        let tree = existing.map { SplitTree(zones: $0.zones.map(\.rect)) } ?? .leaf
        let canvas = ZoneEditorCanvas(frame: CGRect(origin: .zero, size: size), tree: tree,
                                      gap: settings.current.zoneGap,
                                      outerPadding: settings.current.outerPadding)
        canvas.onApply = { [weak self] in self?.apply() }
        canvas.onCancel = { [weak self] in self?.cancel() }
        self.display = identity
        self.canvas = canvas
        return canvas
    }

    /// Save the drawn zones to the display and close.
    public func apply() {
        guard let canvas, let display else { return }
        let rects = canvas.tree.zoneRects()
        let zones = rects.enumerated().map { Zone(index: $0.offset, rect: $0.element) }

        // Overwrite the display's own custom layout; never a built-in, which
        // other displays may share.
        let layout: ZoneLayout
        if let current = store.assignedLayout(for: display), current.origin == .custom {
            layout = ZoneLayout(id: current.id, name: current.name, zones: zones, origin: .custom)
        } else {
            layout = ZoneLayout(name: "Custom", zones: zones, origin: .custom)
        }
        store.save(layout)
        store.assign(layoutID: layout.id, to: display)
        let gap = canvas.gap
        settings.update { $0.zoneGap = gap }
        ZonesLog.info("Editor", "applied \(zones.count) zones, gap \(Int(gap))pt")
        close()
        onApply?(display, layout)
    }

    /// Close without saving.
    public func cancel() {
        ZonesLog.info("Editor", "cancelled")
        close()
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
        canvas = nil
        display = nil
        onClose?()
    }
}

/// Borderless, transparent, above everything but the menu bar and Dock.
final class ZoneEditorWindow: NSWindow {
    init(frame: CGRect, canvas: ZoneEditorCanvas) {
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true
        title = "Zone Editor"
        canvas.autoresizingMask = [.width, .height]
        contentView = canvas
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
