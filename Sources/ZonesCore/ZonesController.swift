import AppKit

/// Wires the subsystems together and owns the menu bar status item.
///
/// Mirrors Tack's TackController: one place that knows what exists and in what
/// order it starts. Subsystems are added here as the epics land — layout store,
/// drag monitor, overlays, window snapper.
public final class ZonesController {
    private let permission: AccessibilityPermission
    private let settings: Settings
    private let layouts: LayoutStore
    private let displays: DisplayObserver
    private let dragMonitor: DragMonitor
    private let overlayManager: ZoneOverlayManager
    private let snapper: WindowSnapper
    private let hotKeyManager: HotKeyManager
    private let assignmentStore: ZoneAssignmentStore
    private let windowRestorer: WindowRestorer
    private let trialManager: TrialManager
    private let licenseStore: LicenseStore
    public let updater: UpdaterService
    public let aboutWindowController: AboutWindowController
    public private(set) var statusMenu: NSMenu = NSMenu()

    private var statusItem: NSStatusItem?
    private var permissionWindow: PermissionWindowController?
    private var onboarding: OnboardingWindowController?
    private var editor: LayoutEditorWindowController?

    public init(permission: AccessibilityPermission = .shared,
                settings: Settings = .shared,
                layouts: LayoutStore = .shared,
                displays: DisplayObserver = .shared,
                dragMonitor: DragMonitor = DragMonitor(),
                overlayManager: ZoneOverlayManager = ZoneOverlayManager(),
                snapper: WindowSnapper = WindowSnapper(),
                hotKeyManager: HotKeyManager = HotKeyManager(),
                assignmentStore: ZoneAssignmentStore = .shared,
                windowRestorer: WindowRestorer? = nil,
                trialManager: TrialManager = .shared,
                licenseStore: LicenseStore = .shared,
                updater: UpdaterService = .shared,
                aboutWindowController: AboutWindowController = AboutWindowController()) {
        self.permission = permission
        self.settings = settings
        self.layouts = layouts
        self.displays = displays
        self.dragMonitor = dragMonitor
        self.overlayManager = overlayManager
        self.snapper = snapper
        self.hotKeyManager = hotKeyManager
        self.assignmentStore = assignmentStore
        self.trialManager = trialManager
        self.licenseStore = licenseStore
        self.updater = updater
        self.aboutWindowController = aboutWindowController
        self.windowRestorer = windowRestorer ?? WindowRestorer(
            assignmentStore: assignmentStore,
            settings: settings,
            layouts: layouts,
            snapper: snapper
        )
    }

    public convenience init(permission: AccessibilityPermission = .shared,
                            settings: Settings = .shared,
                            layouts: LayoutStore = .shared,
                            displays: DisplayObserver = .shared) {
        self.init(permission: permission,
                  settings: settings,
                  layouts: layouts,
                  displays: displays,
                  dragMonitor: DragMonitor(),
                  overlayManager: ZoneOverlayManager(),
                  snapper: WindowSnapper(),
                  hotKeyManager: HotKeyManager(),
                  assignmentStore: .shared)
    }

    public func start() {
        // Status item first and unconditionally.
        installStatusItem()

        // Observe permission trust changes.
        permission.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityTrustDidChange),
            name: .accessibilityTrustDidChange,
            object: nil
        )
        permission.startMonitoring()

        displays.notificationCenter.addObserver(
            self,
            selector: #selector(displayConfigurationDidSettle),
            name: .displayConfigurationDidSettle,
            object: nil
        )

        let onboarding = OnboardingWindowController()
        self.onboarding = onboarding
        onboarding.presentIfNeeded { [weak self] in
            self?.resolvePermission()
        }
    }

    private func resolvePermission() {
        DispatchQueue.main.async { [weak self] in self?.onboarding = nil }
        if permission.isTrusted {
            activateWindowManagement()
        } else {
            ZonesLog.info("Zones", "not trusted at launch; showing permission window")
            showPermissionWindow()
        }
    }

    // MARK: - Test seams

    /// The status item menu, built exactly as `start()` builds it.
    func menuForTesting() -> NSMenu {
        rebuildMenu()
        return statusMenu
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.split.3x1",
            accessibilityDescription: "Zones"
        )
        rebuildMenu()
        item.menu = statusMenu
        statusItem = item
    }

    public func rebuildMenu() {
        statusMenu.removeAllItems()
        let menu = makeMenu()
        for item in menu.items {
            menu.removeItem(item)
            statusMenu.addItem(item)
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        status.tag = Self.statusMenuItemTag
        menu.addItem(status)

        if let trialLine = trialManager.menuLine {
            let trialItem = NSMenuItem(title: trialLine, action: #selector(openCheckout), keyEquivalent: "")
            trialItem.target = self
            menu.addItem(trialItem)
        }

        menu.addItem(.separator())
        let edit = NSMenuItem(title: "Edit Layout…", action: #selector(openEditor),
                              keyEquivalent: "e")
        edit.target = self
        menu.addItem(edit)
        menu.addItem(NSMenuItem(title: "Settings…", action: nil, keyEquivalent: ","))
        menu.addItem(.separator())

        let updateItem = NSMenuItem(title: "Check for Updates…",
                                    action: #selector(checkForUpdates),
                                    keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        let aboutItem = NSMenuItem(title: "About Zones",
                                   action: #selector(showAbout),
                                   keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Zones",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        return menu
    }

    @objc public func checkForUpdates() {
        updater.checkForUpdates()
    }

    @objc public func showAbout() {
        aboutWindowController.show()
    }

    @objc private func openCheckout() {
        if let url = ZonesStoreConfig.checkoutURL {
            NSWorkspace.shared.open(url)
        }
    }

    static let statusMenuItemTag = 1001

    private var statusTitle: String {
        permission.isTrusted ? "Zones is active" : "Accessibility access needed"
    }

    private func refreshStatusMenuItem() {
        guard let item = statusItem?.menu?.item(withTag: Self.statusMenuItemTag) else { return }
        item.title = statusTitle
    }

    // MARK: - Permission

    private func showPermissionWindow() {
        let controller = PermissionWindowController(permission: permission)
        permissionWindow = controller
        controller.present()
    }

    @objc private func accessibilityTrustDidChange() {
        refreshStatusMenuItem()
        guard permission.isTrusted else {
            ZonesLog.info("Zones", "accessibility revoked; window management suspended")
            dragMonitor.stop()
            overlayManager.hide()
            hotKeyManager.stop()
            windowRestorer.stop()
            return
        }
        permissionWindow?.window?.close()
        permissionWindow = nil
        activateWindowManagement()
    }

    private func activateWindowManagement() {
        refreshStatusMenuItem()

        if layouts.installBuiltInsIfEmpty() {
            ZonesLog.info("Zones", "installed \(layouts.layouts.count) built-in layouts")
        }
        assignDefaultLayoutsToUnassignedDisplays()

        displays.start()

        setupDragHandling()
        dragMonitor.start()

        hotKeyManager.layoutProvider = { [weak self] identity in
            self?.layouts.assignedLayout(for: identity)
        }
        hotKeyManager.start()

        windowRestorer.start()

        ZonesLog.info("Zones", "accessibility granted; window management active")
    }

    private func setupDragHandling() {
        dragMonitor.onDragStarted = { [weak self] _, _ in
            guard let self = self, self.trialManager.canSnap else { return }
            let assigned = self.currentAssignedLayouts()
            self.overlayManager.show(layouts: assigned)
        }

        dragMonitor.onDragMoved = { [weak self] location, _, isActivated, isSpanHeld in
            guard let self = self else { return }
            guard self.trialManager.canSnap else {
                self.overlayManager.hide()
                return
            }
            if isActivated {
                if self.overlayManager.overlayWindows.isEmpty {
                    let assigned = self.currentAssignedLayouts()
                    self.overlayManager.show(layouts: assigned)
                }
                self.overlayManager.updateHighlight(at: location, isSpanHeld: isSpanHeld)
            } else {
                self.overlayManager.hide()
            }
        }

        dragMonitor.onDragEnded = { [weak self] window, location, shouldSnap, _ in
            guard let self = self else { return }
            guard self.trialManager.canSnap else {
                self.overlayManager.hide()
                return
            }
            if shouldSnap, let hit = self.overlayManager.lastHitResult {
                self.snapper.snap(window: window, to: hit.boundingCGFrame)
                let pointer = CoordinateConverter.cgToAppKit(location)
                if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) {
                    let identity = DisplayIdentity.forScreen(screen)
                    if let layout = self.layouts.assignedLayout(for: identity) {
                        self.assignmentStore.assign(
                            window: window,
                            display: identity,
                            layoutID: layout.id,
                            zoneIndex: hit.primaryIndex ?? 0,
                            zoneIndices: Array(hit.zoneIndices),
                            snappedRect: hit.boundingCGFrame
                        )
                    }
                }
            } else if !shouldSnap {
                self.assignmentStore.removeAssignment(for: window)
            }
            self.overlayManager.hide()
        }

        dragMonitor.onDragCancelled = { [weak self] in
            self?.overlayManager.hide()
        }
    }

    private func currentAssignedLayouts() -> [DisplayIdentity: ZoneLayout] {
        var map: [DisplayIdentity: ZoneLayout] = [:]
        for (identity, _) in DisplayObserver.currentDisplays() {
            if let layout = layouts.assignedLayout(for: identity) {
                map[identity] = layout
            }
        }
        return map
    }

    /// Give every display a layout, so a newly attached monitor is usable
    /// immediately rather than having no zones until the user opens the editor.
    private func assignDefaultLayoutsToUnassignedDisplays() {
        guard let fallback = layouts.layouts.first else { return }
        for (identity, _) in DisplayObserver.currentDisplays()
        where layouts.assignedLayout(for: identity) == nil {
            layouts.assign(layoutID: fallback.id, to: identity)
            ZonesLog.info("Zones", "assigned default layout to display \(identity.key)")
        }
    }

    @objc private func openEditor() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.screens.first
        guard let screen else { return }

        let identity = DisplayIdentity.forScreen(screen)
        let visible = screen.visibleFrame
        let controller = LayoutEditorWindowController(
            store: layouts,
            display: identity,
            targetAspectRatio: visible.height > 0 ? visible.width / visible.height : 16.0 / 9.0
        )
        editor = controller
        controller.present()
    }

    @objc private func displayConfigurationDidSettle() {
        assignDefaultLayoutsToUnassignedDisplays()
        if settings.current.flashZonesOnLayoutSwitch {
            overlayManager.flashZones(layouts: currentAssignedLayouts())
        }
    }
}
