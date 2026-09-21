import AppKit

/// Shown once, on first run, before the permission ask.
///
/// The flow comes from Tack; the words are Zones' own. It exists so the
/// Accessibility prompt arrives with context rather than as a bare system
/// dialog the user has no reason to trust.
public final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private static let hasRunKey = "com.pinyridgelabs.Zones.hasCompletedOnboarding"

    private let defaults: UserDefaults
    private var onFinish: (() -> Void)?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Zones"
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContentView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Whether onboarding still needs to run.
    public var isPending: Bool {
        !defaults.bool(forKey: Self.hasRunKey)
    }

    public func presentIfNeeded(then finish: @escaping () -> Void) {
        guard isPending else {
            finish()
            return
        }
        onFinish = finish
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeContentView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))

        let heading = NSTextField(labelWithString: "Snap windows into your own layouts")
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        heading.frame = NSRect(x: 24, y: 238, width: 432, height: 26)

        let body = NSTextField(wrappingLabelWithString:
            "Build a layout of zones for each display, then drag any window while "
            + "holding Shift. The zones light up, and dropping the window snaps it "
            + "into the one under your cursor.\n\n"
            + "Zones needs Accessibility access to move other applications' windows. "
            + "That is the only permission it asks for.")
        body.font = .systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor
        body.frame = NSRect(x: 24, y: 120, width: 432, height: 108)

        let next = NSButton(title: "Continue", target: self, action: #selector(finish))
        next.bezelStyle = .rounded
        next.keyEquivalent = "\r"
        next.frame = NSRect(x: 356, y: 24, width: 100, height: 32)

        [heading, body, next].forEach(container.addSubview)
        return container
    }

    @objc private func finish() {
        defaults.set(true, forKey: Self.hasRunKey)
        window?.close()
    }

    /// Closing the window by any route continues startup.
    ///
    /// Routing both the Continue button and the red close button through here
    /// is deliberate: an earlier version only continued from the button, so
    /// closing the window left the app running with no status item and no way
    /// to reach it.
    public func windowWillClose(_ notification: Notification) {
        let finish = onFinish
        onFinish = nil
        finish?()
    }
}
