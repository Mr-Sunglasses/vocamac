// WritingStyleResolver.swift
// VocaMac
//
// Decides which writing style a given dictation should use. Pure, so the
// whole decision is testable from a fixture list without a window server.

import Foundation

/// The style chosen for one dictation, plus why.
struct ResolvedWritingStyle: Equatable {
    let style: WritingStyle
    let rules: WritingStyleRules
    /// The app whose rule matched, for display in Settings and the menu bar.
    let matchedAppName: String?
    var intent: WritingIntent = .preserve
    var cleanup: WritingCleanupPolicy = .inherit
    var cleanupLevel: CleanupLevel?
    var cleanupPrompt: String?
    /// A Terminal rule whose tab in front runs a coding agent: the text is
    /// prose to the agent, so it is formatted and cleaned up as Plain text
    /// (see `WritingStyleResolver.applyingCodingAgent`). `style` stays
    /// Terminal, which is what the menu shows and binds.
    var codingAgent = false

    var profile: WritingProfile {
        guard codingAgent else {
            return WritingProfile(
                format: style, rules: rules, intent: intent, cleanup: cleanup,
                cleanupLevel: cleanupLevel, cleanupPrompt: cleanupPrompt
            )
        }
        // Prose for the agent, in the speaker's own words: no Formal or
        // Casual rewrite of an instruction.
        return WritingProfile(
            format: .plain, rules: WritingStyle.plain.defaultRules, intent: .preserve, cleanup: cleanup,
            cleanupLevel: cleanupLevel, cleanupPrompt: cleanupPrompt
        )
    }

    /// The style's name as the menu shows it.
    var displayName: String {
        codingAgent ? "\(style.displayName) · coding agent" : style.displayName
    }

    /// The unshaped result: global preferences only.
    static let plain = ResolvedWritingStyle(
        style: .plain,
        rules: WritingStyle.plain.defaultRules,
        matchedAppName: nil
    )

    /// Passthrough used when the feature is switched off. It intentionally
    /// matches Plain's formatting contract while retaining disabled state for
    /// resolution and UI reporting.
    static let disabled = ResolvedWritingStyle(
        style: .plain,
        rules: .passthrough,
        matchedAppName: nil
    )
}

enum WritingStyleResolver {

    /// Resolve the style for the app that is about to receive text.
    ///
    /// - Parameters:
    ///   - target: The frontmost app at injection time, or the snapshot taken
    ///     when recording started. `nil` falls back to the default style.
    ///   - bindings: The user's configured per-app rules.
    ///   - defaultStyle: Used when no binding matches.
    ///   - isEnabled: The master toggle. When off, nothing is shaped at all.
    static func resolve(
        target: RunningAppSnapshot?,
        bindings: [AppStyleBinding],
        defaultStyle: WritingStyle,
        isEnabled: Bool,
        defaultIntent: WritingIntent = .preserve
    ) -> ResolvedWritingStyle {
        guard isEnabled else { return .disabled }

        if let target {
            // Later bindings win, so re-binding an app from the menu bar
            // overrides an earlier seeded entry without needing a removal.
            if let match = bindings.last(where: { $0.isEnabled && $0.matches(target) }) {
                return ResolvedWritingStyle(
                    style: match.style,
                    rules: match.effectiveRules,
                    matchedAppName: match.displayName,
                    intent: match.intent,
                    cleanup: match.cleanup,
                    cleanupLevel: match.cleanupLevel,
                    cleanupPrompt: match.cleanupPrompt
                )
            }
        }

        return ResolvedWritingStyle(
            style: defaultStyle,
            rules: defaultStyle.defaultRules,
            matchedAppName: nil,
            intent: defaultIntent
        )
    }

    /// Dictation into a terminal whose tab in front runs a coding agent
    /// (`CodingAgentDetector`) is prose to the agent, not a command: clean
    /// it up like Plain text. RewriteProtectedText still keeps paths, flags,
    /// and identifiers exact.
    ///
    /// Only the default Terminal behaviour changes. A rule whose rules,
    /// cleanup policy, level, or prompt the user set keeps them: they chose
    /// how that terminal's text should come out.
    static func applyingCodingAgent(_ resolved: ResolvedWritingStyle, detected: Bool) -> ResolvedWritingStyle {
        guard detected, resolved.style == .terminal, resolved.rules == WritingStyle.terminal.defaultRules,
              resolved.cleanup == .inherit, resolved.cleanupLevel == nil,
              resolved.cleanupPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        else { return resolved }
        var prose = resolved
        prose.codingAgent = true
        return prose
    }

    /// Website rules override the receiving browser's app rule. Matching uses
    /// only the URL host and never stores page content or browsing history.
    static func applyingWebsiteRule(
        _ resolved: ResolvedWritingStyle,
        url: URL?,
        bindings: [WebsiteStyleBinding]
    ) -> ResolvedWritingStyle {
        // The most specific domain wins, so a mail.example.com rule beats an
        // example.com rule whichever was added first. Among equals, the later.
        let specificity = { (binding: WebsiteStyleBinding) -> Int in
            binding.hostPattern.trimmingCharacters(in: CharacterSet(charactersIn: "*.")).count
        }
        guard let url,
              let match = bindings.filter({ $0.matches(url) })
                .enumerated()
                .max(by: { (specificity($0.element), $0.offset) < (specificity($1.element), $1.offset) })?
                .element else { return resolved }
        return ResolvedWritingStyle(
            style: match.style,
            rules: match.style.defaultRules,
            matchedAppName: match.displayName,
            intent: match.intent,
            cleanup: match.cleanup,
            cleanupLevel: match.cleanupLevel,
            cleanupPrompt: match.cleanupPrompt
        )
    }
}
