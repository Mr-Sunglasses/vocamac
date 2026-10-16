// MenuBarIconStyleTests.swift
// VocaMac Tests

import XCTest
@testable import VocaMac

final class MenuBarIconStyleTests: XCTestCase {

    func testIdleUsesSystemMic() {
        XCTAssertEqual(MenuBarIconStyle.style(for: .idle), .systemSymbolTemplate(name: "mic.fill"))
    }

    func testRecordingUsesTintedMark() {
        XCTAssertEqual(MenuBarIconStyle.style(for: .recording), .brandMarkTinted)
    }

    func testProcessingUsesSystemSymbol() {
        XCTAssertEqual(
            MenuBarIconStyle.style(for: .processing),
            .systemSymbol(name: "ellipsis.circle")
        )
    }

    func testCommandModeShowsAWandWhileListeningAndRewriting() {
        XCTAssertEqual(
            MenuBarIconStyle.style(for: .recording, isCommandMode: true),
            .systemSymbol(name: "wand.and.stars")
        )
        XCTAssertEqual(
            MenuBarIconStyle.style(for: .processing, isCommandMode: true),
            .systemSymbol(name: "wand.and.stars")
        )
        // An error or idle state is not Command Mode's to show.
        XCTAssertEqual(MenuBarIconStyle.style(for: .idle, isCommandMode: true), .systemSymbolTemplate(name: "mic.fill"))
    }

    func testErrorUsesSystemSymbol() {
        XCTAssertEqual(
            MenuBarIconStyle.style(for: .error),
            .systemSymbol(name: "exclamationmark.triangle")
        )
    }
}

// MARK: - Glyph States

final class MenuBarGlyphStateTests: XCTestCase {

    func testEveryStyleMapsToTheOverlayBoardStates() {
        XCTAssertEqual(MenuBarGlyphState(style: .style(for: .idle)), .ready)
        XCTAssertEqual(MenuBarGlyphState(style: .style(for: .recording)), .listening)
        XCTAssertEqual(MenuBarGlyphState(style: .style(for: .processing)), .working)
        XCTAssertEqual(MenuBarGlyphState(style: .style(for: .recording, isCommandMode: true)), .commandMode)
        XCTAssertEqual(MenuBarGlyphState(style: .style(for: .error)), .needsAttention)
        XCTAssertEqual(MenuBarGlyphState(style: .style(for: .idle, readiness: .blocked)), .needsAttention)
        XCTAssertEqual(MenuBarGlyphState(style: .style(for: .idle, readiness: .preparing)), .off)
    }

    func testOnlyActiveOrAttentionStatesAreColoured() {
        XCTAssertTrue(MenuBarGlyphState.ready.isTemplate)
        XCTAssertTrue(MenuBarGlyphState.working.isTemplate)
        XCTAssertTrue(MenuBarGlyphState.off.isTemplate)
        XCTAssertFalse(MenuBarGlyphState.listening.isTemplate)
        XCTAssertFalse(MenuBarGlyphState.commandMode.isTemplate)
        XCTAssertFalse(MenuBarGlyphState.needsAttention.isTemplate)
    }

    @MainActor
    func testIconImageIsTheMarkWithRoomForItsBadge() {
        let image = MenuBarIcon.image(for: .needsAttention)
        XCTAssertEqual(image.size, MenuBarIcon.canvasSize)
        XCTAssertFalse(image.isTemplate)
        XCTAssertTrue(MenuBarIcon.image(for: .ready).isTemplate)
    }
}
