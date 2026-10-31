// RecognitionConfidenceTests.swift
// VocaMac

import XCTest
@testable import VocaMac

final class RecognitionConfidenceTests: XCTestCase {

    private func word(_ text: String, _ probability: Double?) -> TimedWord {
        TimedWord(word: text, start: 0, end: 0, probability: probability)
    }

    func testNoConfidenceMeansNil() {
        let segment = TimedSegment(start: 0, end: 1, text: "hello there", words: [word("hello", nil), word("there", nil)])
        XCTAssertNil(RecognitionConfidence.lowConfidenceWords(in: [segment]))
        XCTAssertNil(RecognitionConfidence.lowConfidenceWords(in: []))
    }

    func testCollectsUnsureWordsNormalized() {
        let segment = TimedSegment(start: 0, end: 2, text: "Deploy to cooper netties,", words: [
            word(" Deploy", 0.97), word(" to", 0.99), word(" cooper", 0.41), word(" netties,", 0.32),
        ])
        XCTAssertEqual(RecognitionConfidence.lowConfidenceWords(in: [segment]), ["cooper", "netties"])
    }

    func testSureOfEverythingIsAnEmptySet() {
        let segment = TimedSegment(start: 0, end: 1, text: "yes", words: [word("yes", 0.95)])
        XCTAssertEqual(RecognitionConfidence.lowConfidenceWords(in: [segment]), [])
    }
}
