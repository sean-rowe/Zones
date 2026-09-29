import AppKit

/// The documents Zones is sold and used under.
///
/// Held here rather than as loose strings at each call site so there is one
/// answer to "what has the buyer agreed to, and where does it live" — the
/// About card lists these, and anything else that needs to point at them
/// points at the same list.
///
/// They live on the website rather than inside the bundle: a licence agreement
/// that can only be corrected by shipping a new build is one that stays wrong
/// in every copy already installed.
public enum LegalDocument: String, CaseIterable {
    case license
    case privacy
    case terms
    case acknowledgements

    /// What the button says.
    public var title: String {
        switch self {
        case .license: return "License Agreement"
        case .privacy: return "Privacy Policy"
        case .terms: return "Terms of Purchase"
        case .acknowledgements: return "Acknowledgements"
        }
    }

    /// The canonical host, which is zones.pinyridgelabs.com
    public var url: URL {
        let path: String
        switch self {
        case .license: path = "eula"
        case .privacy: path = "privacy"
        case .terms: path = "terms"
        case .acknowledgements: path = "acknowledgements"
        }
        return URL(string: "https://zones.pinyridgelabs.com/\(path)/")!
    }
}

/// The About card: what this copy of Zones is, who made it, and every document
/// it is used under.
///
/// A menu bar app has no application menu of its own, so there was nowhere at
/// all for a version number or a licence agreement to live — the status menu
/// went from "Check for Updates…" straight to Help. Someone asked to agree to
/// terms at purchase should be able to read them again afterwards without
/// going looking for the website.
public final class AboutWindowController: NSObject {
    internal private(set) var window: NSWindow?

    /// Seam: production opens the URL; a test records it.
    public var openURLHandler: (URL) -> Void = { NSWorkspace.shared.open($0) }

    /// Seam: the bundle answers in a built app, and answers nothing in a test
    /// binary, where the version would otherwise read as "dev".
    public var versionProvider: () -> (short: String, build: String) = {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleShortVersionString"] as? String ?? "dev",
                info?["CFBundleVersion"] as? String ?? "0")
    }

    /// Every document the card offers, in the order it offers them.
    public var documents: [LegalDocument] { LegalDocument.allCases }

    /// What the card says this copy is.
    public var versionLine: String {
        let version = versionProvider()
        return "Version \(version.short) (\(version.build))"
    }

    public static let copyrightLine = "© 2026 Pinyridge Labs"

    /// How far the card's contents sit from its edges.
    public static let padding = (top: CGFloat(24), left: CGFloat(24),
                                 bottom: CGFloat(20), right: CGFloat(24))
    public static let buttonSpacing: CGFloat = 10

    public override init() {
        super.init()
    }

    public func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp?.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Zones"
        window.isReleasedWhenClosed = false

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 6
        content.translatesAutoresizingMaskIntoConstraints = false

        if let icon = NSApp?.applicationIconImage {
            let well = NSImageView(image: icon)
            well.imageScaling = .scaleProportionallyUpOrDown
            well.widthAnchor.constraint(equalToConstant: 72).isActive = true
            well.heightAnchor.constraint(equalToConstant: 72).isActive = true
            content.addArrangedSubview(well)
            content.setCustomSpacing(12, after: well)
        }

        let name = NSTextField(labelWithString: "Zones")
        name.font = .systemFont(ofSize: 17, weight: .semibold)
        content.addArrangedSubview(name)

        let version = NSTextField(labelWithString: versionLine)
        version.font = .systemFont(ofSize: 11)
        version.textColor = .secondaryLabelColor
        content.addArrangedSubview(version)

        let tagline = NSTextField(labelWithString: "FancyZones for macOS — arrange your windows into tailored zones.")
        tagline.font = .systemFont(ofSize: 12)
        tagline.textColor = .secondaryLabelColor
        content.addArrangedSubview(tagline)
        content.setCustomSpacing(16, after: tagline)

        // Two rows of two, so four documents do not make one long line that
        // pushes the card wider than the icon needs it to be.
        var buttons: [NSButton] = []
        for pair in stride(from: 0, to: documents.count, by: 2).map({
            Array(documents[$0..<min($0 + 2, documents.count)])
        }) {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = Self.buttonSpacing
            for document in pair {
                let button = NSButton(title: document.title, target: self,
                                      action: #selector(openDocument(_:)))
                button.bezelStyle = .rounded
                button.font = .systemFont(ofSize: 11)
                button.identifier = NSUserInterfaceItemIdentifier(document.rawValue)
                row.addArrangedSubview(button)
                buttons.append(button)
            }
            content.addArrangedSubview(row)
        }
        let widest = buttons.map(\.fittingSize.width).max() ?? 0
        for button in buttons {
            button.widthAnchor.constraint(equalToConstant: widest).isActive = true
        }

        let copyright = NSTextField(labelWithString: Self.copyrightLine)
        copyright.font = .systemFont(ofSize: 10)
        copyright.textColor = .tertiaryLabelColor
        content.addArrangedSubview(copyright)
        if content.arrangedSubviews.count >= 2 {
            content.setCustomSpacing(14, after: content.arrangedSubviews[content.arrangedSubviews.count - 2])
        }

        let container = NSView()
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor,
                                         constant: Self.padding.top),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                             constant: Self.padding.left),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor,
                                              constant: -Self.padding.right),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor,
                                            constant: -Self.padding.bottom),
        ])

        window.contentView = container
        let fits = content.fittingSize
        window.setContentSize(NSSize(width: fits.width + Self.padding.left + Self.padding.right,
                                     height: fits.height + Self.padding.top + Self.padding.bottom))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp?.activate(ignoringOtherApps: true)
        self.window = window
    }

    @objc public func openDocument(_ sender: Any?) {
        guard let identifier = (sender as? NSButton)?.identifier?.rawValue,
              let document = LegalDocument(rawValue: identifier) else { return }
        open(document)
    }

    public func open(_ document: LegalDocument) {
        openURLHandler(document.url)
    }
}
