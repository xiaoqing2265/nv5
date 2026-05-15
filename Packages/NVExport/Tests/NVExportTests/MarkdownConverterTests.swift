import XCTest
import NVModel
import NVExport

final class MarkdownConverterTests: XCTestCase {

    func testEmptyNote() throws {
        let note = Note(title: "", body: "")
        let content = try MarkdownConverter.convert(note)
        guard case .text(let s) = content else {
            XCTFail("Expected .text case")
            return
        }
        XCTAssertEqual(s, "")
    }

    func testPlainTextNote() throws {
        let note = Note(title: "Test", body: "Plain content")
        let content = try MarkdownConverter.convert(note)
        guard case .text(let s) = content else {
            XCTFail("Expected .text case")
            return
        }
        XCTAssertTrue(s.hasPrefix("# Test"))
        XCTAssertTrue(s.contains("Plain content"))
    }

    func testBoldTextInBody() throws {
        let note = Note(title: "Bold Test", body: "This has bold text")
        let content = try MarkdownConverter.convert(note)
        guard case .text(let s) = content else {
            XCTFail("Expected .text case")
            return
        }
        XCTAssertTrue(s.contains("**"))
    }

    func testChineseTitleAndBody() throws {
        let note = Note(title: "中文标题", body: "这是中文正文内容")
        let content = try MarkdownConverter.convert(note)
        guard case .text(let s) = content else {
            XCTFail("Expected .text case")
            return
        }
        XCTAssertTrue(s.contains("# 中文标题"))
        XCTAssertTrue(s.contains("这是中文正文内容"))
    }

    func testEmojiInNote() throws {
        let note = Note(title: "📝 Emoji", body: "Hello 🎉🎊")
        let content = try MarkdownConverter.convert(note)
        guard case .text(let s) = content else {
            XCTFail("Expected .text case")
            return
        }
        XCTAssertTrue(s.contains("📝"))
        XCTAssertTrue(s.contains("🎉"))
    }
}