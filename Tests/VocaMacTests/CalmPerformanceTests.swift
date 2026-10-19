// CalmPerformanceTests.swift
// VocaMac
//
// Main-thread cost of the v3 window with a heavy user's data: a year of
// history (5,000 dictations), a full year of stats, 300 dictionary words,
// 50 snippets and 30 app rules. Each step renders the real window offscreen
// (layout plus a full draw), so the numbers include SwiftUI's body,
// layout and drawing work, not just model code.
//
// Wall-clock timings depend on the machine, so like the dictation
// benchmarks these run only on request: set VOCAMAC_PERF_REPORT to a file
// path and the table of timings is appended there. The thresholds catch a
// regression back to work that grows with the data (a feed or list that
// builds every row, a dialog that rebuilds its list per row). CI checks
// paging itself with `CalmFeedPagingTests`, which doesn't time anything.

import AppKit
import SwiftUI
import XCTest
@testable import VocaMac

@MainActor
final class CalmPerformanceTests: XCTestCase {

    // MARK: - Thresholds

    /// The most any single interaction may take on the large state, in ms.
    private static let interactionBudget = 300.0
    /// The most a first render of a page may take, in ms.
    private static let firstRenderBudget = 300.0

    /// The report file, or a skip when the benchmark wasn't asked for.
    private static func reportPath() throws -> String {
        guard let path = ProcessInfo.processInfo.environment["VOCAMAC_PERF_REPORT"], !path.isEmpty else {
            throw XCTSkip("Set VOCAMAC_PERF_REPORT to a file path to run the timing benchmarks")
        }
        return path
    }

    // MARK: - Tests

    func testInteractionsStayFastWithLargeState() throws {
        let reportPath = try Self.reportPath()
        let fixture = try CalmPerfFixture(historyCount: 5_000)
        defer { fixture.tearDown() }
        var report = Report()

        // Warm up type metadata, fonts and caches once, untimed: the first
        // render in a process pays for things no user interaction does.
        fixture.render()
        for page in CalmMainPage.allCases {
            fixture.navigator.show(page)
            fixture.render()
        }
        fixture.navigator.show(.home)
        fixture.render()

        // An update with nothing to do: the floor under every other number.
        report.add("Idle update (nothing changed)", fixture.time {})

        // Page switches.
        for page in CalmMainPage.allCases where page != .home {
            report.add("Switch to \(page.title)", fixture.time { fixture.navigator.show(page) })
            report.add("Switch back to Home", fixture.time { fixture.navigator.show(.home) })
        }

        // AppState churn while Home shows: a status change publishes
        // AppState, which every observing view re-reads.
        report.add("Home: AppState change", fixture.time { fixture.appState.isAutoPaused.toggle() })

        // The Settings sheet and each of its pages.
        report.add("Open Settings sheet", fixture.time { fixture.navigator.openSettings(.general) })
        for destination in CalmSettingsDestination.allCases where destination != .general {
            report.add("Settings › \(destination.title)", fixture.time { fixture.navigator.select(destination) })
        }
        fixture.navigator.select(.general)
        fixture.render()
        report.add("Settings › General: toggle", fixture.time { fixture.appState.soundEffectsEnabled.toggle() })
        report.add("Settings › General: AppState change", fixture.time { fixture.appState.isAutoPaused.toggle() })
        report.add("Settings search", fixture.time { fixture.navigator.settingsSearchText = "microphone" })
        report.add("Close Settings sheet", fixture.time { fixture.navigator.closeSettings() })

        // Dialogs, over the page that opens them.
        fixture.navigator.show(.styles)
        fixture.render()
        report.add("Styles: open Add app dialog", fixture.time { fixture.dialogs.shown = .addApp })
        // Its list of installed apps arrives from a background task.
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        fixture.render()
        report.add("Add app dialog: AppState change", fixture.time { fixture.appState.isAutoPaused.toggle() })
        report.add("Close Add app dialog", fixture.time { fixture.dialogs.shown = nil })
        fixture.navigator.openSettings(.general)
        fixture.render()
        report.add("General: open Microphone dialog", fixture.time { fixture.dialogs.shown = .microphone })
        report.add("Close Microphone dialog", fixture.time { fixture.dialogs.shown = nil })
        fixture.navigator.closeSettings()
        fixture.navigator.show(.home)
        fixture.render()
        report.add("Home: unrelated defaults write", fixture.time {
            UserDefaults.standard.set(UUID().uuidString, forKey: "vocamac.tests.perf.unrelated")
        })
        UserDefaults.standard.removeObject(forKey: "vocamac.tests.perf.unrelated")

        report.write(to: reportPath, title: "Interactions, 5,000 history entries")
        for (label, timing) in report.rows {
            XCTAssertLessThan(timing.update, Self.interactionBudget, "\(label) took \(Int(timing.update)) ms")
        }
    }

    func testFirstRenderOfEachPageWithLargeState() throws {
        let reportPath = try Self.reportPath()
        var report = Report()
        for page in CalmMainPage.allCases {
            let fixture = try CalmPerfFixture(historyCount: 5_000, page: page)
            defer { fixture.tearDown() }
            report.add("First render: \(page.title)", fixture.time(settling: false) {})
        }
        report.write(to: reportPath, title: "First render, 5,000 history entries")
        for (label, timing) in report.rows {
            XCTAssertLessThan(timing.update, Self.firstRenderBudget, "\(label) took \(Int(timing.update)) ms")
        }
    }

    /// Home's first render barely depends on how much history there is:
    /// the feed builds only the rows on its first page.
    func testHomeFirstRenderDoesNotGrowWithHistory() throws {
        let reportPath = try Self.reportPath()
        var report = Report()
        for count in [50, 500, 5_000] {
            let fixture = try CalmPerfFixture(historyCount: count, page: .insights)
            defer { fixture.tearDown() }
            fixture.render()
            report.add("Home first render, \(count) entries", fixture.time { fixture.navigator.show(.home) })
        }
        report.write(to: reportPath, title: "Home first render by history size")
        let small = report.rows[0].timing.update
        let large = report.rows[2].timing.update
        XCTAssertLessThan(large, Self.firstRenderBudget)
        // 100× the history may cost a little more, but the feed builds the
        // same first page of rows either way.
        XCTAssertLessThan(large - small, 60, "Home with 5,000 entries took \(Int(large)) ms, with 50 \(Int(small)) ms")
    }

    /// Search over 5,000 entries doesn't block typing.
    func testHomeSearchStaysFast() throws {
        _ = try Self.reportPath()
        let fixture = try CalmPerfFixture(historyCount: 5_000)
        defer { fixture.tearDown() }
        let store = fixture.appState.historyStore
        let start = CFAbsoluteTimeGetCurrent()
        let results = store.search("meeting notes")
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1_000
        XCTAssertFalse(results.isEmpty)
        XCTAssertLessThan(elapsed, Self.interactionBudget)
    }
}

// MARK: - Fixture

/// The window on a large state, rendered offscreen.
@MainActor
final class CalmPerfFixture {
    let appState: AppState
    let mocks: TestMocks
    let navigator: CalmNavigator
    let dialogs = DialogSwitch()
    let window: NSWindow
    let host: NSHostingView<AnyView>
    let directory: URL

    init(historyCount: Int, page: CalmMainPage = .home) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CalmPerformance-\(UUID().uuidString)", isDirectory: true)
        try LargeState.writeHistory(count: historyCount, to: directory)
        let store = DictationHistoryStore(directory: directory)
        (appState, mocks) = AppState.makeTestState(historyStore: store)
        LargeState.fill(appState, mocks: mocks)

        navigator = CalmNavigator(mainPage: page)
        let root = DialogHarness(navigator: navigator, dialogs: dialogs)
            .environmentObject(appState)
            .environmentObject(SettingsWindowManager.shared)
        host = NSHostingView(rootView: AnyView(root))
        let size = SettingsWindowGeometry.defaultContentSize
        host.frame = NSRect(origin: .zero, size: size)
        window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        // On screen (far off it), so views display and layers commit as
        // they do in the app.
        window.orderFrontRegardless()
    }

    func tearDown() {
        window.contentView = nil
        window.close()
        try? FileManager.default.removeItem(at: directory)
        UserDefaults.standard.removeObject(forKey: CalmWindowView.lastMainPageKey)
    }

    /// Bring the window up to date the way a frame does: pending updates,
    /// layout, layer display (text and shapes drawn into their layers),
    /// and the Core Animation commit.
    func update() {
        RunLoop.main.run(until: Date())
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        CATransaction.flush()
    }

    /// Rasterize the whole window on the CPU, shadows, blurs and opacity
    /// groups included. A real window leaves that compositing to the window
    /// server, so this is reported but not budgeted.
    func rasterize() {
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
    }

    /// Let animations and follow-up work from the last step finish, so
    /// each measurement starts from a quiet window.
    func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        render()
    }

    func render() {
        update()
        rasterize()
    }

    /// The main-thread work from `action` until the window has been redrawn,
    /// and, separately, a full CPU rasterization of the result.
    func time(settling: Bool = true, _ action: () -> Void) -> Timing {
        if settling { settle() }
        let start = CFAbsoluteTimeGetCurrent()
        action()
        update()
        // Work that lands one turn later (onAppear, onChange, preference
        // updates) still comes before the screen settles.
        update()
        let updated = CFAbsoluteTimeGetCurrent()
        rasterize()
        let rasterized = CFAbsoluteTimeGetCurrent()
        return Timing(update: (updated - start) * 1_000, raster: (rasterized - updated) * 1_000)
    }
}

// MARK: - Dialog harness

/// Which real dialog the harness shows.
enum PerfDialog {
    case addApp
    case microphone
}

@MainActor
@Observable
final class DialogSwitch {
    var shown: PerfDialog?
}

/// The window with a dialog presented the way pages present theirs: the
/// window under it disabled (as `CalmWindowView` does while a dialog is
/// up) and the dialog drawn by a dialog host over everything.
private struct DialogHarness: View {
    let navigator: CalmNavigator
    @Bindable var dialogs: DialogSwitch

    var body: some View {
        let isPresented = dialogs.shown != nil
        CalmWindowView(navigator: navigator)
            .disabled(isPresented)
            .environment(\.calmDimsWhenDisabled, !isPresented)
            .accessibilityHidden(isPresented)
            .background {
                Color.clear.calmDialog(item: $dialogs.shown) { dialog in
                    switch dialog {
                    case .addApp: CalmStylesAddDialog(group: .messages) { _ in }
                    case .microphone: CalmMicrophoneDialog()
                    }
                }
            }
            .calmDialogHost()
    }
}

// MARK: - Large state

@MainActor
private enum LargeState {
    static let apps: [(name: String, bundle: String)] = [
        ("Slack", "com.tinyspeck.slackmacgap"), ("Mail", "com.apple.mail"),
        ("Notes", "com.apple.Notes"), ("Xcode", "com.apple.dt.Xcode"),
        ("Safari", "com.apple.Safari"), ("Messages", "com.apple.MobileSMS"),
        ("Terminal", "com.apple.Terminal"), ("Visual Studio Code", "com.microsoft.VSCode"),
        ("Notion", "notion.id"), ("Linear", "com.linear"), ("Google Chrome", "com.google.Chrome"),
        ("Pages", "com.apple.iWork.Pages"),
    ]

    static let words = """
    the meeting notes we agreed on yesterday should go out before lunch so everyone can review the plan \
    and then we can talk about the launch timeline the budget the hiring plan and what the customers asked \
    for in the last round of interviews please make sure the draft includes the numbers from finance
    """.split(separator: " ").map(String.init)

    /// `count` dictations over the past year, newest first, written as the
    /// store's index so it loads them the way it does at launch.
    static func writeHistory(count: Int, to directory: URL) throws {
        var generator = SeededGenerator(seed: 42)
        let now = Date()
        let span: TimeInterval = 365 * 24 * 3_600
        var entries: [DictationHistoryEntry] = []
        entries.reserveCapacity(count)
        for index in 0..<count {
            let age = span * Double(index) / Double(max(count, 1))
            let wordCount = [4, 12, 30, 60, 120, 220][Int.random(in: 0..<6, using: &generator)]
            let text = (0..<wordCount).map { _ in words[Int.random(in: 0..<words.count, using: &generator)] }
                .joined(separator: " ")
            let app = apps[Int.random(in: 0..<apps.count, using: &generator)]
            let isEdit = index % 37 == 0
            let status: DictationHistoryStatus = index % 53 == 0 ? .failed : .completed
            entries.append(DictationHistoryEntry(
                createdAt: now.addingTimeInterval(-age - 60),
                status: status,
                rawText: isEdit ? "make it shorter" : text,
                finalText: status == .failed ? "" : text.prefix(1).uppercased() + text.dropFirst() + ".",
                appName: app.name,
                bundleIdentifier: app.bundle,
                modelID: "parakeet-v3",
                audioSeconds: Double(wordCount) / 2.4,
                transcriptionSeconds: 0.4,
                errorMessage: status == .failed ? "The model stopped before it finished." : nil,
                retryCount: index % 41 == 0 ? 1 : 0,
                commandOriginal: isEdit ? text : nil
            ))
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(entries).write(to: directory.appendingPathComponent("index.json"))
    }

    /// A full year of stats, 300 dictionary words, 50 snippets and 30 app rules.
    static func fill(_ appState: AppState, mocks: TestMocks) {
        var generator = SeededGenerator(seed: 7)
        var stats = UserStats()
        let calendar = CalmActivityCalendar.statsCalendar(for: stats)
        let today = calendar.startOfDay(for: Date())
        for back in 0..<400 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            let key = CalmActivityCalendar.dayKey(for: day, calendar: calendar)
            let words = Int.random(in: 0..<2_400, using: &generator)
            stats.dailyWordCounts[key] = words
            stats.dailyTranscriptionCounts[key] = words / 40
            stats.dailyAudioSeconds[key] = Double(words) / 2.4
            stats.totalWords += words
            stats.totalTranscriptions += words / 40
            stats.totalAudioDurationSeconds += Double(words) / 2.4
        }
        stats.currentStreak = 120
        stats.bestStreak = 210
        stats.lastUsageDate = Date()
        stats.longestDictationSeconds = 240
        mocks.statsManager.stats = stats

        appState.setVocabularyTerms((0..<300).map { "Term\($0) \(words[$0 % words.count].capitalized)" })
        appState.wordReplacements = (0..<40).map {
            WordReplacement(heard: "phrase \($0)", replacement: "Replacement \($0)")
        }
        appState.snippets = (0..<50).map {
            Snippet(trigger: "snippet \($0)", expansion: String(repeating: "Expansion text \($0). ", count: 6))
        }
        appState.writingStyleBindings = (0..<30).map { index in
            AppStyleBinding(
                id: "com.example.app\(index)", displayName: "Example App \(index)",
                bundleIdentifier: "com.example.app\(index)",
                style: WritingStyle.allCases[index % WritingStyle.allCases.count]
            )
        }
    }
}

/// A small deterministic generator, so every run builds the same data.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

// MARK: - Report

/// One measurement: the main-thread update (body, layout, layer display,
/// commit), and a full CPU rasterization of the window.
struct Timing {
    let update: Double
    let raster: Double
}

private struct Report {
    private(set) var rows: [(label: String, timing: Timing)] = []

    mutating func add(_ label: String, _ timing: Timing) {
        rows.append((label, timing))
    }

    /// Appends the table to the report file.
    func write(to path: String, title: String) {
        var lines = ["", "== \(title) ==", "step".padding(toLength: 44, withPad: " ", startingAt: 0) + "  update ms  raster ms"]
        for (label, timing) in rows {
            lines.append(label.padding(toLength: 44, withPad: " ", startingAt: 0)
                + String(format: "%11.1f%11.1f", timing.update, timing.raster))
        }
        let text = lines.joined(separator: "\n") + "\n"
        let url = URL(fileURLWithPath: path)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
