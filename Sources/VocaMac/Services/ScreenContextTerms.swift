// ScreenContextTerms.swift
// VocaMac
//
// Picks the words from on-screen text that a speech engine is likely to get
// wrong: code identifiers and names. The dictionary corrector then spells a
// dictation's matching words the way the screen does.

import Foundation

enum ScreenContextTerms {

    static let maximumTerms = 300

    private static let patterns: [NSRegularExpression] = [
        // camelCase and iOS-style names: userId, iPhone, macOS
        #"\b[a-z][a-z0-9]*[A-Z][A-Za-z0-9]*\b"#,
        // Capitals inside a word: GitHub, OpenAI, UserService
        #"\b[A-Z][a-z0-9]+[A-Z][A-Za-z0-9]*\b"#,
        // snake_case and SCREAMING_CASE
        #"\b[A-Za-z][A-Za-z0-9]*(?:_[A-Za-z0-9]+)+\b"#,
        // kebab-case
        #"\b[a-z][a-z0-9]*(?:-[a-z0-9]+)+\b"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    /// Capitalized words; kept only when they don't start a sentence and
    /// aren't ordinary words (which would make "Apple" out of "apple").
    private static let capitalizedWord = try? NSRegularExpression(pattern: #"\b[A-Z][a-z]{2,}\b"#)

    /// Distinct terms, most relevant first, at most `maximumTerms`.
    ///
    /// A term the screen shows more often comes first, then the one nearest
    /// the middle of the text: the reader sends the visible text, or the text
    /// around the caret with the caret in the middle. Engines that take few
    /// hints keep the first ones.
    static func extract(from text: String, isKnownWord: (String) -> Bool) -> [String] {
        guard !text.isEmpty else { return [] }
        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)

        var found: [(location: Int, term: String)] = []
        for regex in patterns {
            for match in regex.matches(in: text, range: fullRange) {
                found.append((match.range.location, source.substring(with: match.range)))
            }
        }

        if let capitalizedWord {
            for match in capitalizedWord.matches(in: text, range: fullRange)
            where !startsSentence(at: match.range.location, in: source) {
                let word = source.substring(with: match.range)
                if !isKnownWord(word.lowercased()) {
                    found.append((match.range.location, word))
                }
            }
        }

        let focus = source.length / 2
        var ranked: [String: (count: Int, distance: Int, first: Int)] = [:]
        var counted = Set<String>()
        for item in found where DictionaryCorrector.normalized(item.term).count >= 3 {
            // Two patterns can match the same word; it was still shown once.
            guard counted.insert("\(item.location):\(item.term)").inserted else { continue }
            let distance = abs(item.location - focus)
            if let rank = ranked[item.term] {
                ranked[item.term] = (rank.count + 1, min(rank.distance, distance), min(rank.first, item.location))
            } else {
                ranked[item.term] = (1, distance, item.location)
            }
        }
        return ranked.sorted { lhs, rhs in
            // Past a few mentions, more says little.
            let lhsCount = min(lhs.value.count, 3), rhsCount = min(rhs.value.count, 3)
            if lhsCount != rhsCount { return lhsCount > rhsCount }
            if lhs.value.distance != rhs.value.distance { return lhs.value.distance < rhs.value.distance }
            return lhs.value.first < rhs.value.first
        }.prefix(maximumTerms).map(\.key)
    }

    /// Whether the word at `location` opens a sentence or line, where a
    /// capital letter says nothing about it being a name.
    private static func startsSentence(at location: Int, in source: NSString) -> Bool {
        var index = location - 1
        while index >= 0 {
            guard let scalar = UnicodeScalar(source.character(at: index)) else { return false }
            let character = Character(scalar)
            if character == " " || character == "\t" {
                index -= 1
                continue
            }
            return character == "\n" || character == "." || character == "!" || character == "?"
                || character == "\"" || character == "“" || character == "#" || character == "-"
                || character == "*" || character == ">"
        }
        return true
    }
}
