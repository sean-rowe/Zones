import XCTest
@testable import ZonesCore

final class DisplayObserverTests: XCTestCase {

    func testABurstOfChangesReportsOnce() {
        let source = NotificationCenter()
        let sink = NotificationCenter()
        let observer = DisplayObserver(sourceCenter: source, notificationCenter: sink,
                                       settleInterval: 0.05)
        var settled = 0
        let token = sink.addObserver(forName: .displayConfigurationDidSettle,
                                     object: nil, queue: nil) { _ in settled += 1 }
        defer { sink.removeObserver(token) }

        // Plugging in one monitor can produce several notifications in a row.
        for _ in 0..<5 { observer.screenParametersChanged() }

        let expectation = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(settled, 1, "a burst of changes must coalesce into one report")
    }

    func testSeparatedChangesReportSeparately() {
        let source = NotificationCenter()
        let sink = NotificationCenter()
        let observer = DisplayObserver(sourceCenter: source, notificationCenter: sink,
                                       settleInterval: 0.05)
        var settled = 0
        let token = sink.addObserver(forName: .displayConfigurationDidSettle,
                                     object: nil, queue: nil) { _ in settled += 1 }
        defer { sink.removeObserver(token) }

        observer.screenParametersChanged()
        let first = expectation(description: "first")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { first.fulfill() }
        wait(for: [first], timeout: 2)

        observer.screenParametersChanged()
        let second = expectation(description: "second")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { second.fulfill() }
        wait(for: [second], timeout: 2)

        XCTAssertEqual(settled, 2)
    }

    func testStopCancelsAPendingReport() {
        let source = NotificationCenter()
        let sink = NotificationCenter()
        let observer = DisplayObserver(sourceCenter: source, notificationCenter: sink,
                                       settleInterval: 0.05)
        var settled = 0
        let token = sink.addObserver(forName: .displayConfigurationDidSettle,
                                     object: nil, queue: nil) { _ in settled += 1 }
        defer { sink.removeObserver(token) }

        observer.screenParametersChanged()
        observer.stop()

        let expectation = expectation(description: "waited")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(settled, 0, "stop() must cancel work already scheduled")
    }
}
