import AppKit

/// Borderless, non-activating transparent NSPanel that displays zone outlines on a display.
///
/// CRITICAL: `ignoresMouseEvents = true` is strictly enforced so this window
/// never swallows or interferes with the window drag in flight.
public class ZoneOverlayWindow: NSPanel {
    public let overlayView: ZoneOverlayView

    public init(screen: NSScreen) {
        let contentRect = screen.frame
        self.overlayView = ZoneOverlayView(frame: NSRect(origin: .zero, size: contentRect.size))

        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        self.contentView = overlayView
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
