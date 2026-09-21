import AppKit
import Foundation

public extension Notification.Name {
    /// Posted after the display configuration has settled.
    static let displayConfigurationDidSettle =
        Notification.Name("com.pinyridgelabs.Zones.displayConfigurationDidSettle")
}

/// Watches for display changes and reports them once they have settled.
///
/// `didChangeScreenParametersNotification` fires repeatedly through a single
/// reconfiguration — plugging in one monitor can produce a burst of them as
/// macOS works out arrangement, resolution and scaling. Acting on each would
/// mean resolving zones against geometry that is still moving, so the burst is
/// coalesced and reported once at the end.
public final class DisplayObserver {
    public static let shared = DisplayObserver()

    /// How long the configuration must be quiet before it counts as settled.
    public static let settleInterval: TimeInterval = 0.5

    private let notificationCenter: NotificationCenter
    private let sourceCenter: NotificationCenter
    private let settleInterval: TimeInterval
    private var observer: NSObjectProtocol?
    private var settleWorkItem: DispatchWorkItem?

    /// - Parameters:
    ///   - sourceCenter: where screen-parameter notifications arrive.
    ///   - notificationCenter: where the settled notification is posted.
    ///     Separate so tests can drive one and observe the other.
    public init(sourceCenter: NotificationCenter = .default,
                notificationCenter: NotificationCenter = .default,
                settleInterval: TimeInterval = DisplayObserver.settleInterval) {
        self.sourceCenter = sourceCenter
        self.notificationCenter = notificationCenter
        self.settleInterval = settleInterval
    }

    public func start() {
        guard observer == nil else { return }
        observer = sourceCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.screenParametersChanged()
        }
    }

    public func stop() {
        if let observer { sourceCenter.removeObserver(observer) }
        observer = nil
        settleWorkItem?.cancel()
        settleWorkItem = nil
    }

    /// Exposed for tests; the observer calls it in normal use.
    public func screenParametersChanged() {
        // Each change restarts the clock, so a burst produces one report.
        settleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.settleWorkItem = nil
            ZonesLog.info("Zones", "display configuration settled: "
                          + "\(NSScreen.screens.count) screen(s)")
            self.notificationCenter.post(name: .displayConfigurationDidSettle, object: nil)
        }
        settleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settleInterval, execute: work)
    }

    /// Current screens paired with their durable identities.
    public static func currentDisplays() -> [(identity: DisplayIdentity, screen: NSScreen)] {
        NSScreen.screens.map { (DisplayIdentity.forScreen($0), $0) }
    }

    deinit {
        if let observer { sourceCenter.removeObserver(observer) }
        settleWorkItem?.cancel()
    }
}
