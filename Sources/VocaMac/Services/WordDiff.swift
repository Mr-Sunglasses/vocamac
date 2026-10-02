// WordDiff.swift
// VocaMac
//
// Word-level difference between two texts, for showing what an edit changed.

import Foundation

enum WordDiff {
    enum Kind: Equatable {
        case same
        case removed
        case added
    }

    struct Segment: Equatable {
        let kind: Kind
        let text: String
    }

    /// Beyond this many words the comparison is skipped and the two texts are
    /// shown whole: a diff of a rewritten chapter helps nobody and costs
    /// quadratic time in the worst case.
    static let maximumTokens = 6_000

    /// `old` and `new` as runs of unchanged, removed, and added text, in
    /// reading order. Joining the `same` and `added` runs gives `new`.
    static func segments(from old: String, to new: String) -> [Segment] {
        let oldTokens = tokens(old), newTokens = tokens(new)
        guard oldTokens.count + newTokens.count <= maximumTokens else {
            return [Segment(kind: .removed, text: old), Segment(kind: .added, text: new)].filter { !$0.text.isEmpty }
        }
        let difference = newTokens.difference(from: oldTokens)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var segments: [Segment] = []
        func append(_ kind: Kind, _ text: String) {
            if let last = segments.last, last.kind == kind {
                segments[segments.count - 1] = Segment(kind: kind, text: last.text + text)
            } else {
                segments.append(Segment(kind: kind, text: text))
            }
        }
        var oldIndex = 0, newIndex = 0
        while oldIndex < oldTokens.count || newIndex < newTokens.count {
            if oldIndex < oldTokens.count, removed.contains(oldIndex) {
                append(.removed, oldTokens[oldIndex])
                oldIndex += 1
            } else if newIndex < newTokens.count, inserted.contains(newIndex) {
                append(.added, newTokens[newIndex])
                newIndex += 1
            } else if oldIndex < oldTokens.count, newIndex < newTokens.count {
                append(.same, newTokens[newIndex])
                oldIndex += 1
                newIndex += 1
            } else {
                // Unreachable for a consistent difference; stop rather than spin.
                break
            }
        }
        return segments
    }

    /// Words and the whitespace between them, each as its own token, so the
    /// tokens joined are the text again.
    static func tokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inWhitespace: Bool?
        for character in text {
            let isWhitespace = character.isWhitespace
            if let inWhitespace, inWhitespace != isWhitespace {
                tokens.append(current)
                current = ""
            }
            current.append(character)
            inWhitespace = isWhitespace
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
