import AppKit

/// Process lifecycle only. Everything else belongs to `ZonesController`.
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller: ZonesController

    public init(controller: ZonesController = ZonesController()) {
        self.controller = controller
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory: menu bar only, no Dock icon, and the app never steals focus
        // on launch. LSUIElement in Info.plist says the same for a bundled build;
        // setting it here covers `swift run` during development too.
        NSApp.setActivationPolicy(.accessory)

        // Offer the move before anything else: an Accessibility grant made from
        // a translocated path does not survive the move, so asking afterwards
        // would make the user grant it twice.
        MoveToApplications.offerMoveIfNeeded()

        controller.start()
    }
}
