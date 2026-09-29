import AppKit
import Sparkle

/// Zones's face over Sparkle.
///
/// Deliberately inert until `start()`: the controller is created in tests and
/// on machines that never granted Accessibility, and neither of those wants a
/// background updater scheduling network checks. `start()` happens once, from
/// the real app's launch path.
public final class UpdaterService {
    /// One updater per process: the menu, the settings pane and the launch
    /// path all speak to the same Sparkle instance.
    public static let shared = UpdaterService()

    private var controller: SPUStandardUpdaterController?

    /// Seam for the real Sparkle controller. A test that must walk the full
    /// launch path stubs this to nil — Sparkle cannot run inside xctest and
    /// says so in an alert on whatever screen the tests run on.
    public lazy var makeController: () -> SPUStandardUpdaterController? = {
        SPUStandardUpdaterController(startingUpdater: true,
                                     updaterDelegate: nil,
                                     userDriverDelegate: nil)
    }

    public init() {}

    /// Whether `start()` has run — the updater exists and may schedule checks.
    public var isStarted: Bool { controller != nil }

    /// Put the one-per-process updater back to inert. Tests only: whether this
    /// has started is shared state, so a test asserting about it has to be able
    /// to set the starting position rather than inherit whatever ran first.
    public func resetForTesting() {
        controller = nil
    }

    /// Begin updating for real: schedules automatic checks per the user's
    /// stored preference and Info.plist defaults.
    public func start() {
        guard controller == nil else { return }
        controller = makeController()
    }

    /// The menu's "Check for Updates…": explicit, with UI, even when
    /// automatic checking is off.
    public func checkForUpdates() {
        start()
        controller?.checkForUpdates(nil)
    }

    /// The Settings toggle. Sparkle persists this in the app's defaults, so
    /// the choice survives relaunches without any code here.
    public var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            start()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }
}
