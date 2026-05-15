import XCTest
import NVModel
import NVExport

final class RichTextConverterTests: XCTestCase {

    func testPlainTextNote() throws {
        let note = Note(title: "RTF Test", body: "Plain content")
        let content = try RichTextConverter.convert(note)
        guard case .rtfData(let d) = content else {
            XCTFail("Expected .rtfData case")
            return
        }
        XCTAssertFalse(d.isEmpty)
    }

    func testEmptyBodyNote() throws {
        let note = Note(title: "Empty Body", body: "")
        let content = try RichTextConverter.convert(note)
        guard case .rtfData(let d) = content else {
            XCTFail("Expected .rtfData case")
            return
        }
        XCTAssertFalse(d.isEmpty)
    }

    func testChineseContent() throws {
        let note = Note(title: "中文标题", body: "这是中文正文内容")
        let content = try RichTextConverter.convert(note)
        guard case .rtfData(let d) = content else {
            XCTFail("Expected .rtfData case")
            return
        }
        XCTAssertFalse(d.isEmpty)
    }

    func testEmojiContent() throws {
        let note = Note(title: "📝 Emoji", body: "Hello 🎉🎊")
        let content = try RichTextConverter.convert(note)
        guard case .rtfData(let d) = content else {
            XCTFail("Expected .rtfData case")
            return
        }
        XCTAssertFalse(d.isEmpty)
    }

    func testByteCount() throws {
        let note = Note(title: "Test", body: "Content here")
        let content = try RichTextConverter.convert(note)
        XCTAssertGreaterThan(content.byteCount, 0)
    }
}