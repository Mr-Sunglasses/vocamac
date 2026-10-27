// TermSuggestionFinder.swift
// VocaMac
//
// Finds Dictionary terms worth suggesting without waiting for the user to
// correct a dictation, which rarely happens in chat apps: the message is
// already sent.

import Foundation

/// Two sources of evidence for a Dictionary term, both from the user's own
/// dictations:
///
/// - **The screen spelled it.** Spoken words were replaced by a name or
///   identifier read from the screen ("Django nots" → "Djangonauts"). Once
///   that happens twice, the term is worth having when it isn't on screen.
/// - **The speaker keeps saying it.** A name the spell checker doesn't know,
///   in several dictations. Adding it lets every engine listen for it.
enum TermSuggestionFinder {

    // MARK: - Screen respellings

    /// Most words a screen term may replace: "cube or net ease" → "Kubernetes".
    static let maximumHeardWords = 3

    /// Where `final` has a screen term in place of different words in `raw`:
    /// (what was heard, the term). Words that only changed case or spacing
    /// ("user id" → "userId") count too: the term still needed the screen.
    ///
    /// - Parameters:
    ///   - raw: What the speech engine returned.
    ///   - final: What VocaMac typed.
    ///   - terms: The screen terms read for this dictation.
    static func screenRespellings(raw: String, final: String, terms: [String]) -> [(heard: String, term: String)] {
        let listed = Set(terms)
        guard !listed.isEmpty else { return [] }
        let source = words(raw), target = words(final)
        guard !source.isEmpty, !target.isEmpty, source.count * target.count <= 1_000_000 else { return [] }
        var found: [(heard: String, term: String)] = []
        for hunk in changes(from: source.map { $0.lowercased() }, to: target.map { $0.lowercased() }) {
            let added = target[hunk.added]
            let removed = source[hunk.removed]
            guard (1...maximumHeardWords).contains(removed.count), (1...3).contains(added.count) else { continue }
            let term = [added.joined(separator: " "), added.joined()].first(where: listed.contains)
            guard let term, !removed.contains(where: listed.contains) else { continue }
            found.append((removed.joined(separator: " ").lowercased(), term))
        }
        // A case-only respelling ("userid" → "userId") lines up as the same
        // word above, so it is found here: a listed term the speaker's words
        // only had in another casing.
        let spoken = Set(source)
        for term in listed where !spoken.contains(term) && target.contains(term)
            && source.contains(where: { $0.lowercased() == term.lowercased() })
            && !found.contains(where: { $0.term == term }) {
            found.append((term.lowercased(), term))
        }
        return found
    }

    // MARK: - Names said again and again

    /// Dictations a name must appear in before it is suggested.
    static let minimumDictations = 3
    /// Most recent dictations looked at.
    static let maximumDictations = 500

    /// Capitalized words, and pairs of them, with how many of `texts` each
    /// appears in, the commonest spelling first. Only these candidates are
    /// checked against the spell checker, so this part can run off the main
    /// thread.
    static func capitalizedCandidates(in texts: [String]) -> [(term: String, dictations: Int)] {
        var counts: [String: Int] = [:]
        for text in texts.prefix(maximumDictations) {
            var seen = Set<String>()
            let tokens = words(text)
            for (index, token) in tokens.enumerated() where isCapitalizedName(token) {
                seen.insert(token)
                if index + 1 < tokens.count, isCapitalizedName(tokens[index + 1]) {
                    seen.insert(token + " " + tokens[index + 1])
                }
            }
            for term in seen { counts[term, default: 0] += 1 }
        }
        return counts.filter { $0.value >= minimumDictations }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    /// Candidates worth suggesting: every word unknown to the spell checker,
    /// and not already in the Dictionary. A pair is kept only when both of
    /// its words are unknown ("Voca Mac", not "Hey Sergey").
    static func unknownNames(
        _ candidates: [(term: String, dictations: Int)],
        vocabulary: [String],
        isKnownWord: (String) -> Bool,
        limit: Int = 10
    ) -> [String] {
        let listed = Set(vocabulary.map { $0.lowercased() })
        var names: [String] = []
        for candidate in candidates where names.count < limit {
            let parts = candidate.term.split(separator: " ").map(String.init)
            guard !listed.contains(candidate.term.lowercased()),
                  !parts.contains(where: { listed.contains($0.lowercased()) || isKnownWord($0.lowercased()) })
            else { continue }
            names.append(candidate.term)
        }
        // "Voca Phone" covers "Voca" and "Phone" on their own.
        let pairs = names.filter { $0.contains(" ") }
        return names.filter { name in !pairs.contains { $0 != name && $0.split(separator: " ").contains(Substring(name)) } }
    }

    /// A word that reads as a name: a capital, then lowercase letters, at
    /// least three letters in all. All-caps words are left out (acronyms,
    /// shouting), and so are words with digits.
    private static func isCapitalizedName(_ word: String) -> Bool {
        guard word.count >= 3, let first = word.first, first.isUppercase else { return false }
        return word.dropFirst().allSatisfy { $0.isLowercase || $0 == "'" || $0 == "’" }
            || (word.allSatisfy(\.isLetter) && word.dropFirst().contains(where: \.isLowercase))
    }

    // MARK: - Words

    private static let wordExpression = try? NSRegularExpression(pattern: #"[\p{L}\p{N}][\p{L}\p{N}_'’-]*"#)

    static func words(_ text: String) -> [String] {
        guard let wordExpression else { return [] }
        let ns = text as NSString
        return wordExpression.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range).trimmingCharacters(in: CharacterSet(charactersIn: "-'’"))
        }.filter { !$0.isEmpty }
    }

    /// Runs of words that differ between two sequences, from a longest
    /// common subsequence.
    private static func changes(from source: [String], to target: [String]) -> [(removed: Range<Int>, added: Range<Int>)] {
        let rows = source.count, columns = target.count
        var lengths = [[Int32]](repeating: [Int32](repeating: 0, count: columns + 1), count: rows + 1)
        for i in stride(from: rows - 1, through: 0, by: -1) {
            for j in stride(from: columns - 1, through: 0, by: -1) {
                lengths[i][j] = source[i] == target[j] ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }
        var hunks: [(removed: Range<Int>, added: Range<Int>)] = []
        var i = 0, j = 0
        var removedStart = 0, addedStart = 0
        func close() {
            if removedStart < i || addedStart < j { hunks.append((removedStart..<i, addedStart..<j)) }
        }
        while i < rows || j < columns {
            if i < rows, j < columns, source[i] == target[j] {
                close()
                i += 1; j += 1
                removedStart = i; addedStart = j
            } else if i < rows, j >= columns || lengths[i + 1][j] >= lengths[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        close()
        return hunks
    }
}
