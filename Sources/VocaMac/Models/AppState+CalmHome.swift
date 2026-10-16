// AppState+CalmHome.swift
// VocaMac
//
// What the v3 Home and Insights pages read from the app state: whether
// Command Mode can be suggested, the keys to show for it and for
// dictation, and the stats summary.

import Foundation

extension AppState {
    /// The Command Mode shortcut as key-cap labels, or nil when none is set.
    var commandModeShortcutCaps: [String]? {
        shortcut(for: .commandMode).map(CalmKeyCaps.labels(for:))
    }

    /// Whether Command Mode can run an edit right now: it has a shortcut
    /// and its model is ready. Home only suggests it then.
    var commandModeIsUsable: Bool {
        commandModeShortcutCaps != nil && commandModeProblem(for: commandModeEngine) == nil
    }

    /// The dictation key as key-cap labels (“Right ⌥”).
    var dictationKeyCaps: [String] {
        CalmKeyCaps.labels(for: HotKeyCombo(keyCode: hotKeyCode, modifiers: hotKeyModifiers))
    }

    /// The verb that goes with the dictation key: “Hold” or “Double-tap”.
    var dictationKeyVerb: String {
        activationMode == .doubleTapToggle ? "Double-tap" : "Hold"
    }

    /// The calendar statistics are kept in.
    var statsCalendar: Calendar {
        CalmActivityCalendar.statsCalendar(for: statsManager.stats)
    }

    /// Totals, streak and bests for Home and Insights.
    func insightsSummary(now: Date = Date()) -> CalmInsightsSummary {
        CalmInsightsSummary(
            stats: statsManager.stats,
            history: historyStore.entries,
            now: now,
            calendar: statsCalendar
        )
    }

    /// Whether there is anything to share or reset on Insights.
    var hasStatistics: Bool {
        let stats = statsManager.stats
        return stats.totalTranscriptions > 0
            || stats.totalWords > 0
            || stats.totalAudioDurationSeconds > 0
            || !stats.dailyWordCounts.isEmpty
    }
}
