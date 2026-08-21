import XCTest
@testable import Feddy

final class ModelsTests: XCTestCase {
    func testDecodesConversationDetail() throws {
        let json = """
        {
          "id": "conv-1",
          "status": "open",
          "subject": "Widget will not open",
          "last_seq": 2,
          "meta": null,
          "parts": [
            { "seq": 1, "author_type": "contact", "body": "Hello", "created_at": "2026-08-19T07:01:02.123Z" },
            { "seq": 2, "author_type": "teammate", "body": "Hi!", "created_at": "2026-08-19T07:05:00Z",
              "author_name": "Yu", "author_avatar_url": "https://example.com/yu.png" }
          ]
        }
        """
        let detail = try FeddyDecoding.decoder()
            .decode(ConversationDetail.self, from: Data(json.utf8))
        XCTAssertEqual(detail.lastSeq, 2)
        XCTAssertEqual(detail.parts.count, 2)
        XCTAssertTrue(detail.parts[0].isFromContact)
        XCTAssertNil(detail.parts[0].authorName)
        XCTAssertFalse(detail.parts[1].isFromContact)
        XCTAssertEqual(detail.parts[1].authorName, "Yu")
        XCTAssertEqual(detail.parts[1].authorAvatarUrl, "https://example.com/yu.png")
        XCTAssertNotEqual(detail.parts[0].authorRunKey, detail.parts[1].authorRunKey)
    }

    func testDecodesConversationListWithUnread() throws {
        let json = """
        {
          "conversations": [
            {
              "id": "conv-1",
              "subject": "Hello",
              "status": "pending",
              "last_seq": 3,
              "last_message_at": "2026-08-19T07:00:00.000Z",
              "seen_seq": 1
            }
          ]
        }
        """
        let list = try FeddyDecoding.decoder()
            .decode(ConversationList.self, from: Data(json.utf8))
        XCTAssertEqual(list.conversations.count, 1)
        XCTAssertTrue(list.conversations[0].hasUnread)
    }

    func testRejectsMalformedDates() {
        let json = """
        { "unread_count": 1 }
        """
        XCTAssertNoThrow(
            try FeddyDecoding.decoder().decode(UnreadCount.self, from: Data(json.utf8))
        )
    }
}

final class AttributeSanitizationTests: XCTestCase {
    func testKeepsScalarsAndConvertsDates() {
        let input: [String: Any] = [
            "plan": "pro",
            "is_member": true,
            "credits_left": 42,
            "score": 4.5,
            "trial_ends_at": Date(timeIntervalSince1970: 1_755_600_000),
            "nested": ["not": "allowed"],
        ]
        let sanitized = APIClient.sanitizeAttributes(input)
        XCTAssertEqual(sanitized["plan"] as? String, "pro")
        XCTAssertEqual(sanitized["is_member"] as? Bool, true)
        XCTAssertEqual(sanitized["credits_left"] as? Int, 42)
        XCTAssertEqual(sanitized["score"] as? Double, 4.5)
        XCTAssertTrue((sanitized["trial_ends_at"] as? String)?.hasPrefix("2025") == true)
        XCTAssertNil(sanitized["nested"])
        XCTAssertTrue(JSONSerialization.isValidJSONObject(sanitized))
    }
}

final class EmailValidationTests: XCTestCase {
    func testAcceptsAndRejects() {
        XCTAssertTrue(EmailValidation.isValid("user@example.com"))
        XCTAssertTrue(EmailValidation.isValid("a.b+c@sub.domain.io"))
        XCTAssertFalse(EmailValidation.isValid("nope"))
        XCTAssertFalse(EmailValidation.isValid("a b@example.com"))
        XCTAssertFalse(EmailValidation.isValid("user@nodot"))
    }
}

final class DeviceContextTests: XCTestCase {
    func testContextCarriesSharedKeys() {
        let context = DeviceContext.build()
        XCTAssertEqual(context["sdk_version"], DeviceContext.sdkVersion)
        XCTAssertNotNil(context["locale"])
        XCTAssertNotNil(context["os_version"])
        XCTAssertFalse(DeviceContext.modelIdentifier().isEmpty)
    }
}

final class BrandColorTests: XCTestCase {
    func testParsesShorthandAndPrefixedHex() {
        XCTAssertEqual(RGB(hex: "#fff"), RGB(hex: "FFFFFF"))
        XCTAssertEqual(RGB(hex: " #000000 ")?.luminance, 0)
    }

    func testRejectsMalformedHex() {
        XCTAssertNil(RGB(hex: "12345"))
        XCTAssertNil(RGB(hex: "gggggg"))
    }

    func testLightBrandColoursAskForDarkText() {
        XCTAssertTrue(RGB(hex: "#FFEB3B")!.needsDarkText)
        XCTAssertTrue(RGB(hex: "#FFFFFF")!.needsDarkText)
        XCTAssertFalse(RGB(hex: "#6366F1")!.needsDarkText)
        XCTAssertFalse(RGB(hex: "#000000")!.needsDarkText)
    }
}
