import AppKit

/// Explains why Zones needs Accessibility and sends the user to the pane.
///
/// Zones asks for exactly one permission. Tack also needs Screen Recording for
/// its tab-hover thumbnails; Zones has no equivalent surface, so this window is
/// the whole permission story and can afford to be clear rather than terse.
public final class PermissionWindowController: NSWindowController {
    private let permission: AccessibilityPermission

    public init(permission: AccessibilityPermission = .shared) {
        self.permission = permission
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Zones needs Accessibility"
        window.center()
        super.init(window: window)
        window.contentView = makeContentView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeContentView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 260))

        let heading = NSTextField(labelWithString: "Zones needs Accessibility access")
        heading.font = .systemFont(ofSize: 16, weight: .semibold)
        heading.frame = NSRect(x: 24, y: 196, width: 412, height: 24)

        let body = NSTextField(wrappingLabelWithString:
            "Zones moves and resizes the windows of other applications when you drop "
            + "them into a zone. macOS only allows that with Accessibility access.\n\n"
            + "Zones asks for no other permission. It does not record your screen and "
            + "does not read window contents.")
        body.font = .systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor
        body.frame = NSRect(x: 24, y: 92, width: 412, height: 96)

        let open = NSButton(title: "Open System Settings", target: self,
                            action: #selector(openSettings))
        open.bezelStyle = .rounded
        open.keyEquivalent = "\r"
        open.frame = NSRect(x: 254, y: 24, width: 182, height: 32)

        let later = NSButton(title: "Later", target: self, action: #selector(dismiss(_:)))
        later.bezelStyle = .rounded
        later.frame = NSRect(x: 166, y: 24, width: 80, height: 32)

        [heading, body, open, later].forEach(container.addSubview)
        return container
    }

    @objc private func openSettings() {
        // Prompt first: on a first run this is the dialog that actually adds
        // Zones to the Accessibility list, so the pane has a row to toggle.
        permission.requestTrust()
        permission.openSystemSettings()
    }

    @objc private func dismiss(_ sender: Any?) {
        window?.close()
    }
}
