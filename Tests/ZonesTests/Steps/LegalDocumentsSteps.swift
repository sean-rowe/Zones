import XCTest
import AppKit
@testable import ZonesCore

/// Steps for legal_documents.
class LegalDocumentsSteps {
    private var controller: ZonesController!
    private var about: AboutWindowController!
    private var openedURLs: [URL] = []
    private var version: (short: String, build: String) = ("1.0.0", "1")

    func tearDown() {
        about?.window?.orderOut(nil)
        about = nil
        controller = nil
        openedURLs = []
        version = ("1.0.0", "1")
    }

    deinit { tearDown() }

    func register(in registry: StepRegistry) {
        registry.given("the status menu is rebuilt") { [self] _ in
            controller = ZonesController()
            controller.rebuildMenu()
        }

        registry.then("it offers an About Zones item") { [self] _ in
            let titles = controller.statusMenu.items.map(\.title)
            XCTAssertTrue(titles.contains("About Zones"),
                          "the status menu is the only menu Zones has, so it is the only "
                          + "place About can be reached from; got \(titles)")
        }

        registry.given("a build reporting version (.+) build (.+)") { [self] args in
            version = (args[0], args[1])
        }

        registry.given("the about card is shown") { [self] _ in
            about = AboutWindowController()
            about.versionProvider = { [self] in version }
            about.openURLHandler = { [weak self] url in self?.openedURLs.append(url) }
            about.show()
            XCTAssertNotNil(about.window, "showing the card should create its window")
        }

        registry.then("it offers the license agreement, privacy policy, terms of purchase "
                      + "and acknowledgements") { [self] _ in
            let offered = Set(about.documents)
            XCTAssertEqual(offered, Set(LegalDocument.allCases),
                           "a document Zones is used under that the card does not offer is a "
                           + "document nobody can read from inside Zones")
            let identifiers = buttonIdentifiers()
            XCTAssertEqual(Set(identifiers), Set(LegalDocument.allCases.map(\.rawValue)),
                           "every document needs its own button, got \(identifiers)")
        }

        registry.then("the card reads \"(.+)\"") { [self] args in
            XCTAssertEqual(about.versionLine, args[0])
            let labels = allSubviews(of: about.window!.contentView!)
                .compactMap { ($0 as? NSTextField)?.stringValue }
            XCTAssertTrue(labels.contains(args[0]),
                          "the card should say which copy this is, got \(labels)")
        }

        registry.then("no button sits closer than (\\d+) points to the card's edge") { [self] args in
            let clearance = CGFloat(Double(args[0])!)
            let content = about.window!.contentView!
            for button in allSubviews(of: content).compactMap({ $0 as? NSButton }) {
                let frame = button.convert(button.bounds, to: content)
                XCTAssertGreaterThanOrEqual(frame.minX, clearance,
                                            "'\(button.title)' is \(frame.minX)pt from the left edge")
                XCTAssertGreaterThanOrEqual(content.bounds.maxX - frame.maxX, clearance,
                                            "'\(button.title)' is \(content.bounds.maxX - frame.maxX)pt "
                                            + "from the right edge")
            }
        }

        registry.then("every button is the same width") { [self] _ in
            let widths = Set(allSubviews(of: about.window!.contentView!)
                .compactMap { ($0 as? NSButton)?.frame.width })
            XCTAssertEqual(widths.count, 1,
                           "buttons stacked two deep have to line up, got \(widths.sorted())")
        }

        registry.when("the license agreement is chosen") { [self] _ in
            let button = allSubviews(of: about.window!.contentView!)
                .compactMap { $0 as? NSButton }
                .first { $0.identifier?.rawValue == LegalDocument.license.rawValue }
            guard let button = button else {
                return XCTFail("no button for the license agreement")
            }
            about.openDocument(button)
        }

        registry.then("(.+) is opened") { [self] args in
            XCTAssertEqual(openedURLs.map(\.absoluteString), [args[0]])
        }
    }

    private func buttonIdentifiers() -> [String] {
        allSubviews(of: about.window!.contentView!)
            .compactMap { ($0 as? NSButton)?.identifier?.rawValue }
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { allSubviews(of: $0) }
    }
}
