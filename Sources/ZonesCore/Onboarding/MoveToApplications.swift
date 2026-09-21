import AppKit
import Foundation

/// Offers to move Zones into /Applications when it is running from somewhere
/// it should not stay.
///
/// Two cases matter. Running straight off a mounted DMG means the app vanishes
/// when the disk image is ejected. App Translocation is the subtler one: macOS
/// runs a quarantined app from a randomised read-only path, which silently
/// breaks anything that writes next to the bundle — and makes Accessibility
/// grants stick to a path that will not exist next launch.
public enum MoveToApplications {

    public enum Location: Equatable {
        case alreadyInApplications
        case mountedDiskImage
        case translocated
        case elsewhere
    }

    /// Classify where the bundle is running from.
    public static func location(of bundleURL: URL = Bundle.main.bundleURL) -> Location {
        let path = bundleURL.path
        if path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/") {
            return .alreadyInApplications
        }
        if path.hasPrefix("/Volumes/") {
            return .mountedDiskImage
        }
        // Translocated bundles run from a generated mount point under
        // /private/var/folders/.../AppTranslocation/<uuid>/d/
        if path.contains("/AppTranslocation/") {
            return .translocated
        }
        return .elsewhere
    }

    /// Whether Zones should offer to move itself.
    public static func shouldOfferMove(from bundleURL: URL = Bundle.main.bundleURL) -> Bool {
        switch location(of: bundleURL) {
        case .mountedDiskImage, .translocated: return true
        case .alreadyInApplications, .elsewhere: return false
        }
    }

    /// Ask, and move if the user agrees.
    ///
    /// Declining must leave the app running exactly where it is — never quit.
    /// A user who says "no" wants to keep using the app, not lose it.
    @discardableResult
    public static func offerMoveIfNeeded(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
        guard shouldOfferMove(from: bundleURL) else { return false }

        let alert = NSAlert()
        alert.messageText = "Move Zones to Applications?"
        alert.informativeText =
            "Zones is running from a temporary location. Moving it to your Applications "
            + "folder keeps it available after you eject the disk image, and keeps the "
            + "Accessibility permission you grant it."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")

        // Zones runs as an accessory, so it is not frontmost by default and an
        // alert can open behind whatever the user is looking at.
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            ZonesLog.info("Zones", "user declined the move to /Applications")
            return false
        }
        return move(from: bundleURL)
    }

    private static func move(from bundleURL: URL) -> Bool {
        let fm = FileManager.default
        let destination = URL(fileURLWithPath: "/Applications")
            .appendingPathComponent(bundleURL.lastPathComponent)

        // Stage beside the destination, then swap. Deleting the installed copy
        // first and then copying would destroy a working installation if the
        // copy failed — leaving the user with no app at all.
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(bundleURL.lastPathComponent).incoming-\(UUID().uuidString)")

        do {
            try fm.copyItem(at: bundleURL, to: staging)
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: staging)
            } else {
                try fm.moveItem(at: staging, to: destination)
            }
            relaunch(at: destination)
            return true
        } catch {
            // Never leave the staging copy behind on failure.
            try? fm.removeItem(at: staging)
            ZonesLog.error("Zones", "move to /Applications failed: \(error)")
            reportFailure("Zones could not move itself",
                          "Drag Zones into your Applications folder manually.")
            return false
        }
    }

    /// Launch the moved copy, and only then quit this one.
    ///
    /// Terminating regardless of the result would quit the running app even
    /// when the relaunch failed, leaving the user with nothing running.
    private static func relaunch(at url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            DispatchQueue.main.async {
                guard error == nil, app != nil else {
                    ZonesLog.error("Zones", "relaunch from /Applications failed: "
                                   + String(describing: error))
                    reportFailure("Zones was moved but could not restart",
                                  "Zones is now in your Applications folder. "
                                  + "Quit this copy and open it from there.")
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }

    private static func reportFailure(_ message: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
