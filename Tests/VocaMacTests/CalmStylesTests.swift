// CalmStylesTests.swift
// VocaMac
//
// The Styles page's grouping of app and website rules into Messages,
// Email, Code and Everything else, and what picking a group's card or
// adding an app does to the real rules.

import XCTest
@testable import VocaMac

@MainActor
final class CalmStylesTests: XCTestCase {

    private let slack = RunningAppSnapshot(displayName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap")
    private let messages = RunningAppSnapshot(displayName: "Messages", bundleIdentifier: "com.apple.MobileSMS")
    private let mail = RunningAppSnapshot(displayName: "Mail", bundleIdentifier: "com.apple.mail")
    private let xcode = RunningAppSnapshot(displayName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
    private let unknownEditor = RunningAppSnapshot(displayName: "MyEditor", bundleIdentifier: "com.example.editor")

    private func clearPreferences() {
        for key in [
            PreferenceKey.writingStyleEnabled, PreferenceKey.writingStyleDefault,
            PreferenceKey.writingStyleBindings, PreferenceKey.websiteStyleBindings,
            PreferenceKey.autoCapitalize, PreferenceKey.appendTrailingSpace,
            CalmStyleGroupStore.defaultsKey,
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func setUp() {
        super.setUp()
        clearPreferences()
    }

    override func tearDown() {
        clearPreferences()
        super.tearDown()
    }

    private func makeState() -> AppState {
        let state = AppState.makeTestState().appState
        state.writingStyleBindings = []
        state.websiteStyleBindings = []
        state.calmStyleGroupStore = CalmStyleGroupStore()
        return state
    }

    // MARK: Groups

    func testEveryStyleBelongsToAGroup() {
        let expected: [WritingStyle: CalmStyleGroup] = [
            .plain: .everythingElse, .notes: .everythingElse, .chat: .messages, .slack: .messages,
            .email: .email, .code: .code, .terminal: .code,
        ]
        for style in WritingStyle.allCases {
            XCTAssertEqual(CalmStyleGroup.family(of: style), expected[style], "\(style)")
        }
    }

    func testEachGroupOffersThreeDistinctStylesIncludingItsDefault() {
        for group in CalmStyleGroup.allCases {
            XCTAssertEqual(group.cardStyles.count, 3)
            XCTAssertEqual(Set(group.cardStyles).count, 3)
            XCTAssertTrue(group.cardStyles.contains(group.defaultStyle), "\(group)")
        }
    }

    func testCardSamplesDifferWithinEachGroup() {
        let state = makeState()
        for group in CalmStyleGroup.allCases {
            let samples = group.cardStyles.map { state.writingStylePreview(group.sampleSpeech, style: $0) }
            XCTAssertEqual(Set(samples).count, 3, "\(group): \(samples)")
        }
    }

    func testCatalogPlacesKnownApps() {
        XCTAssertEqual(CalmStyleGroup.catalogGroup(bundleIdentifier: slack.bundleIdentifier, processName: nil, id: "x"), .messages)
        XCTAssertEqual(CalmStyleGroup.catalogGroup(bundleIdentifier: mail.bundleIdentifier, processName: nil, id: "x"), .email)
        XCTAssertEqual(CalmStyleGroup.catalogGroup(bundleIdentifier: xcode.bundleIdentifier, processName: nil, id: "x"), .code)
        XCTAssertEqual(CalmStyleGroup.catalogGroup(bundleIdentifier: "com.apple.Terminal", processName: nil, id: "x"), .code)
        XCTAssertEqual(CalmStyleGroup.catalogGroup(bundleIdentifier: "md.obsidian", processName: nil, id: "x"), .everythingElse)
        XCTAssertNil(CalmStyleGroup.catalogGroup(bundleIdentifier: unknownEditor.bundleIdentifier, processName: nil, id: "x"))
    }

    func testGroupOfARulePrefersAssignmentThenCatalogThenStyle() {
        let state = makeState()
        let known = AppStyleBinding.from(snapshot: slack, style: .plain)
        let unknown = AppStyleBinding.from(snapshot: unknownEditor, style: .code)
        XCTAssertEqual(state.calmStyleGroup(of: known), .messages, "catalog wins over the style")
        XCTAssertEqual(state.calmStyleGroup(of: unknown), .code, "style family for unknown apps")

        var store = CalmStyleGroupStore()
        store.assign(.email, toKey: CalmStyleGroupStore.appKey(known.id))
        state.calmStyleGroupStore = store
        XCTAssertEqual(state.calmStyleGroup(of: known), .email, "an explicit choice wins")

        let site = WebsiteStyleBinding(hostPattern: "github.com", displayName: "github.com", style: .code)
        XCTAssertEqual(state.calmStyleGroup(of: site), .code)
    }

    // MARK: Chosen style

    func testGroupStyleDefaultsThenFollowsMostAppsThenThePick() {
        let state = makeState()
        XCTAssertEqual(state.calmStyle(for: .messages), .chat)

        state.writingStyleBindings = [
            AppStyleBinding.from(snapshot: slack, style: .slack),
            AppStyleBinding.from(snapshot: messages, style: .plain),
            AppStyleBinding(id: "net.whatsapp.WhatsApp", displayName: "WhatsApp", bundleIdentifier: "net.whatsapp.WhatsApp", style: .plain),
        ]
        XCTAssertEqual(state.calmStyle(for: .messages), .plain, "most apps use Plain")

        var store = state.calmStyleGroupStore
        store.setStyle(.slack, for: .messages)
        state.calmStyleGroupStore = store
        XCTAssertEqual(state.calmStyle(for: .messages), .slack, "a picked card wins")
    }

    func testPausedAppsDoNotDecideTheGroupStyle() {
        let state = makeState()
        var paused = AppStyleBinding.from(snapshot: messages, style: .plain)
        paused.isEnabled = false
        state.writingStyleBindings = [AppStyleBinding.from(snapshot: slack, style: .slack), paused]
        XCTAssertEqual(state.calmStyle(for: .messages), .slack)
    }

    func testEverythingElseIsTheDefaultStyle() {
        let state = makeState()
        state.writingStyleDefault = .notes
        XCTAssertEqual(state.calmStyle(for: .everythingElse), .notes)
    }

    func testMostCommonStyleBreaksTiesByCardOrder() {
        XCTAssertNil(AppState.mostCommonStyle([], preferring: [.plain]))
        XCTAssertEqual(AppState.mostCommonStyle([.slack, .chat], preferring: [.plain, .chat, .slack]), .chat)
        XCTAssertEqual(AppState.mostCommonStyle([.slack, .slack, .chat], preferring: [.plain, .chat, .slack]), .slack)
        XCTAssertEqual(AppState.mostCommonStyle([.email, .code], preferring: [.plain]), .code, "then allCases order")
    }

    // MARK: Picking a card

    func testApplyingAStyleUpdatesEveryAppInTheGroupAndKeepsTone() {
        let state = makeState()
        var customized = AppStyleBinding.from(snapshot: slack, style: .slack)
        var rules = WritingStyle.slack.defaultRules
        rules.listMarkers = false
        customized.ruleOverrides = rules
        customized.intent = .casual
        customized.cleanup = .off
        let editor = AppStyleBinding.from(snapshot: xcode, style: .code)
        state.writingStyleBindings = [customized, AppStyleBinding.from(snapshot: messages, style: .chat), editor]

        XCTAssertEqual(state.calmCustomizedApps(in: .messages, switchingTo: .plain).map(\.id), [customized.id])
        XCTAssertTrue(state.calmCustomizedApps(in: .messages, switchingTo: .slack).isEmpty)

        state.calmApplyStyle(.plain, to: .messages)

        let byID = Dictionary(uniqueKeysWithValues: state.writingStyleBindings.map { ($0.id, $0) })
        XCTAssertEqual(byID[customized.id]?.style, .plain)
        XCTAssertNil(byID[customized.id]?.ruleOverrides, "formatting resets to the new style")
        XCTAssertEqual(byID[customized.id]?.intent, .casual, "tone is kept")
        XCTAssertEqual(byID[customized.id]?.cleanup, .off, "AI cleanup is kept")
        XCTAssertEqual(byID["com.apple.MobileSMS"]?.style, .plain)
        XCTAssertEqual(byID[editor.id]?.style, .code, "other groups are untouched")
        XCTAssertEqual(state.calmStyle(for: .messages), .plain)
        XCTAssertEqual(state.writingStyleDefault, .plain)
    }

    func testApplyingAStylePinsUnknownAppsToTheirTab() {
        let state = makeState()
        state.writingStyleBindings = [AppStyleBinding.from(snapshot: unknownEditor, style: .code)]
        XCTAssertEqual(state.calmApps(in: .code).count, 1)

        state.calmApplyStyle(.plain, to: .code)

        XCTAssertEqual(state.writingStyleBindings.first?.style, .plain)
        XCTAssertEqual(state.calmApps(in: .code).count, 1, "Plain would otherwise move it to Everything else")
        XCTAssertTrue(state.calmApps(in: .everythingElse).isEmpty)
    }

    func testApplyingAStyleToEverythingElseSetsTheDefaultAndWebsites() {
        let state = makeState()
        let notesSite = WebsiteStyleBinding(hostPattern: "notion.so", displayName: "Notion", style: .plain)
        state.websiteStyleBindings = [notesSite]

        state.calmApplyStyle(.notes, to: .everythingElse)

        XCTAssertEqual(state.writingStyleDefault, .notes)
        XCTAssertEqual(state.websiteStyleBindings.first?.style, .notes)
        XCTAssertEqual(state.calmWebsites(in: .everythingElse).map(\.id), [notesSite.id])
    }

    func testApplyingAStyleToAnEmptyGroupIsRememberedForNewApps() {
        let state = makeState()
        state.calmApplyStyle(.slack, to: .messages)
        XCTAssertEqual(state.calmStyle(for: .messages), .slack)

        let added = state.calmAddApp(messages, to: .messages)
        XCTAssertEqual(added.style, .slack)
    }

    func testSettingOneAppsStyleResetsItsFormatting() {
        let state = makeState()
        var binding = AppStyleBinding.from(snapshot: xcode, style: .code)
        var rules = WritingStyle.code.defaultRules
        rules.caseCommands = false
        binding.ruleOverrides = rules
        state.writingStyleBindings = [binding]

        state.calmSetStyle(.terminal, forApp: binding.id)
        XCTAssertEqual(state.writingStyleBindings.first?.style, .terminal)
        XCTAssertNil(state.writingStyleBindings.first?.ruleOverrides)
    }

    // MARK: Adding

    func testAddingAKnownAppUsesTheGroupStyleAndKeepsSuggestedTone() {
        let state = makeState()
        state.calmApplyStyle(.plain, to: .email)
        let binding = state.calmAddApp(mail, to: .email)
        XCTAssertEqual(binding.style, .plain)
        XCTAssertEqual(binding.intent, .professional)
        XCTAssertEqual(state.calmApps(in: .email).map(\.id), [binding.id])
    }

    func testAddingAnAppReplacesItsRuleAndMovesItToTheNewTab() {
        let state = makeState()
        state.writingStyleBindings = [AppStyleBinding.from(snapshot: unknownEditor, style: .code)]
        XCTAssertEqual(state.calmExistingGroup(for: unknownEditor), .code)

        state.calmAddApp(unknownEditor, to: .messages)

        XCTAssertEqual(state.writingStyleBindings.count, 1)
        XCTAssertEqual(state.writingStyleBindings.first?.style, .chat)
        XCTAssertEqual(state.calmExistingGroup(for: unknownEditor), .messages)
    }

    func testAddingAWebsiteNormalizesAndReplacesTheSameHost() {
        let state = makeState()
        XCTAssertNil(state.calmAddWebsite("   ", to: .code))

        let first = state.calmAddWebsite("https://GitHub.com/VocaHQ/", to: .code)
        XCTAssertEqual(first?.hostPattern, "github.com")
        XCTAssertEqual(first?.style, .code)
        let second = state.calmAddWebsite("github.com", to: .messages)

        XCTAssertEqual(state.websiteStyleBindings.count, 1)
        XCTAssertEqual(state.websiteStyleBindings.first?.id, second?.id)
        XCTAssertEqual(state.calmWebsites(in: .messages).count, 1)
        XCTAssertTrue(state.calmWebsites(in: .code).isEmpty)
    }

    func testSuggestionsSkipAppsAlreadySetUp() {
        let state = makeState()
        let installed = [slack, messages, xcode]
        XCTAssertEqual(
            state.calmSuggestedApps(for: .messages, installed: installed).compactMap(\.bundleIdentifier),
            ["com.tinyspeck.slackmacgap", "com.apple.MobileSMS"]
        )
        state.writingStyleBindings = [AppStyleBinding.from(snapshot: slack, style: .slack)]
        XCTAssertEqual(
            state.calmSuggestedApps(for: .messages, installed: installed).compactMap(\.bundleIdentifier),
            ["com.apple.MobileSMS"]
        )
        XCTAssertEqual(state.calmSuggestedApps(for: .code, installed: installed).compactMap(\.bundleIdentifier), ["com.apple.dt.Xcode"])
    }

    // MARK: Websites and candidates

    func testWebsiteHostNormalization() {
        XCTAssertEqual(CalmWebsiteHost.normalized("https://Mail.Google.com/mail/u/0"), "mail.google.com")
        XCTAssertEqual(CalmWebsiteHost.normalized("github.com/foo"), "github.com")
        XCTAssertEqual(CalmWebsiteHost.normalized(" *.example.com. "), "*.example.com")
        XCTAssertTrue(CalmWebsiteHost.looksLikeWebsite("github.com"))
        XCTAssertTrue(CalmWebsiteHost.looksLikeWebsite("https://docs.google.com/document"))
        XCTAssertTrue(CalmWebsiteHost.looksLikeWebsite("*.example.co"))
        XCTAssertFalse(CalmWebsiteHost.looksLikeWebsite("notion"))
        XCTAssertFalse(CalmWebsiteHost.looksLikeWebsite("Visual Studio Code"))
        XCTAssertFalse(CalmWebsiteHost.looksLikeWebsite("v1.2"))
        XCTAssertFalse(CalmWebsiteHost.looksLikeWebsite(""))
    }

    func testCandidatesMergeAndFilter() {
        let installed = [
            RunningAppSnapshot(displayName: "Signal", bundleIdentifier: "org.signal"),
            RunningAppSnapshot(displayName: "Notion", bundleIdentifier: "notion.id"),
        ]
        let running = [RunningAppSnapshot(displayName: "Notion", bundleIdentifier: "NOTION.id")]
        let merged = CalmAppCandidates.merged([installed, running], excludingBundleIdentifier: nil)
        XCTAssertEqual(merged.map(\.displayName), ["Notion", "Signal"])
        XCTAssertEqual(CalmAppCandidates.filter(merged, query: "n").map(\.displayName), ["Notion", "Signal"])
        XCTAssertEqual(CalmAppCandidates.filter(merged, query: "sig").map(\.displayName), ["Signal"])
        XCTAssertEqual(CalmAppCandidates.filter(merged, query: " ").count, 2)
        XCTAssertTrue(CalmAppCandidates.merged([installed], excludingBundleIdentifier: "org.signal").allSatisfy { $0.displayName != "Signal" })
    }

    // MARK: Store

    func testStoreRoundTripsAndSurvivesBadData() {
        var store = CalmStyleGroupStore()
        store.assign(.code, toKey: CalmStyleGroupStore.appKey("a"))
        store.setStyle(.terminal, for: .code)
        let decoded = CalmStyleGroupStore.decode(store.encodedJSON())
        XCTAssertEqual(decoded, store)
        XCTAssertEqual(decoded.group(forKey: "app:a"), .code)
        XCTAssertEqual(decoded.style(for: .code), .terminal)

        XCTAssertEqual(CalmStyleGroupStore.decode("not json"), CalmStyleGroupStore())
        XCTAssertEqual(CalmStyleGroupStore.decode(nil), CalmStyleGroupStore())
        let future = CalmStyleGroupStore.decode(#"{"assignments":{"app:a":"later"},"styles":{"code":"fancy"}}"#)
        XCTAssertNil(future.group(forKey: "app:a"), "an unknown group is ignored")
        XCTAssertNil(future.style(for: .code), "an unknown style is ignored")
    }
}
