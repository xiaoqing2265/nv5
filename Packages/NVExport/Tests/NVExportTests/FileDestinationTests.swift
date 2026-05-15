import XCTest
import NVModel
import NVExport

final class FileDestinationTests: XCTestCase {

    func testWriteTextFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let content = ExportContent.text("Hello World")
        let url = try await FileDestination.write(
            content: content,
            suggestedName: "test-file",
            format: .plainText,
            in: tempDir
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let written = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(written, "Hello World")
    }

    func testDuplicateFilenameResolution() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let content = ExportContent.text("First")
        let url1 = try await FileDestination.write(
            content: content,
            suggestedName: "duplicate",
            format: .plainText,
            in: tempDir
        )

        let content2 = ExportContent.text("Second")
        let url2 = try await FileDestination.write(
            content: content2,
            suggestedName: "duplicate",
            format: .plainText,
            in: tempDir
        )

        XCTAssertTrue(url1.path.contains("-2.txt"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url1.path.replacingOccurrences(of: "-2.txt", with: ".txt")))
    }

    func testSanitizeFilename() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let content = ExportContent.text("Content")
        let url = try await FileDestination.write(
            content: content,
            suggestedName: "test/file:name",
            format: .markdown,
            in: tempDir
        )

        XCTAssertFalse(url.lastPathComponent.contains("/"))
        XCTAssertFalse(url.lastPathComponent.contains(":"))
        XCTAssertTrue(url.path.contains(".md"))
    }
}