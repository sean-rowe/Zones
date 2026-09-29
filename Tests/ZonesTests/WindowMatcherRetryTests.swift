import XCTest
import ApplicationServices
@testable import ZonesCore

final class WindowMatcherRetryTests: XCTestCase {
    private var matcher: WindowMatcher!
    private var savedAttempts: Int!
    private var savedPause: (() -> Void)!
    private var pauses = 0

    private let info = WindowInfo(windowID: 10571, ownerPID: 501, ownerName: "Terminal",
                                  windowTitle: "zsh", bounds: .zero,
                                  bundleIdentifier: "com.apple.Terminal",
                                  layer: 0, isOnScreen: true)

    override func setUp() {
        super.setUp()
        matcher = WindowMatcher()
        savedAttempts = WindowMatcher.resolveAttempts
        savedPause = WindowMatcher.resolvePause
        pauses = 0
        WindowMatcher.resolvePause = { [weak self] in self?.pauses += 1 }
    }

    override func tearDown() {
        WindowMatcher.resolveAttempts = savedAttempts
        WindowMatcher.resolvePause = savedPause
        super.tearDown()
    }

    func testAWindowFoundFirstTimeIsNotWaitedFor() {
        var asks = 0
        matcher.resolveOnceForTesting = { _ in
            asks += 1
            return AXUIElementCreateSystemWide()
        }
        XCTAssertNotNil(matcher.findAXElement(for: info))
        XCTAssertEqual(asks, 1, "a window that is there is not asked for twice")
        XCTAssertEqual(pauses, 0, "nothing should have waited")
    }

    func testAWindowThatArrivesLateIsStillFound() {
        WindowMatcher.resolveAttempts = 4
        var asks = 0
        matcher.resolveOnceForTesting = { _ in
            asks += 1
            return asks >= 3 ? AXUIElementCreateSystemWide() : nil
        }
        XCTAssertNotNil(matcher.findAXElement(for: info),
                        "the window turned up on the third ask")
        XCTAssertEqual(asks, 3)
    }

    func testAWindowThatNeverArrivesIsGivenUpOn() {
        WindowMatcher.resolveAttempts = 4
        var asks = 0
        matcher.resolveOnceForTesting = { _ in
            asks += 1
            return nil
        }
        XCTAssertNil(matcher.findAXElement(for: info))
        XCTAssertEqual(asks, 4, "asked its budget of times and no more")
    }

    func testTheLastAskIsNotFollowedByAWait() {
        WindowMatcher.resolveAttempts = 4
        matcher.resolveOnceForTesting = { _ in nil }
        _ = matcher.findAXElement(for: info)
        XCTAssertEqual(pauses, 3, "three waits between four asks")
    }

    func testTheWindowIsAlwaysAskedForAtLeastOnce() {
        WindowMatcher.resolveAttempts = 0
        var asks = 0
        matcher.resolveOnceForTesting = { _ in
            asks += 1
            return AXUIElementCreateSystemWide()
        }
        XCTAssertNotNil(matcher.findAXElement(for: info))
        XCTAssertEqual(asks, 1)
    }
}
