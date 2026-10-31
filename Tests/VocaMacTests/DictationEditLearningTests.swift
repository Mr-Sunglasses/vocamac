// DictationEditLearningTests.swift
// VocaMac

import XCTest
@testable import VocaMac

final class DictationEditLearningTests: XCTestCase {

    // MARK: - Reading the edited dictation

    func testUnchangedFieldReadsAsDictated() throws {
        let reading = try XCTUnwrap(DictationEditReader.read(
            inserted: "See you at five. ", before: "Hi. See you at five. ", after: "Hi. See you at five. "
        ))
        XCTAssertEqual(reading.editedText, "See you at five.")
        XCTAssertEqual(reading.precedingCharacter, ".")
    }

    func testWritingAfterTheDictationLeavesItAsDictated() throws {
        let reading = try XCTUnwrap(DictationEditReader.read(
            inserted: "See you at five.", before: "See you at five.", after: "See you at five. Bring snacks."
        ))
        XCTAssertEqual(reading.editedText, "See you at five.")
        XCTAssertNil(reading.precedingCharacter, "Start of the field")
    }

    func testWritingBeforeTheDictationLeavesItAsDictated() throws {
        let reading = try XCTUnwrap(DictationEditReader.read(
            inserted: "see you at five", before: "see you at five", after: "Okay see you at five"
        ))
        XCTAssertEqual(reading.editedText, "see you at five")
    }

    func testAnEditInsideTheDictationIsRead() throws {
        let reading = try XCTUnwrap(DictationEditReader.read(
            inserted: "Basically we ship Friday.", before: "Notes: Basically we ship Friday.",
            after: "Notes: We ship Friday."
        ))
        XCTAssertEqual(reading.editedText, "We ship Friday.")
        XCTAssertEqual(reading.precedingCharacter, ":")
    }

    func testAnEditReachingPastTheDictationIsUnknown() throws {
        let reading = try XCTUnwrap(DictationEditReader.read(
            inserted: "ship Friday", before: "We should ship Friday", after: "Let's ship Monday"
        ))
        XCTAssertNil(reading.editedText)
    }

    func testADictationNotInTheFieldReadsNothing() {
        XCTAssertNil(DictationEditReader.read(inserted: "hello", before: "goodbye", after: "goodbye!"))
    }

    // MARK: - Personal fillers

    func testDeletedFillersAreFound() {
        XCTAssertEqual(PersonalFillers.deletions(dictated: "Basically we ship Friday.", edited: "We ship Friday."), ["basically"])
        XCTAssertEqual(
            PersonalFillers.deletions(dictated: "It was, you know, fine.", edited: "It was fine."), ["you know"]
        )
    }

    func testOnlyListedFillersCount() {
        XCTAssertEqual(PersonalFillers.deletions(dictated: "Send the report.", edited: "Send report."), [],
                       "Deleting “the” while editing must not teach VocaMac to drop it")
        XCTAssertEqual(PersonalFillers.deletions(dictated: "It is not done.", edited: "It is done."), [])
    }

    func testRewordingTeachesNothing() {
        XCTAssertEqual(
            PersonalFillers.deletions(dictated: "Actually we ship Friday.", edited: "We ship on Monday."), [],
            "An edit that adds words is rewriting, not removing a filler"
        )
        XCTAssertEqual(
            PersonalFillers.deletions(dictated: "Actually I think we should probably ship it on Friday.", edited: "Ship it."),
            [], "Deleting most of the dictation is rewriting"
        )
    }

    func testExcludedWordsAreNotLearned() {
        XCTAssertEqual(
            PersonalFillers.deletions(dictated: "Basically we ship.", edited: "We ship.") { $0 == "basically" }, []
        )
    }

    func testLearnedFillersAreRemoved() {
        XCTAssertEqual(PersonalFillers.remove(["basically"], from: "Basically, we ship Friday.").text, "We ship Friday.")
        XCTAssertEqual(PersonalFillers.remove(["basically"], from: "It is basically done.").text, "It is done.")
        XCTAssertEqual(PersonalFillers.remove(["actually"], from: "It works, actually.").text, "It works.")
    }

    func testCommaBoundFillersStayWhenTheyAreWords() {
        XCTAssertEqual(PersonalFillers.remove(["like"], from: "I like it.").text, "I like it.")
        XCTAssertEqual(PersonalFillers.remove(["like"], from: "It was, like, huge.").text, "It was, huge.")
        XCTAssertEqual(PersonalFillers.remove(["right"], from: "Turn right at the light.").text, "Turn right at the light.")
        XCTAssertEqual(PersonalFillers.remove(["so"], from: "So, we ship Friday.").text, "We ship Friday.")
        XCTAssertEqual(PersonalFillers.remove(["you know"], from: "You know, it works.").text, "It works.")
    }

    func testUnlistedWordsAreNeverRemoved() {
        XCTAssertEqual(PersonalFillers.remove(["the"], from: "Send the report.").removed, 0)
    }

    // MARK: - Lowercase starts

    func testALowercasedStartIsNoticedAtTheStartOfAMessage() {
        XCTAssertTrue(LearnedCasing.lowercasedStart(dictated: "Sounds good", edited: "sounds good", precedingCharacter: nil))
        XCTAssertTrue(LearnedCasing.lowercasedStart(dictated: "Sounds good", edited: "sounds good", precedingCharacter: "\n"))
    }

    func testALowercasedStartMidSentenceIsAJoinNotAStyle() {
        XCTAssertFalse(LearnedCasing.lowercasedStart(dictated: "Sounds good", edited: "sounds good", precedingCharacter: ","))
        XCTAssertFalse(LearnedCasing.lowercasedStart(dictated: "Sounds good", edited: "sounds good", precedingCharacter: "d"))
    }

    func testOtherEditsAreNotALowercaseStart() {
        XCTAssertFalse(LearnedCasing.lowercasedStart(dictated: "Sounds good", edited: "sounds great", precedingCharacter: nil))
        XCTAssertFalse(LearnedCasing.lowercasedStart(dictated: "sounds good", edited: "sounds good", precedingCharacter: nil))
    }

    func testLowercasingKeepsNamesAndI() {
        let known: (String) -> Bool = { ["sounds", "the", "nasa"].contains($0) }
        XCTAssertEqual(LearnedCasing.lowercasingStart("Sounds good.", isKnownWord: known), "sounds good.")
        XCTAssertEqual(LearnedCasing.lowercasingStart("Priya is here.", isKnownWord: known), "Priya is here.")
        XCTAssertEqual(LearnedCasing.lowercasingStart("I think so.", isKnownWord: known), "I think so.")
        XCTAssertEqual(LearnedCasing.lowercasingStart("NASA called.", isKnownWord: known), "NASA called.")
    }

    func testTheStyleEngineStartsInLowercaseAndCapitalizesLaterSentences() {
        var rules = WritingStyle.plain.defaultRules
        rules.capitalization = .lowercaseStart
        let text = WritingStyleEngine.format(
            "Sounds good. see you then", rules: rules, globalAutoCapitalize: true, globalTrailingSpace: false,
            isKnownWord: { _ in true }
        )
        XCTAssertEqual(text, "sounds good. See you then")
        XCTAssertEqual(
            WritingStyleEngine.format("Sounds good", rules: rules, globalAutoCapitalize: true, globalTrailingSpace: false),
            "Sounds good", "Without a word check the capital stays"
        )
    }

    // MARK: - History

    func testOlderHistoryEntriesDecodeWithoutEditedText() throws {
        let entry = DictationHistoryEntry(modelID: "tiny", audioSeconds: 1)
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        json.removeValue(forKey: "editedText")
        let decoded = try JSONDecoder().decode(DictationHistoryEntry.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.editedText)
        XCTAssertNil(decoded.wasEditedAfterTyping)
    }

    func testEditFreeRateCountsOnlyReadBacks() {
        func entry(_ final: String, edited: String?) -> DictationHistoryEntry {
            DictationHistoryEntry(status: .completed, finalText: final, modelID: "tiny", audioSeconds: 1, editedText: edited)
        }
        let few = [entry("a", edited: "a"), entry("b", edited: nil)]
        XCTAssertNil(CalmEditFreeRate.from(few), "Too few read-backs to say")
        let entries = (0..<4).map { _ in entry("Hi. ", edited: "Hi.") } + [entry("Hi.", edited: "Hello."), entry("x", edited: nil)]
        let rate = CalmEditFreeRate.from(entries)
        XCTAssertEqual(rate, CalmEditFreeRate(unedited: 4, observed: 5))
        XCTAssertEqual(rate?.percent, 80)
    }
}

@MainActor
final class AppStateEditLearningTests: XCTestCase {

    private let messages = RunningAppSnapshot(displayName: "Messages", bundleIdentifier: "com.apple.MobileSMS")

    func testANewInstallLearnsAutomatically() {
        let (appState, _) = AppState.makeTestState()
        XCTAssertEqual(appState.learnCorrectionsMode, .automatic)
    }

    func testAnInstallThatUsesTheDictionaryKeepsSuggest() {
        let (appState, _) = AppState.makeTestState()
        UserDefaults.standard.removeObject(forKey: PreferenceKey.learnModeDefaultSettled)
        UserDefaults.standard.removeObject(forKey: PreferenceKey.learnCorrectionsMode)
        appState.addVocabularyTerm("Priya")
        appState.settleLearnModeDefault()
        XCTAssertEqual(appState.learnCorrectionsMode, .suggest)
        XCTAssertNotNil(UserDefaults.standard.object(forKey: PreferenceKey.learnCorrectionsMode), "Stored, so it stays")
    }

    func testTheDefaultIsSettledOnce() {
        let (appState, _) = AppState.makeTestState()
        // Settled at launch for a new install; adding words later keeps it.
        appState.addVocabularyTerm("Priya")
        appState.settleLearnModeDefault()
        XCTAssertEqual(appState.learnCorrectionsMode, .automatic)
    }

    func testAChosenModeIsKept() {
        let (appState, _) = AppState.makeTestState()
        UserDefaults.standard.removeObject(forKey: PreferenceKey.learnModeDefaultSettled)
        appState.learnCorrectionsMode = .off
        appState.addVocabularyTerm("Priya")
        appState.settleLearnModeDefault()
        XCTAssertEqual(appState.learnCorrectionsMode, .off)
    }

    func testAutomaticLearningOffersUndo() throws {
        let (appState, mocks) = AppState.makeTestState()
        appState.isKnownWord = { word, _ in word != "namratha" && word != "namrata" }
        appState._receiveCorrectionsForTesting([.init(heard: "Namratha", corrected: "Namrata")])
        XCTAssertEqual(appState.vocabularyTerms, ["Namrata"])
        XCTAssertEqual(appState.wordReplacements.map(\.replacement), ["Namrata"])
        XCTAssertEqual(mocks.cursorOverlay.learnedMessages, ["Learned “Namrata”"])

        try XCTUnwrap(mocks.cursorOverlay.learnedUndo)()
        XCTAssertTrue(appState.vocabularyTerms.isEmpty)
        XCTAssertTrue(appState.wordReplacements.isEmpty)
        // Taken back for good: the same fix isn't learned or suggested again.
        appState._receiveCorrectionsForTesting([.init(heard: "Namratha", corrected: "Namrata")])
        XCTAssertTrue(appState.vocabularyTerms.isEmpty)
        XCTAssertTrue(appState.dictionarySuggestions.isEmpty)
    }

    func testUndoKeepsATermThatWasAlreadyListed() throws {
        let (appState, mocks) = AppState.makeTestState()
        appState.addVocabularyTerm("GitHub")
        appState.addWordReplacement(heard: "get hub", replacement: "GitHub")
        appState._receiveCorrectionsForTesting([.init(heard: "git hub", corrected: "GitHub")])
        XCTAssertEqual(appState.wordReplacements.first?.heardForms, ["get hub"], "A listed term isn't learned again")
        XCTAssertTrue(mocks.cursorOverlay.learnedMessages.isEmpty)
    }

    func testOnlyNamesAndTermsAreAddedUnasked() {
        let (appState, mocks) = AppState.makeTestState()
        appState.isKnownWord = { _, _ in true }
        // A plain lowercase word the spell checker knows: suggested instead.
        appState._receiveCorrectionsForTesting([.init(heard: "mane", corrected: "main")])
        XCTAssertTrue(appState.vocabularyTerms.isEmpty)
        XCTAssertEqual(appState.dictionarySuggestions.map(\.corrected), ["main"])
        // Found on screen or in History, not fixed by the user: suggested.
        appState._receiveCorrectionsForTesting([
            .init(heard: "Greptile", corrected: "Greptile", language: "en", source: .frequent),
        ])
        XCTAssertTrue(appState.vocabularyTerms.isEmpty)
        XCTAssertTrue(mocks.cursorOverlay.learnedMessages.isEmpty)
    }

    func testEditedTextIsKeptInHistory() async {
        let (appState, _) = AppState.makeTestState()
        let id = await appState.historyStore.begin(
            audio: nil, target: messages, modelID: "tiny", language: "en", audioSeconds: 1
        )
        appState.historyStore.complete(id, rawText: "basically we ship", finalText: "Basically we ship.", summary: nil,
                                       language: "en", transcriptionSeconds: 0.1, keepAudio: false)
        appState.receiveEdit(DictationEditObservation(
            inserted: "Basically we ship.", editedText: "We ship.", precedingCharacter: nil, historyID: id, app: messages
        ))
        XCTAssertEqual(appState.historyStore.entry(id: id)?.editedText, "We ship.")
        XCTAssertEqual(appState.historyStore.entry(id: id)?.wasEditedAfterTyping, true)
    }

    func testNothingIsReadBackWithLearningOff() async {
        let (appState, _) = AppState.makeTestState()
        appState.learnCorrectionsMode = .off
        let id = await appState.historyStore.begin(
            audio: nil, target: messages, modelID: "tiny", language: "en", audioSeconds: 1
        )
        appState.historyStore.complete(id, rawText: "a", finalText: "A.", summary: nil,
                                       language: "en", transcriptionSeconds: 0.1, keepAudio: false)
        appState.receiveEdit(DictationEditObservation(
            inserted: "A.", editedText: "B.", precedingCharacter: nil, historyID: id, app: messages
        ))
        XCTAssertNil(appState.historyStore.entry(id: id)?.editedText)
    }

    func testAFillerDeletedThreeTimesIsRemovedFromThenOn() async throws {
        let (appState, mocks) = AppState.makeTestState()
        for sentence in ["Basically we ship.", "Basically it works.", "It is basically done."] {
            appState.receiveEdit(DictationEditObservation(
                inserted: sentence, editedText: PersonalFillers.remove(["basically"], from: sentence).text,
                precedingCharacter: nil, app: messages
            ))
        }
        XCTAssertEqual(appState.personalFillers, ["basically"])
        XCTAssertEqual(mocks.cursorOverlay.learnedMessages, ["Learned to leave out “basically”"])
        XCTAssertEqual(appState.dictionaryContext(contextTerms: [], language: "en").removedWords, ["basically"])

        let output = await DictationOutputPipeline(cleaner: MockTranscriptCleanup(), snippets: SnippetExpander()).process(
            "Basically, the build is green.", options: DictationOutputOptions(
                profile: WritingProfile(format: .plain, rules: WritingStyle.plain.defaultRules), snippetList: [],
                cleanupEnabled: false, rewritingEnabled: false, model: .qwen25_0_5b_q4_k_m, customPrompt: "",
                language: "en", autoCapitalize: true, trailingSpace: false,
                dictionary: appState.dictionaryContext(contextTerms: [], language: "en")
            )
        )
        XCTAssertEqual(output.text, "The build is green.")

        // Undo on the overlay keeps the word, for good.
        try XCTUnwrap(mocks.cursorOverlay.learnedUndo)()
        XCTAssertTrue(appState.personalFillers.isEmpty)
        for _ in 0..<3 {
            appState.receiveEdit(DictationEditObservation(
                inserted: "Basically we ship.", editedText: "We ship.", precedingCharacter: nil, app: messages
            ))
        }
        XCTAssertTrue(appState.personalFillers.isEmpty)
    }

    func testRemovingALearnedFillerCanBeUndone() {
        let (appState, _) = AppState.makeTestState()
        appState.personalFillers = ["basically", "honestly"]
        appState.removePersonalFillerWithUndo("basically")
        XCTAssertEqual(appState.personalFillers, ["honestly"])
        appState.undoCenter.undo()
        XCTAssertEqual(appState.personalFillers, ["basically", "honestly"])
    }

    func testLowercasingTheStartThreeTimesLearnsIt() throws {
        let (appState, mocks) = AppState.makeTestState()
        XCTAssertNotEqual(appState.resolveWritingStyle(for: messages).rules.capitalization, .lowercaseStart)
        for _ in 0..<3 {
            appState.receiveEdit(DictationEditObservation(
                inserted: "Sounds good", editedText: "sounds good", precedingCharacter: nil, app: messages
            ))
        }
        XCTAssertEqual(appState.learnedLowercaseApps.map(\.displayName), ["Messages"])
        XCTAssertEqual(appState.resolveWritingStyle(for: messages).rules.capitalization, .lowercaseStart)
        let notes = RunningAppSnapshot(displayName: "Notes", bundleIdentifier: "com.apple.Notes")
        XCTAssertNotEqual(appState.resolveWritingStyle(for: notes).rules.capitalization, .lowercaseStart)
        XCTAssertEqual(mocks.cursorOverlay.learnedMessages, ["Learned to start in lowercase in Messages"])

        let learned = try XCTUnwrap(appState.learnedLowercaseApps.first)
        appState.removeLearnedLowercaseAppWithUndo(learned)
        XCTAssertNotEqual(appState.resolveWritingStyle(for: messages).rules.capitalization, .lowercaseStart)
        appState.undoCenter.undo()
        XCTAssertEqual(appState.resolveWritingStyle(for: messages).rules.capitalization, .lowercaseStart)
    }

    func testLowercasingMidSentenceTeachesNothing() {
        let (appState, _) = AppState.makeTestState()
        for _ in 0..<3 {
            appState.receiveEdit(DictationEditObservation(
                inserted: "Sounds good", editedText: "sounds good", precedingCharacter: ",", app: messages
            ))
        }
        XCTAssertTrue(appState.learnedLowercaseApps.isEmpty)
    }
}
