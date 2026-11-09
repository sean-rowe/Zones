import AppKit

/// A filled accent button for the one primary action on a surface —
/// "Create new layout", "Merge zones" — as FancyZones fills its own.
///
/// Drawn rather than relying on `bezelColor`, which AppKit only honours while
/// the window is key: the merge button appears on a fresh overlay, and a
/// primary action that turns grey whenever focus wanders reads as disabled.
final class AccentButton: NSButton {

    private let symbolName: String?

    init(title: String, symbolName: String?, target: AnyObject?, action: Selector?) {
        self.symbolName = symbolName
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryPushIn)
        font = .systemFont(ofSize: 13, weight: .medium)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var symbol: NSImage? {
        guard let symbolName,
              let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return nil
        }
        return image.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
    }

    private var label: NSAttributedString {
        NSAttributedString(string: title, attributes: [
            .font: font ?? .systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
    }

    override var intrinsicContentSize: NSSize {
        let text = label.size()
        let imageWidth = symbol.map { $0.size.width + 6 } ?? 0
        return NSSize(width: ceil(text.width + imageWidth + 32), height: 32)
    }

    override func draw(_ dirtyRect: CGRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
        var fill = NSColor.controlAccentColor
        if isHighlighted { fill = fill.blended(withFraction: 0.18, of: .black) ?? fill }
        if !isEnabled { fill = fill.withAlphaComponent(0.4) }
        fill.setFill()
        path.fill()

        let text = label
        let textSize = text.size()
        let image = symbol
        let imageWidth = image.map { $0.size.width + 6 } ?? 0
        var x = bounds.midX - (textSize.width + imageWidth) / 2
        if let image {
            // Symbols are templates; tint to match the white title.
            let tinted = NSImage(size: image.size, flipped: false) { rect in
                image.draw(in: rect)
                NSColor.white.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: CGRect(x: x, y: bounds.midY - image.size.height / 2,
                                   width: image.size.width, height: image.size.height))
            x += imageWidth
        }
        text.draw(at: CGPoint(x: x, y: bounds.midY - textSize.height / 2))
    }
}
