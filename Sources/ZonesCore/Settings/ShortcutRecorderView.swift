import AppKit

public extension Notification.Name {
    /// Posted to suspend the hot key tap while a shortcut is being recorded.
    static let hotKeyInterceptionChanged = Notification.Name("Zones.hotKeyInterceptionChanged")
}

/// A clickable field that records a keyboard shortcut (key combo) and warns on shadowed chords.
public class ShortcutRecorderView: NSView {
    public var keyCombo: KeyCombo = .empty {
        didSet { needsDisplay = true }
    }
    public var onKeyComboChanged: ((KeyCombo) -> Void)?
    public var onShadowingWarning: ((String) -> Void)?

    private var isRecording = false
    private var localMonitor: Any?
    private var windowObserver: NSObjectProtocol?

    public override var intrinsicContentSize: NSSize { NSSize(width: 140, height: 24) }
    public override var acceptsFirstResponder: Bool { true }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 4
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    public override func draw(_ dirtyRect: NSRect) {
        let bg: NSColor = isRecording ? .controlAccentColor.withAlphaComponent(0.15) : .controlBackgroundColor
        bg.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()

        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).stroke()

        let text = isRecording ? "Type shortcut..." : keyCombo.displayString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor,
        ]
        let str = text as NSString
        let size = str.size(withAttributes: attrs)
        let point = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        str.draw(at: point, withAttributes: attrs)
    }

    public override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    public func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        needsDisplay = true
        window?.makeFirstResponder(self)

        setHotKeyInterception(suspended: true)

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return nil
        }

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            self?.stopRecording()
        }
    }

    public func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        needsDisplay = true
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let o = windowObserver { NotificationCenter.default.removeObserver(o); windowObserver = nil }
        setHotKeyInterception(suspended: false)
    }

    private func setHotKeyInterception(suspended: Bool) {
        NotificationCenter.default.post(
            name: .hotKeyInterceptionChanged,
            object: self,
            userInfo: ["suspended": suspended]
        )
    }

    public override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        stopRecording()
    }

    public func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == 53 { // Escape
            stopRecording()
            return
        }

        if event.keyCode == 51 { // Delete/Backspace — clear
            keyCombo = .empty
            onKeyComboChanged?(.empty)
            stopRecording()
            return
        }

        let modMask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        let mods = event.modifierFlags.intersection(modMask)
        guard !mods.isEmpty else { return }

        let combo = KeyCombo(keyCode: event.keyCode, modifierFlags: mods.rawValue)
        if let warning = KeyCombo.shadowingWarning(for: combo) {
            onShadowingWarning?(warning)
        }

        keyCombo = combo
        onKeyComboChanged?(combo)
        stopRecording()
    }

    deinit {
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        if let o = windowObserver { NotificationCenter.default.removeObserver(o) }
        if isRecording { setHotKeyInterception(suspended: false) }
    }
}
