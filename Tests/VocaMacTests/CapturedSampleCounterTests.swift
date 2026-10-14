import XCTest
import os
@testable import VocaMac

final class CapturedSampleCounterTests: XCTestCase {

    func testNothingIsCapturedBeforeTheMicrophoneIsLive() {
        let counter = CapturedSampleCounter()
        XCTAssertEqual(counter.releaseBoundary(at: 10), 0)
    }

    func testATapOfTheKeyBeforeTheFirstBufferKeepsNothing() {
        let counter = CapturedSampleCounter()
        counter.markLive(at: 10)
        XCTAssertEqual(counter.releaseBoundary(at: 10.05), 0)
    }

    func testAShortWordBeforeASlowFirstBufferIsKept() {
        // An 8 kHz headset delivers its first buffer after 512 ms; "yes" can
        // be over by then.
        let counter = CapturedSampleCounter()
        counter.markLive(at: 10)
        XCTAssertEqual(counter.releaseBoundary(at: 10.4), 6_400)
    }

    func testTheBufferStillBeingFilledIsKept() {
        let counter = CapturedSampleCounter()
        counter.record(16_000, at: 11)
        // Released 60 ms after the last delivery.
        XCTAssertEqual(counter.releaseBoundary(at: 11.06), 16_960)
        XCTAssertEqual(counter.count, 16_000)
    }

    func testAStalledTapCannotStretchTheBoundary() {
        let counter = CapturedSampleCounter()
        counter.record(16_000, at: 11)
        XCTAssertEqual(
            counter.releaseBoundary(at: 15),
            16_000 + Int(CapturedSampleCounter.maxInFlightSeconds * 16_000)
        )
    }

    func testTheInjectedClockIsUsed() {
        let now = OSAllocatedUnfairLock(initialState: 10.0)
        let counter = CapturedSampleCounter(clock: { now.withLock { $0 } })
        counter.record(16_000)
        now.withLock { $0 = 10.1 }
        XCTAssertEqual(counter.releaseBoundary(), 17_600)
    }

    func testDeliveriesNeverMoveTheCountBack() {
        let counter = CapturedSampleCounter()
        counter.record(4_000, at: 1)
        counter.record(2_000, at: 2)
        XCTAssertEqual(counter.count, 4_000)
    }
}
