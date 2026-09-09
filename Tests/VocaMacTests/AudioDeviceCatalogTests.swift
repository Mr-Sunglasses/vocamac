import XCTest
@testable import VocaMac

@MainActor
final class AudioDeviceCatalogTests: XCTestCase {
    func testSlowDriverDoesNotBlockMainActorAndCachedVisitsDoNotRescan() async {
        let started = expectation(description: "Background enumeration started")
        started.assertForOverFulfill = true
        let gate = DispatchSemaphore(value: 0)
        let device = AudioDevice(id: "test", name: "Test", isDefault: true,
                                 sampleRate: 48000, channelCount: 1)
        let catalog = AudioDeviceCatalog(observeChanges: false) {
            XCTAssertFalse(Thread.isMainThread)
            started.fulfill()
            _ = gate.wait(timeout: .now() + 5)
            return [device]
        }
        let refresh = Task { await catalog.refresh() }
        await fulfillment(of: [started], timeout: 2)
        // This main-actor continuation must run while the driver is blocked.
        XCTAssertTrue(catalog.isRefreshing)
        XCTAssertFalse(catalog.hasLoaded)
        await catalog.refresh()
        gate.signal()
        await refresh.value
        XCTAssertEqual(catalog.devices, [device])
        XCTAssertTrue(catalog.hasLoaded)
        XCTAssertFalse(catalog.isRefreshing)
        await catalog.refresh() // A second enumeration would over-fulfill started.
    }

    func testEmptyScanFinishesLoading() async {
        let catalog = AudioDeviceCatalog(observeChanges: false) { [] }
        await catalog.refresh()
        XCTAssertTrue(catalog.hasLoaded)
        XCTAssertTrue(catalog.devices.isEmpty)
        XCTAssertFalse(catalog.isRefreshing)
    }

    func testHardwareChangeDuringScanQueuesOneFreshResult() async {
        let started = expectation(description: "Initial scan started")
        let gate = DispatchSemaphore(value: 0)
        let scanner = Scanner(started: started, gate: gate)
        let catalog = AudioDeviceCatalog(observeChanges: false) { scanner.scan() }
        let refresh = Task { await catalog.refresh() }
        await fulfillment(of: [started], timeout: 2)
        await catalog.refresh(force: true)
        await catalog.refresh(force: true)
        gate.signal()
        await refresh.value
        XCTAssertEqual(catalog.devices.first?.id, "2")
        XCTAssertFalse(catalog.isRefreshing)
    }
}

/// Calls are serialized by the catalog; locking also keeps the fake Sendable.
private final class Scanner: @unchecked Sendable {
    let started: XCTestExpectation
    let gate: DispatchSemaphore
    private let lock = NSLock()
    private var count = 0

    init(started: XCTestExpectation, gate: DispatchSemaphore) {
        self.started = started
        self.gate = gate
    }

    func scan() -> [AudioDevice] {
        lock.lock()
        count += 1
        let index = count
        lock.unlock()
        if index == 1 {
            started.fulfill()
            _ = gate.wait(timeout: .now() + 5)
        }
        return [AudioDevice(id: String(index), name: "Test", isDefault: true,
                            sampleRate: 48000, channelCount: 1)]
    }
}
