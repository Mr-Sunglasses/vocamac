// UserDefaultTests.swift
// VocaMac
//
// `@UserDefault` stores settings the way `@AppStorage` did and publishes
// its object only when its own value changes.

import Combine
import SwiftUI
import XCTest
@testable import VocaMac

@MainActor
final class UserDefaultTests: XCTestCase {
    private var store: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "UserDefaultTests-\(UUID().uuidString)"
        store = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        store.removePersistentDomain(forName: suiteName)
        store = nil
        super.tearDown()
    }

    @MainActor
    private final class Settings: ObservableObject {
        @UserDefault private(set) var isOn: Bool
        @UserDefault private(set) var count: Int
        @UserDefault private(set) var level: CleanupLevel
        @UserDefault private(set) var languages: String?

        init(store: UserDefaults) {
            _isOn = UserDefault(wrappedValue: true, "test.isOn", store: store)
            _count = UserDefault(wrappedValue: 3, "test.count", store: store)
            _level = UserDefault(wrappedValue: .medium, "test.level", store: store)
            _languages = UserDefault("test.languages", store: store)
        }

        func set(isOn: Bool) { self.isOn = isOn }
        func set(level: CleanupLevel) { self.level = level }
        func set(languages: String?) { self.languages = languages }
    }

    /// Counts `objectWillChange` sends, after any already queued.
    private func changes(of settings: Settings, during body: () -> Void) -> Int {
        var count = 0
        let subscription = settings.objectWillChange.sink { count += 1 }
        body()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        subscription.cancel()
        return count
    }

    func testDefaultsUntilSet() {
        let settings = Settings(store: store)
        XCTAssertTrue(settings.isOn)
        XCTAssertEqual(settings.count, 3)
        XCTAssertEqual(settings.level, .medium)
        XCTAssertNil(settings.languages)
    }

    func testStoresValuesTheWayAppStorageDoes() {
        let settings = Settings(store: store)
        settings.set(isOn: false)
        settings.set(level: .light)
        settings.set(languages: "en,de")
        XCTAssertEqual(store.object(forKey: "test.isOn") as? Bool, false)
        XCTAssertEqual(store.string(forKey: "test.level"), CleanupLevel.light.rawValue)
        XCTAssertEqual(store.string(forKey: "test.languages"), "en,de")

        settings.set(languages: nil)
        XCTAssertNil(store.object(forKey: "test.languages"))
    }

    func testReadsValuesAppStorageWrote() {
        store.set(false, forKey: "test.isOn")
        store.set(9, forKey: "test.count")
        store.set(CleanupLevel.light.rawValue, forKey: "test.level")
        let settings = Settings(store: store)
        XCTAssertFalse(settings.isOn)
        XCTAssertEqual(settings.count, 9)
        XCTAssertEqual(settings.level, .light)
    }

    func testAnUnreadableValueFallsBackToTheDefault() {
        store.set("not a level", forKey: "test.level")
        store.set("not a number", forKey: "test.count")
        let settings = Settings(store: store)
        XCTAssertEqual(settings.level, .medium)
        XCTAssertEqual(settings.count, 3)
    }

    func testSettingPublishesOnce() {
        let settings = Settings(store: store)
        _ = settings.isOn
        XCTAssertEqual(changes(of: settings) { settings.set(isOn: false) }, 1)
    }

    func testAWriteToAnotherKeyDoesNotPublish() {
        let settings = Settings(store: store)
        _ = (settings.isOn, settings.count, settings.level, settings.languages)
        XCTAssertEqual(changes(of: settings) { store.set(UUID().uuidString, forKey: "test.unrelated") }, 0)
    }

    func testAWriteFromElsewherePublishesWhenTheValueChanges() {
        let settings = Settings(store: store)
        _ = settings.count
        XCTAssertEqual(changes(of: settings) { store.set(5, forKey: "test.count") }, 1)
        XCTAssertEqual(settings.count, 5)
        // The same value again changes nothing.
        XCTAssertEqual(changes(of: settings) { store.set(5, forKey: "test.count") }, 0)
    }

    func testAppStateIgnoresUnrelatedDefaultsWrites() {
        let (appState, _) = AppState.makeTestState()
        _ = (appState.historyEnabled, appState.soundEffectsEnabled, appState.hotKeyCode)
        var count = 0
        let subscription = appState.objectWillChange.sink { count += 1 }
        defer { subscription.cancel() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        count = 0
        UserDefaults.standard.set(UUID().uuidString, forKey: "vocamac.tests.unrelated")
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        XCTAssertEqual(count, 0)
        UserDefaults.standard.removeObject(forKey: "vocamac.tests.unrelated")
    }
}
