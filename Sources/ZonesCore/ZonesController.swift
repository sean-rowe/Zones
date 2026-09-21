import AppKit

/// Wires the subsystems together and owns the menu bar status item.
///
/// Mirrors Tack's TackController: one place that knows what exists and in what
/// order it starts. Subsystems are added here as the epics land — layout store,
/// drag monitor, overlays, hotkeys — so the wiring stays visible in one file
/// rather than spreading across the app delegate.
public final class ZonesController {
    private let permission: AccessibilityPermission
    private let settings: Settings
    private var statusItem: NSStatusItem?
    private var permissionWindow: PermissionWindowController?
    private var onboarding: OnboardingWindowController?

    public init(permission: AccessibilityPermission = .shared,
                settings: Settings = .shared) {
        self.permission = permission
        self.settings = settings
    }

    public func start() {
        // Status item first and unconditionally. Whatever else happens during
        // startup, the user must have a way to reach the app.
        installStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityTrustDidChange),
            name: .accessibilityTrustDidChange,
            object: nil
        )
        permission.startMonitoring()

        let onboarding = OnboardingWindowController()
        self.onboarding = onboarding
        onboarding.presentIfNeeded { [weak self] in
            self?.resolvePermission()
        }
    }

    private func resolvePermission() {
        onboarding = nil
        if permission.isTrusted {
            activateWindowManagement()
        } else {
            ZonesLog.info("Zones", "not trusted at launch; showing permission window")
            showPermissionWindow()
        }
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.split.3x1",
            accessibilityDescription: "Zones"
        )
        item.menu = makeMenu()
        statusItem = item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        status.tag = Self.statusMenuItemTag
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Edit Layouts…", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: nil, keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Zones",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        return menu
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
            return
        }
        // Granting while running must not require a relaunch: close the nag and
        // bring the app up as though it had launched trusted.
        permissionWindow?.window?.close()
        permissionWindow = nil
        activateWindowManagement()
    }

    private func activateWindowManagement() {
        refreshStatusMenuItem()
        ZonesLog.info("Zones", "accessibility granted; window management active")
        // Layout store, drag monitor, overlays and hotkeys attach here as the
        // later epics land.
    }
}
