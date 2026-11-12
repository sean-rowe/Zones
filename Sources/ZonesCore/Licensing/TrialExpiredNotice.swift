import AppKit

/// Says why nothing is happening when an expired trial blocks a drag.
///
/// Without it the only symptom is a drag that shows no zones and snaps
/// nowhere. A small banner appears at the top of the display under the
/// pointer, at most once per drag, and takes no clicks or focus.
public final class TrialExpiredNotice {
    public static let title = "Your Zones trial has ended"
    public static let detail = "Zone snapping is off. Choose Buy Zones… from the menu bar icon to turn it back on."

    /// How long the banner stays up.
    public var displayDuration: TimeInterval = 4

    /// Seam: tests count presentations instead of putting a window on screen.
    public lazy var present: (CGPoint) -> Void = { [weak self] location in
        self?.showBanner(near: location)
    }

    private var shownThisDrag = false
    private(set) var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    public init() {}

    /// A new drag may show the banner again.
    public func dragBegan() {
        shownThisDrag = false
    }

    /// Called for every blocked drag event. Shows the banner the first time
    /// the user asks for zones during this drag. `location` is in CG
    /// coordinates. Returns whether the banner was shown by this call.
    @discardableResult
    public func dragBlocked(isActivated: Bool, at location: CGPoint) -> Bool {
        guard isActivated, !shownThisDrag else { return false }
        shownThisDrag = true
        ZonesLog.info("Trial", "drag blocked: trial expired and no license")
        present(location)
        return true
    }

    public func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Banner

    private func showBanner(near cgLocation: CGPoint) {
        hide()
        let pointer = CoordinateConverter.cgToAppKit(cgLocation)
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
            ?? NSScreen.screens.first else { return }

        let titleLabel = NSTextField(labelWithString: Self.title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white
        let detailLabel = NSTextField(labelWithString: Self.detail)
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = NSColor.white.withAlphaComponent(0.85)

        // Laid out by hand: the labels' own sizes decide the banner's, so a
        // long line can never be squeezed or clipped.
        let inset = CGSize(width: 22, height: 14)
        let spacing: CGFloat = 4
        let titleSize = titleLabel.intrinsicContentSize
        let detailSize = detailLabel.intrinsicContentSize
        let size = CGSize(width: ceil(max(titleSize.width, detailSize.width)) + inset.width * 2,
                          height: ceil(titleSize.height + spacing + detailSize.height) + inset.height * 2)
        detailLabel.frame = CGRect(x: (size.width - detailSize.width) / 2, y: inset.height,
                                   width: detailSize.width, height: detailSize.height)
        titleLabel.frame = CGRect(x: (size.width - titleSize.width) / 2,
                                  y: inset.height + detailSize.height + spacing,
                                  width: titleSize.width, height: titleSize.height)

        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        background.appearance = NSAppearance(named: .darkAqua)
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        background.addSubview(titleLabel)
        background.addSubview(detailLabel)

        let visible = screen.visibleFrame
        let frame = NSRect(x: visible.midX - size.width / 2,
                           y: visible.maxY - size.height - 48,
                           width: size.width, height: size.height)

        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = background
        panel.orderFrontRegardless()
        self.panel = panel

        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration, execute: work)
    }
}
