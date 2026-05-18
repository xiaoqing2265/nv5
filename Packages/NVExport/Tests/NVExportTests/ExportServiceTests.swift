import XCTest
@testable import NVExport
import NVModel

final class ExportServiceTests: XCTestCase {

    func testRenderMarkdownReturnsText() throws {
        let note = Note(title: "Hello", body: "World")
        let service = ExportService()
        let content = try service.render(note: note, as: .markdown)
        guard case .text(let s) = content else {
            XCTFail("Expected .text")
            return
        }
        XCTAssertTrue(s.contains("Hello"))
        XCTAssertTrue(s.contains("World"))
    }

    func testRenderPlainTextReturnsText() throws {
        let note = Note(title: "Hello", body: "World")
        let service = ExportService()
        let content = try service.render(note: note, as: .plainText)
        guard case .text(let s) = content else {
            XCTFail("Expected .text")
            return
        }
        XCTAssertTrue(s.contains("World"))
    }

    func testRenderRichTextReturnsRtfData() throws {
        let note = Note(title: "Hello", body: "World")
        let service = ExportService()
        let content = try service.render(note: note, as: .richText)
        guard case .rtfData(let data) = content else {
            XCTFail("Expected .rtfData")
            return
        }
        XCTAssertFalse(data.isEmpty)
    }

    func testRenderEmptyNote() throws {
        let note = Note(title: "", body: "")
        let service = ExportService()
        let content = try service.render(note: note, as: .markdown)
        guard case .text(let s) = content else {
            XCTFail("Expected .text")
            return
        }
        XCTAssertEqual(s, "")
    }
}
