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

    func testDevelopmentBuildIsNeverBlockedByAnExpiredTrial() {
        _ = manager.state // establish anchor
        simulatedDate = Calendar.current.date(byAdding: .day, value: 44, to: simulatedDate)!
        XCTAssertFalse(manager.canSnap)

        manager.isDevelopmentBuild = { true }
        XCTAssertEqual(manager.state, .licensed)
        XCTAssertTrue(manager.canSnap)
        XCTAssertNil(manager.menuLine)
    }

    func testTestsRunWithTheTrialClockEnforced() {
        XCTAssertFalse(TrialManager().isDevelopmentBuild())
    }

    func testExpiredNoticeShowsOncePerDragAndOnlyWhenZonesAreAskedFor() {
        let notice = TrialExpiredNotice()
        var shown = 0
        notice.present = { _ in shown += 1 }

        notice.dragBegan()
        XCTAssertFalse(notice.dragBlocked(isActivated: false, at: .zero))
        XCTAssertEqual(shown, 0, "a plain drag is not a request for zones")

        XCTAssertTrue(notice.dragBlocked(isActivated: true, at: .zero))
        XCTAssertFalse(notice.dragBlocked(isActivated: true, at: .zero))
        XCTAssertEqual(shown, 1)

        notice.dragBegan()
        XCTAssertTrue(notice.dragBlocked(isActivated: true, at: .zero))
        XCTAssertEqual(shown, 2)
    }

    /// Opt-in: puts the real banner on the main display for a moment.
    func testExpiredNoticeBannerOnARealScreen() throws {
        guard let dir = ProcessInfo.processInfo.environment["ZONES_NOTICE_SNAPSHOT_DIR"] else {
            throw XCTSkip("set ZONES_NOTICE_SNAPSHOT_DIR to render the banner")
        }
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let notice = TrialExpiredNotice()
        notice.displayDuration = 0.5
        notice.dragBegan()
        let cgPoint = CGPoint(x: screen.frame.midX, y: screen.frame.height / 2)
        XCTAssertTrue(notice.dragBlocked(isActivated: true, at: cgPoint))

        let panel = try XCTUnwrap(notice.panel)
        XCTAssertTrue(screen.visibleFrame.contains(panel.frame))
        XCTAssertTrue(panel.ignoresMouseEvents)

        let view = try XCTUnwrap(panel.contentView)
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("trial-expired-notice.png"))

        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        XCTAssertNil(notice.panel, "the banner dismisses itself")
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
