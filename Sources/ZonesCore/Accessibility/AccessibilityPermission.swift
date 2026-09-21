import ApplicationServices
import AppKit
import Foundation

public extension Notification.Name {
    /// Posted when Accessibility trust flips, in either direction, while the
    /// app is already running.
    static let accessibilityTrustDidChange =
        Notification.Name("com.pinyridgelabs.Zones.accessibilityTrustDidChange")
}

/// Accessibility trust: checking it, asking for it, and noticing it arrive.
///
/// The silent check and the prompting check are deliberately separate calls.
/// `AXIsProcessTrustedWithOptions` with the prompt option shows a system dialog
/// every time it is called, so polling with it would pester the user once a
/// second forever. Poll with `AXIsProcessTrusted`; prompt only on an explicit
/// user action.
public final class AccessibilityPermission {
    public static let shared = AccessibilityPermission()

    private var timer: Timer?
    private var lastKnownTrust: Bool
    /// Exposed so collaborators observe the same center this instance posts on.
    /// Defaulting them to `.default` independently meant an injected test center
    /// was posted to while the observer listened elsewhere, and nothing fired.
    public let notificationCenter: NotificationCenter
    private let trustProvider: () -> Bool

    /// - Parameter trustProvider: injectable so tests can drive trust flipping
    ///   without the machine's real Accessibility state, which no test can set.
    public init(notificationCenter: NotificationCenter = .default,
                trustProvider: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.notificationCenter = notificationCenter
        self.trustProvider = trustProvider
        self.lastKnownTrust = trustProvider()
    }

    /// Whether the process is trusted right now. Never prompts.
    public var isTrusted: Bool {
        trustProvider()
    }

    /// Ask macOS to show the "grant accessibility" dialog. Prompts every call,
    /// so only ever call this from a user action.
    @discardableResult
    public func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Open the Accessibility pane in System Settings directly.
    public func openSystemSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Begin watching for trust changes.
    ///
    /// macOS posts no notification when Accessibility is granted, so polling is
    /// the only option. This is what lets a user grant permission and have Zones
    /// start working without a relaunch.
    public func startMonitoring(interval: TimeInterval = 1.0) {
        guard timer == nil else { return }
        // Built unscheduled, then added once in .common mode. `scheduledTimer`
        // would have registered it in .default as well, leaving two
        // registrations for one timer.
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkForChange()
        }
        // .common keeps it firing while menus are open or a window is dragged.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// Exposed for tests; called by the timer in normal use.
    public func checkForChange() {
        let trusted = trustProvider()
        guard trusted != lastKnownTrust else { return }
        lastKnownTrust = trusted
        ZonesLog.info("Zones", "accessibility trust changed to \(trusted)")
        notificationCenter.post(name: .accessibilityTrustDidChange, object: nil)
    }

    deinit {
        timer?.invalidate()
    }
}
