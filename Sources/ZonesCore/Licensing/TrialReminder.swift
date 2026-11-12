import Foundation
import UserNotifications

/// Tells a trial user the clock is running, before it runs out.
///
/// Three moments, each delivered at most once: three days left, one day left,
/// and the day snapping stops. No repetition, no badge, nothing while the app
/// is licensed.
public enum TrialReminder {
    public static let sentKey = "ZonesTrialRemindersSent"

    public enum Moment: String, CaseIterable, Sendable {
        case threeDaysLeft = "trial-3"
        case oneDayLeft = "trial-1"
        case expired = "trial-expired"

        public var title: String {
            switch self {
            case .threeDaysLeft: return "Three days left in your Zones trial"
            case .oneDayLeft:    return "One day left in your Zones trial"
            case .expired:       return "Your Zones trial has ended"
            }
        }

        public var body: String {
            switch self {
            case .threeDaysLeft:
                return "Snapping keeps working until then. $39.99 once, for up to three Macs."
            case .oneDayLeft:
                return "After tomorrow zone snapping will stop until Zones is bought."
            case .expired:
                return "Zone snapping has stopped. Your windows are unchanged. Nothing was lost."
            }
        }
    }

    /// Which moment, if any, this state calls for. Pure, so the schedule is
    /// testable without a notification centre or a clock.
    public static func moment(for state: LicenseState) -> Moment? {
        switch state {
        case .licensed: return nil
        case .trialExpired: return .expired
        case .trial(let days):
            if days <= 1 { return .oneDayLeft }
            if days <= 3 { return .threeDaysLeft }
            return nil
        }
    }

    /// Whether this moment should be delivered now: the state calls for it and
    /// it has not been delivered before.
    public static func shouldDeliver(_ moment: Moment, alreadySent: Set<String>) -> Bool {
        !alreadySent.contains(moment.rawValue)
    }

    /// Posts one moment and reports whether it reached the user.
    public typealias Poster = (Moment, @escaping (Bool) -> Void) -> Void

    /// Check the state and post a notification if a moment has arrived and has
    /// not been delivered before. A moment counts as delivered only once it
    /// was actually posted, so one refused while notifications are off is
    /// offered again on a later check instead of being lost.
    public static func deliverIfNeeded(
        state: LicenseState,
        defaults: UserDefaults = .standard,
        post: Poster = TrialReminder.postNotification
    ) {
        guard let moment = moment(for: state) else { return }
        let sent = Set(defaults.stringArray(forKey: sentKey) ?? [])
        guard shouldDeliver(moment, alreadySent: sent) else { return }

        post(moment) { delivered in
            guard delivered else {
                ZonesLog.info("Trial", "reminder \(moment.rawValue) not delivered; will try again")
                return
            }
            var sent = Set(defaults.stringArray(forKey: sentKey) ?? [])
            sent.insert(moment.rawValue)
            defaults.set(Array(sent), forKey: sentKey)
            ZonesLog.info("Trial", "reminder \(moment.rawValue) delivered")
        }
    }

    /// The real poster: asks for permission the first time a reminder is due,
    /// never earlier, then posts it.
    public static func postNotification(_ moment: Moment, completion: @escaping (Bool) -> Void) {
        // The notification centre needs a bundle; a test runner has none.
        guard NSClassFromString("XCTestCase") == nil, Bundle.main.bundleIdentifier != nil else {
            completion(false)
            return
        }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let content = UNMutableNotificationContent()
            content.title = moment.title
            content.body = moment.body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "com.pinyridgelabs.Zones.\(moment.rawValue)",
                content: content,
                trigger: nil
            )
            center.add(request) { error in
                DispatchQueue.main.async { completion(error == nil) }
            }
        }
    }
}
