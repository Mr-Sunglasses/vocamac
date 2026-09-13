// MeetingCaptureSessionTests.swift
// VocaMacTests

import XCTest
@testable import VocaMac

@MainActor
final class MeetingCaptureSessionTests: XCTestCase {
    func testAudioIsPendingUntilItIsTranscribed() {
        let session = MeetingCaptureSession()
        XCTAssertNil(session.pendingAudio, "Nothing captured: the window can close freely")

        session.capturedSamples = [0.2, 0.1]
        session.isTranscribing = true
        XCTAssertEqual(session.pendingAudio, .transcribing)

        session.isTranscribing = false
        XCTAssertEqual(session.pendingAudio, .notTranscribed, "A failed transcription keeps its audio")

        session.capturedSamples = nil
        XCTAssertNil(session.pendingAudio)
    }
}
