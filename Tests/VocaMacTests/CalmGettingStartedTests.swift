// CalmGettingStartedTests.swift
// VocaMac Tests

import XCTest
@testable import VocaMac

@MainActor
final class CalmGettingStartedTests: XCTestCase {
    func testFreshInstallHasNothingDone() {
        let (state, _) = AppState.makeTestState()
        state.selectedModelSize = ModelSize.tiny.rawValue
        state.transcriptCleanupEnabled = false
        state.setVocabularyTerms([])
        state.wordReplacements = []

        XCTAssertFalse(state.calmGettingStartedDone.contains(.pickModel))
        XCTAssertFalse(state.calmGettingStartedDone.contains(.addWord))
        XCTAssertFalse(state.calmGettingStartedDone.contains(.smartCleanup))
    }

    func testStepsTickOffFromSettings() {
        let (state, _) = AppState.makeTestState()
        state.selectedModelSize = ModelSize.parakeetV3.rawValue
        state.transcriptCleanupEnabled = true
        state.setVocabularyTerms(["Priya Raman"])

        let done = state.calmGettingStartedDone
        XCTAssertTrue(done.contains(.pickModel))
        XCTAssertTrue(done.contains(.addWord))
        XCTAssertTrue(done.contains(.smartCleanup))
    }

    func testHomeTitleWelcomesBackOnlyAfterADictation() {
        let (state, _) = AppState.makeTestState()
        XCTAssertEqual(state.calmHomeTitle, state.hasStatistics ? "Welcome back" : "Welcome")
    }
}
