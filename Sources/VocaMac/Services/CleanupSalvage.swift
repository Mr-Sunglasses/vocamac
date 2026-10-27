// CleanupSalvage.swift
// VocaMac
//
// Keeps the safe part of a model cleanup: the words it deleted that are
// clearly filler, applied to what the user actually said.

import Foundation

/// A small cleanup model often gets the fillers right and one other thing
/// wrong — it turns "George" into "our", or drops a name. Accepting the whole
/// answer is unsafe and rejecting it throws the good deletions away too.
///
/// This lines the model's answer up against the original, word by word, and
/// returns only the deletions that can't change meaning:
///
/// - hesitations ("um", "uh")
/// - filler words set off by commas ("it was, like, huge", "you know,")
/// - a sentence-opening "so," / "well," / "okay,"
/// - an accidental repeat right next to the same word ("gone gone")
/// - a cut-off start of the next word ("sn scan", "web website")
/// - a restart the speaker abandoned ("I want to, I need to fix it")
///
/// Everything else the model did — rewording, re-casing, insertions — is
/// ignored. The deletions are applied to the user's own text, so the result
/// is always their words minus filler. Code and Terminal styles use only this:
/// the model decides what is filler, and never writes into a command.
enum CleanupSalvage {

    /// Ranges in `original` (words plus the punctuation stuck to them) that
    /// the model deleted and that are safe to delete.
    static func safeDeletions(
        original: String, candidate: String, isKnownWord: (String) -> Bool = { _ in true }
    ) -> [NSRange] {
        let source = tokens(in: original)
        let target = tokens(in: candidate)
        guard !source.isEmpty, source.count * max(target.count, 1) <= 4_000_000 else { return [] }
        let kept = alignedSourceIndices(source.map(\.core), target.map(\.core))
        // A real word counts as clipped ("web website") only in sentences: in
        // "pip install pip pipenv" or "make web website" both are arguments.
        let allowsClippedWords = WritingStyleEngine.readsAsProse(original)

        var deletions: [NSRange] = []
        var index = 0
        while index < source.count {
            guard !kept.contains(index) else { index += 1; continue }
            var end = index
            while end + 1 < source.count, !kept.contains(end + 1) { end += 1 }
            if let ranges = safeRanges(
                for: Array(index...end), in: source, kept: kept,
                allowsClippedWords: allowsClippedWords, isKnownWord: isKnownWord
            ) {
                deletions.append(contentsOf: ranges)
            }
            index = end + 1
        }
        return deletions
    }

    // MARK: - Safety rules

    static let commaFillers: Set<String> = [
        "like", "you know", "you see",
    ]
    static let openingFillers: Set<String> = [
        "so", "well", "okay", "ok", "alright",
    ]
    static let unfinishedEndings: Set<String> = ["to", "a", "an", "the", "for", "with", "of"]
    /// Words people double on purpose: "very very", "no no", "bye bye".
    static let intentionalRepeats: Set<String> = [
        "very", "really", "so", "much", "many", "more", "no", "yes", "yeah", "bye", "ha",
        "hey", "please", "go", "again", "far", "long", "too", "super", "now", "well",
        "right", "okay", "ok", "wait", "come", "knock", "what", "why", "that", "had", "thank",
    ]

    /// Words of `intentionalRepeats` that are doubled by grammar or surprise
    /// rather than for emphasis: "I know that that works", "had had", "what
    /// what?". Two copies stay; a third ("what what what is this") or a
    /// longer phrase they open ("what is it what is it") is a stutter.
    static let grammaticalDoubles: Set<String> = ["what", "why", "that", "had"]

    /// Digits read out repeat on purpose: "four two four two" is a code.
    static let numberWords: Set<String> = [
        "zero", "oh", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
        "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "thousand",
        "million", "billion", "double", "triple",
    ]

    /// Longest phrase, in words, whose accidental repeat may be removed: "you
    /// can see you can see", "I was going to say I was going to say".
    static let longestRepeatedPhrase = 6

    /// The length in words of the phrase `removed` repeats, when `removed` is
    /// one or more copies of a phrase said again right beside it, so taking
    /// it out leaves one copy: "if if", "what what what", "voice to voice to
    /// text". Nil when it isn't, or when the repeat is likely on purpose
    /// ("very very", "no no no", "four two four two").
    ///
    /// - Parameters:
    ///   - removed: The deleted words, lowercased, in order.
    ///   - following: The kept words right after the deletion.
    ///   - preceding: The kept words right before it.
    static func repeatedPhraseLength(_ removed: [String], following: [String], preceding: [String]) -> Int? {
        guard let first = removed.first else { return nil }
        for length in 1...min(longestRepeatedPhrase, removed.count) where removed.count % length == 0 {
            let unit = Array(removed.prefix(length))
            guard !unit.contains(where: numberWords.contains),
                  stride(from: length, to: removed.count, by: length)
                    .allSatisfy({ Array(removed[$0..<($0 + length)]) == unit }),
                  Array(following.prefix(length)) == unit || Array(preceding.suffix(length)) == unit else { continue }
            guard intentionalRepeats.contains(first) else { return length }
            let copies = removed.count / length + 1
            return grammaticalDoubles.contains(first) && (length > 1 || copies >= 3) ? length : nil
        }
        return nil
    }

    /// What to delete for one run of words the model left out, or nil when
    /// the run isn't safely filler. Usually the run itself; for a repeat, the
    /// first copy, so "the, the build" loses "the," rather than leaving
    /// "the, build".
    private static func safeRanges(
        for run: [Int], in source: [Token], kept: Set<Int>, allowsClippedWords: Bool,
        isKnownWord: (String) -> Bool
    ) -> [NSRange]? {
        // Hesitations can go wherever they sit, even beside an unsafe edit;
        // judge what is left.
        let hesitations = run.filter { WritingStyleEngine.isHesitationWord(source[$0].core) }.map { source[$0].range }
        let onlyHesitations = hesitations.isEmpty ? nil : hesitations
        // A protected technical token or snippet is never filler.
        guard run.allSatisfy({ !source[$0].isProtected }) else { return onlyHesitations }
        let wholeRun = [NSUnionRange(source[run[0]].range, source[run[run.count - 1]].range)]
        let words = run.filter { !WritingStyleEngine.isHesitationWord(source[$0].core) }
        guard let first = words.first, let last = words.last else { return wholeRun }

        let phrase = words.map { source[$0].core }.joined(separator: " ")
        let previous = (0..<first).last { kept.contains($0) }
        let next = ((last + 1)..<source.count).first { kept.contains($0) }
        let atSentenceStart = previous.map { source[$0].endsSentence } ?? true
        let commaAfter = source[last].text.hasSuffix(",")
        let commaBefore = previous.map { source[$0].text.hasSuffix(",") } ?? false

        if commaFillers.contains(phrase), commaAfter || commaBefore {
            return wholeRun
        }
        if openingFillers.contains(phrase), atSentenceStart, commaAfter {
            return wholeRun
        }
        // "gone gone", "what what what": the deleted copies sit beside a kept
        // copy.
        if !source[last].text.contains(where: { ".!?".contains($0) }) {
            let copies = words.map { source[$0].core }
            let window = longestRepeatedPhrase
            let after = next.map { next in
                Array((next..<min(next + window, source.count)).prefix { kept.contains($0) }).map { source[$0].core }
            } ?? []
            if repeatedPhraseLength(copies, following: after, preceding: []) != nil {
                return wholeRun
            }
            // The model dropped the later copies; drop the earlier ones
            // instead, so the one the speaker abandoned goes with its
            // trailing comma and the last copy keeps its own punctuation.
            if let previous, !source[previous].text.contains(where: { ".!?".contains($0) }) {
                let lowest = max(0, previous - window + 1)
                let before = Array((lowest...previous).reversed().prefix { kept.contains($0) }.reversed())
                if let length = repeatedPhraseLength(copies, following: [], preceding: before.map { source[$0].core }) {
                    let start = before[before.count - length]
                    let end = words.count > length ? words[words.count - length - 1] : previous
                    return [NSUnionRange(source[start].range, source[end].range)]
                        + hesitations.filter { $0.location > source[end].range.location }
                }
            }
        }
        // "sn scan", "web website": a cut-off start of the very next word,
        // both plain letters. Never a lone letter here — in a command it is
        // a flag, drive, or variable.
        if run.count == 1, let next, next == first + 1,
           source[first].text.allSatisfy(\.isLetter), source[next].text.allSatisfy(\.isLetter),
           EditMerge.isCutOffStart(source[first].core, of: source[next].core, allowsLetter: false, isKnownWord: isKnownWord)
            || (allowsClippedWords && EditMerge.isClippedWord(source[first].core, of: source[next].core)) {
            return wholeRun
        }
        // "I want to, I need to": an abandoned start, marked by a comma or
        // dash, that the next kept words start over.
        if (2...6).contains(words.count), let next,
           unfinishedEndings.contains(source[last].core),
           source[last].text.hasSuffix(",") || source[last].text.hasSuffix("—") || source[last].text.hasSuffix("-"),
           source[first].core == source[next].core {
            return wholeRun
        }
        return onlyHesitations
    }

    // MARK: - Tokens

    private struct Token {
        let text: String
        let range: NSRange
        /// Lowercased letters and digits, for alignment.
        let core: String

        var endsSentence: Bool { text.last.map { ".!?…".contains($0) } ?? false }

        /// `RewriteProtectedText` placeholders and masked snippets.
        var isProtected: Bool {
            text.contains("VOCAKEEP") || text.unicodeScalars.contains { (0xE000...0xF8FF).contains($0.value) }
        }
    }

    private static let tokenExpression = try? NSRegularExpression(pattern: #"\S+"#)

    private static func tokens(in text: String) -> [Token] {
        guard let tokenExpression else { return [] }
        let ns = text as NSString
        return tokenExpression.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let word = ns.substring(with: match.range)
            let core = word.lowercased().unicodeScalars
                .filter { CharacterSet.alphanumerics.contains($0) || $0 == "'" || $0 == "’" }
                .map(String.init).joined()
            // Pure punctuation ("—", "...") has nothing to align on.
            return core.isEmpty ? nil : Token(text: word, range: match.range, core: core)
        }
    }

    /// Indices of `source` that a longest common subsequence keeps.
    private static func alignedSourceIndices(_ source: [String], _ target: [String]) -> Set<Int> {
        let rows = source.count, columns = target.count
        guard columns > 0 else { return [] }
        var lengths = [[Int32]](repeating: [Int32](repeating: 0, count: columns + 1), count: rows + 1)
        for i in stride(from: rows - 1, through: 0, by: -1) {
            for j in stride(from: columns - 1, through: 0, by: -1) {
                lengths[i][j] = source[i] == target[j]
                    ? lengths[i + 1][j + 1] + 1
                    : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }
        // Among equally long alignments, prefer the one that drops earlier
        // words: when a word repeats ("gone gone", "I want to, I need to"),
        // the first copy is the one the speaker abandoned.
        var kept = Set<Int>()
        var i = 0, j = 0
        while i < rows, j < columns {
            if lengths[i + 1][j] == lengths[i][j] {
                i += 1
            } else if source[i] == target[j] {
                kept.insert(i); i += 1; j += 1
            } else {
                j += 1
            }
        }
        return kept
    }
}
