// DockVisibilityCoordinatorTests.swift
// VocaMac Tests
//
// Tests for when the Dock icon appears and disappears as windows open and
// close. The app is menu-bar-only, so the icon should be visible exactly
// while at least one window is on screen.

import AppKit
import XCTest

@testable import VocaMac

@MainActor
final class DockVisibilityCoordinatorTests: XCTestCase {

    /// Records policy changes instead of touching the real NSApplication.
    private final class PolicyRecorder {
        var applied: [NSApplication.ActivationPolicy] = []
    }

    private func makeCoordinator(
        hideDelay: TimeInterval = 0
    ) -> (DockVisibilityCoordinator, PolicyRecorder) {
        let recorder = PolicyRecorder()
        let coordinator = DockVisibilityCoordinator(hideDelay: hideDelay) { policy in
            recorder.applied.append(policy)
        }
        return (coordinator, recorder)
    }

    /// Let a zero-delay hide land.
    private func settle() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    func testOpeningAWindowShowsTheDockIcon() {
        let (coordinator, recorder) = makeCoordinator()

        coordinator.windowDidOpen()

        XCTAssertEqual(recorder.applied, [.regular])
        XCTAssertEqual(coordinator.openWindowCount, 1)
    }

    func testClosingTheOnlyWindowHidesTheDockIcon() async {
        let (coordinator, recorder) = makeCoordinator()

        coordinator.windowDidOpen()
        coordinator.windowDidClose()
        await settle()

        XCTAssertEqual(recorder.applied, [.regular, .accessory])
        XCTAssertEqual(coordinator.openWindowCount, 0)
    }

    /// The bug this coordinator exists for: closing one window while another
    /// is still open used to hide the Dock icon out from under it.
    func testClosingOneOfTwoWindowsKeepsTheDockIcon() async {
        let (coordinator, recorder) = makeCoordinator()

        coordinator.windowDidOpen()   // Settings
        coordinator.windowDidOpen()   // Update
        coordinator.windowDidClose()  // Update closes, Settings still open
        await settle()

        XCTAssertFalse(recorder.applied.contains(.accessory),
                       "Dock icon was hidden while a window was still open")
        XCTAssertEqual(coordinator.openWindowCount, 1)
    }

    func testDockIconHidesOnlyAfterTheLastWindowCloses() async {
        let (coordinator, recorder) = makeCoordinator()

        coordinator.windowDidOpen()
        coordinator.windowDidOpen()
        coordinator.windowDidClose()
        await settle()
        XCTAssertFalse(recorder.applied.contains(.accessory))

        coordinator.windowDidClose()
        await settle()
        XCTAssertEqual(recorder.applied.last, .accessory)
        XCTAssertEqual(coordinator.openWindowCount, 0)
    }

    /// A window opening during the grace period cancels the pending hide,
    /// so the icon does not flicker when one window replaces another.
    func testReopeningDuringTheGracePeriodKeepsTheDockIcon() async {
        let (coordinator, recorder) = makeCoordinator(hideDelay: 0.2)

        coordinator.windowDidOpen()
        coordinator.windowDidClose()
        coordinator.windowDidOpen()
        await settle()
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertFalse(recorder.applied.contains(.accessory),
                       "Dock icon was hidden even though a window reopened")
        XCTAssertEqual(coordinator.openWindowCount, 1)
    }

    func testCloseWithoutOpenDoesNotDriveTheCountNegative() async {
        let (coordinator, _) = makeCoordinator()

        coordinator.windowDidClose()
        await settle()

        XCTAssertEqual(coordinator.openWindowCount, 0)
    }
}
