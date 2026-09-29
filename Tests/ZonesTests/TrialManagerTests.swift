import XCTest
@testable import ZonesCore

final class TrialManagerTests: XCTestCase {
    private var manager: TrialManager!
    private var defaults: UserDefaults!
    private var simulatedDate: Date!
    private var memoryKeychainDate: Date?

    override func setUp() {
        super.setUp()
        manager = TrialManager()
        defaults = UserDefaults(suiteName: "TrialManagerTests_\(UUID().uuidString)")!
        manager.defaults = defaults

        simulatedDate = Date()
        manager.now = { [weak self] in self?.simulatedDate ?? Date() }

        memoryKeychainDate = nil
        manager.readKeychainAnchor = { [weak self] in self?.memoryKeychainDate }
        manager.writeKeychainAnchor = { [weak self] date in self?.memoryKeychainDate = date }
        manager.isLicensed = { false }
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
        super.tearDown()
    }

    func testFreshInstallStartsTrialWithFullDays() {
        let state = manager.state
        XCTAssertEqual(state, .trial(daysRemaining: 14))
        XCTAssertTrue(manager.canSnap)
        XCTAssertEqual(manager.menuLine, "Trial: 14 days left")
    }

    func testAdvancingClockDecrementsTrialDays() {
        _ = manager.state // establish anchor

        // Advance clock by 5 days
        simulatedDate = simulatedDate.addingTimeInterval(5 * 86400)
        XCTAssertEqual(manager.state, .trial(daysRemaining: 9))
        XCTAssertTrue(manager.canSnap)

        // Advance to 13 days
        simulatedDate = simulatedDate.addingTimeInterval(8 * 86400)
        XCTAssertEqual(manager.state, .trial(daysRemaining: 1))
        XCTAssertEqual(manager.menuLine, "Trial ends tomorrow — Buy Zones…")
    }

    func testMovingClockBackwardsDoesNotRestoreUsedDays() {
        _ = manager.state // establish anchor

        // Advance clock by 10 days (4 days left)
        simulatedDate = simulatedDate.addingTimeInterval(10 * 86400)
        XCTAssertEqual(manager.state, .trial(daysRemaining: 4))

        // Set system clock back 5 days
        simulatedDate = simulatedDate.addingTimeInterval(-5 * 86400)
        // Days used floor prevents restoring days
        XCTAssertEqual(manager.state, .trial(daysRemaining: 4), "Setting system clock backwards must not restore spent trial days")
    }

    func testExpiredTrialBlocksSnapping() {
        _ = manager.state // establish anchor

        // Advance past 14 days
        simulatedDate = simulatedDate.addingTimeInterval(15 * 86400)
        XCTAssertEqual(manager.state, .trialExpired)
        XCTAssertFalse(manager.canSnap, "Expired trial must block snapping")
        XCTAssertEqual(manager.menuLine, "Trial expired — Buy Zones…")
    }

    func testLicenseOverridesTrialExpiry() {
        _ = manager.state
        simulatedDate = simulatedDate.addingTimeInterval(20 * 86400)
        XCTAssertEqual(manager.state, .trialExpired)

        // Become licensed
        manager.isLicensed = { true }
        XCTAssertEqual(manager.state, .licensed)
        XCTAssertTrue(manager.canSnap)
        XCTAssertNil(manager.menuLine)
    }

    func testTrialReminderMilestones() {
        XCTAssertNil(TrialReminder.moment(for: .licensed))
        XCTAssertNil(TrialReminder.moment(for: .trial(daysRemaining: 10)))
        XCTAssertEqual(TrialReminder.moment(for: .trial(daysRemaining: 3)), .threeDaysLeft)
        XCTAssertEqual(TrialReminder.moment(for: .trial(daysRemaining: 1)), .oneDayLeft)
        XCTAssertEqual(TrialReminder.moment(for: .trialExpired), .expired)

        // Dedup delivery
        var sent: Set<String> = []
        XCTAssertTrue(TrialReminder.shouldDeliver(.threeDaysLeft, alreadySent: sent))
        sent.insert(TrialReminder.Moment.threeDaysLeft.rawValue)
        XCTAssertFalse(TrialReminder.shouldDeliver(.threeDaysLeft, alreadySent: sent))
    }
}
