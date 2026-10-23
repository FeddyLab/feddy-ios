import XCTest
@testable import Feddy

final class ReplyPopupPickerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func conversation(
        _ id: String,
        lastSeq: Int = 4,
        seenSeq: Int = 2,
        daysAgo: Double = 1,
        author: String? = "teammate",
        status: String = "open"
    ) -> ConversationSummary {
        ConversationSummary(
            id: id,
            subject: nil,
            status: status,
            lastSeq: lastSeq,
            lastMessageAt: now.addingTimeInterval(-daysAgo * 86_400),
            seenSeq: seenSeq,
            lastMessage: "Reply in \(id)",
            lastAuthorType: author,
            lastAuthorName: "Yu"
        )
    }

    func testPicksNewestUnreadReplyAndCountsTheRest() {
        let list = [
            conversation("older", daysAgo: 3),
            conversation("newest", daysAgo: 0.5),
            conversation("read", lastSeq: 4, seenSeq: 4, daysAgo: 0.1),
        ]
        let pick = ReplyPopupPicker.pick(from: list, shown: [:], now: now)
        XCTAssertEqual(pick?.conversationId, "newest")
        XCTAssertEqual(pick?.message, "Reply in newest")
        XCTAssertEqual(pick?.otherCount, 1)
        XCTAssertEqual(pick?.surfaced, ["older": 4, "newest": 4])
    }

    func testEachReplyPopsOnce() {
        let list = [conversation("a", lastSeq: 4)]
        XCTAssertNil(ReplyPopupPicker.pick(from: list, shown: ["a": 4], now: now))
        // A later reply in the same thread is new again.
        let later = [conversation("a", lastSeq: 6)]
        XCTAssertEqual(
            ReplyPopupPicker.pick(from: later, shown: ["a": 4], now: now)?.conversationId, "a"
        )
    }

    func testOnlyRepliesFromTheLastFourteenDays() {
        let list = [conversation("stale", daysAgo: 14.5), conversation("recent", daysAgo: 13.5)]
        let pick = ReplyPopupPicker.pick(from: list, shown: [:], now: now)
        XCTAssertEqual(pick?.conversationId, "recent")
        XCTAssertEqual(pick?.otherCount, 0)
        XCTAssertNil(ReplyPopupPicker.pick(from: [list[0]], shown: [:], now: now))
    }

    func testIgnoresThreadsWhereTheUserSpokeLast() {
        let list = [conversation("mine", author: "contact"), conversation("unknown", author: nil)]
        XCTAssertNil(ReplyPopupPicker.pick(from: list, shown: [:], now: now))
    }

    func testClosedThreadsAndBotRepliesStillPop() {
        let closed = [conversation("closed", status: "closed")]
        XCTAssertEqual(ReplyPopupPicker.pick(from: closed, shown: [:], now: now)?.conversationId, "closed")
        let bot = [conversation("bot", author: "bot")]
        XCTAssertEqual(ReplyPopupPicker.pick(from: bot, shown: [:], now: now)?.conversationId, "bot")
    }

    func testShownThreadsStillCountInTheTotal() {
        let list = [conversation("seen-card", daysAgo: 2), conversation("fresh", daysAgo: 1)]
        let pick = ReplyPopupPicker.pick(from: list, shown: ["seen-card": 4], now: now)
        XCTAssertEqual(pick?.conversationId, "fresh")
        XCTAssertEqual(pick?.otherCount, 1)
    }

    func testRecordMarksEverySurfacedThreadAndDropsUnlisted() {
        let list = [conversation("a", lastSeq: 5), conversation("b", lastSeq: 3)]
        let pick = ReplyPopupPicker.pick(from: list, shown: [:], now: now)
        let next = ReplyPopupPicker.record(pick, into: ["gone": 9, "a": 2], listed: list)
        XCTAssertEqual(next, ["a": 5, "b": 3])
        XCTAssertNil(ReplyPopupPicker.pick(from: list, shown: next, now: now))
    }
}
