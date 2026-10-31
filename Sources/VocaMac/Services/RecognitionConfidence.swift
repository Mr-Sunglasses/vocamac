// RecognitionConfidence.swift
// VocaMac
//
// Which words the speech engine was unsure of.
//
// Whisper (token log-probabilities) and Parakeet (token confidences) report
// how sure they were of each word; Apple Speech, the ONNX models and a remote
// endpoint don't. A real word decoded with low confidence is the evidence
// `DictionaryCorrector` needs before it respells ordinary words as a term
// that sounds the same.

import Foundation

enum RecognitionConfidence {

    /// Below this a word counts as unsure. Whisper's word probability for a
    /// clearly spoken common word is usually above 0.9; misheard names and
    /// jargon fall well below this.
    static let lowThreshold = 0.6

    /// Normalized words (see `DictionaryCorrector.normalized`) decoded below
    /// `lowThreshold`, or nil when no word in `segments` carries a
    /// confidence, so callers can tell "sure of everything" from "doesn't
    /// say".
    static func lowConfidenceWords(in segments: [TimedSegment]) -> Set<String>? {
        let words = segments.flatMap(\.words)
        guard words.contains(where: { $0.probability != nil }) else { return nil }
        var unsure = Set<String>()
        for word in words {
            guard let probability = word.probability, probability < lowThreshold else { continue }
            let key = DictionaryCorrector.normalized(word.word)
            if !key.isEmpty { unsure.insert(key) }
        }
        return unsure
    }
}
