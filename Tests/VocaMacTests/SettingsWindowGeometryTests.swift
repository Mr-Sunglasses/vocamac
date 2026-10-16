import XCTest
@testable import VocaMac

final class SettingsWindowGeometryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1050)

    func testCollapsedSavedFrameIsRejected() {
        XCTAssertTrue(SettingsWindowGeometry.needsReset(CGRect(x: 959, y: 766, width: 1, height: 28), screens: [screen]))
    }

    func testUsableFrameIsPreserved() {
        XCTAssertFalse(SettingsWindowGeometry.needsReset(CGRect(x: 300, y: 200, width: 1240, height: 800), screens: [screen]))
    }

    func testMinimumSizeFrameIsPreserved() {
        let size = SettingsWindowGeometry.minimumContentSize
        XCTAssertFalse(SettingsWindowGeometry.needsReset(CGRect(origin: CGPoint(x: 300, y: 200), size: size), screens: [screen]))
    }

    /// The old Settings window (860 × 620) is too small for the v3 window
    /// and its Settings sheet, so a remembered frame of that size resets.
    func testOldSettingsWindowFrameIsRejected() {
        XCTAssertTrue(SettingsWindowGeometry.needsReset(CGRect(x: 300, y: 200, width: 860, height: 658), screens: [screen]))
    }

    func testSettingsSheetFitsTheSmallestWindow() {
        let minimum = SettingsWindowGeometry.minimumContentSize
        XCTAssertGreaterThanOrEqual(minimum.width, CalmMetrics.sheetSize.width + 2 * CalmMetrics.Space.s40)
        XCTAssertGreaterThanOrEqual(minimum.height, CalmMetrics.sheetSize.height + 2 * 30)
        XCTAssertGreaterThanOrEqual(SettingsWindowGeometry.defaultContentSize.width, minimum.width)
        XCTAssertGreaterThanOrEqual(SettingsWindowGeometry.defaultContentSize.height, minimum.height)
    }

    func testDisconnectedDisplayIsRejected() {
        XCTAssertTrue(SettingsWindowGeometry.needsReset(CGRect(x: 2400, y: 200, width: 1240, height: 800), screens: [screen]))
    }

    func testWindowOnSecondaryDisplayIsPreserved() {
        let second = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        XCTAssertFalse(SettingsWindowGeometry.needsReset(CGRect(x: 2400, y: 200, width: 1240, height: 800), screens: [screen, second]))
    }
}
