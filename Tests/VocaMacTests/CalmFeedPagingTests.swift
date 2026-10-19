// CalmFeedPagingTests.swift
// VocaMac
//
// Home builds rows for one page of history at a time. These checks don't
// time anything, so they hold on any machine (CalmPerformanceTests covers
// timing on request).

import XCTest
@testable import VocaMac

final class CalmFeedPagingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    /// `count` entries, newest first, eight per day.
    private func history(_ count: Int) -> [DictationHistoryEntry] {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        return (0..<count).map { index in
            DictationHistoryEntry(createdAt: start.addingTimeInterval(-Double(index) * 3 * 3600), modelID: "m", audioSeconds: 1)
        }
    }

    func testFirstPageHoldsOnlyPageSizeEntries() {
        let entries = history(5_000)
        let page = CalmFeedDay.page(entries, limit: CalmPaging.pageSize, calendar: calendar)
        XCTAssertEqual(page.reduce(0) { $0 + $1.entries.count }, CalmPaging.pageSize)
        XCTAssertEqual(page.first?.entries.first?.id, entries.first?.id, "The newest entry comes first")
    }

    func testEachMorePageAddsTheNextEntriesInOrder() {
        let entries = history(5_000)
        let two = CalmFeedDay.page(entries, limit: CalmPaging.pageSize * 2, calendar: calendar)
        let shown = two.flatMap(\.entries).map(\.id)
        XCTAssertEqual(shown, entries.prefix(CalmPaging.pageSize * 2).map(\.id))
    }

    func testADaySplitAcrossPagesStaysOneGroup() {
        let entries = history(60)
        let page = CalmFeedDay.page(entries, limit: 12, calendar: calendar)
        let days = page.map(\.day)
        XCTAssertEqual(days, Array(NSOrderedSet(array: days)) as? [Date], "No day appears twice")
        XCTAssertEqual(page.reduce(0) { $0 + $1.entries.count }, 12)
    }

    func testShortHistoryAndEmptyLimits() {
        XCTAssertEqual(CalmFeedDay.page(history(10), limit: 50, calendar: calendar).reduce(0) { $0 + $1.entries.count }, 10)
        XCTAssertTrue(CalmFeedDay.page(history(10), limit: 0, calendar: calendar).isEmpty)
        XCTAssertTrue(CalmFeedDay.page([], limit: 50, calendar: calendar).isEmpty)
    }
}
