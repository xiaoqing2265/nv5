import XCTest
import NVModel
import NVExport

final class PlainTextConverterTests: XCTestCase {

    func testEmptyNote() throws {
        let note = Note(title: "", body: "")
        let content = try PlainTextConverter.convert(note)
        guard case .text(let s) = content else {
            XCTFail("Expected .text case")
            return
        }
        XCTAssertEqual(s, "")
    }

    func testTitleOnlyNote() throws {
        let note = Note(title: "Test Title", body: "")
        let content = try PlainTextConverter.convert(note)
        guard case .text(let s) = content else {
            XCTFail("Expected .text case")
            return
        }
        XCTAssertEqual(s, "Test Title\n\n")
    }

    func testBodyOnlyNote() throws {
        let note = Note(title: "", body: "Hello World")
        let content = try PlainTextConverter.convert(note)
        guard case .text(let s) = content else {
            XCTFail("Expected .text case")
            return
        }
        XCTAssertEqual(s, "Hello World")
    }

    func testFullNote() throws {
        let note = Note(title: "My Note", body: "Some content here")
        let content = try PlainTextConverter.convert(note)
        guard case .text(let s) = content else {
            XCTFail("Expected .text case")
            return
        }
        XCTAssertEqual(s, "My Note\n\nSome content here")
    }

    func testMixedChineseAndEnglish() throws {
        let note = Note(title: "中文标题 Chinese", body: "正文内容 Body content 123")
        let content = try PlainTextConverter.convert(note)
        guard case .text(let s) = content else {
            XCTFail("Expected .text case")
            return
        }
        XCTAssertTrue(s.contains("中文标题"))
        XCTAssertTrue(s.contains("正文内容"))
    }

    func testEmojiContent() throws {
        let note = Note(title: "Emoji 📝", body: "Hello 👋🎉")
        let content = try PlainTextConverter.convert(note)
        guard case .text(let s) = content else {
            XCTFail("Expected .text case")
            return
        }
        XCTAssertTrue(s.contains("📝"))
        XCTAssertTrue(s.contains("👋"))
    }
}