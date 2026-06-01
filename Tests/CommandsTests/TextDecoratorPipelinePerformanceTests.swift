import AppKit
import XCTest
@testable import NV5

@MainActor
final class TextDecoratorPipelinePerformanceTests: XCTestCase {
    func testInteractiveDecoratorSkipsHTTPLinkDetection() {
        let storage = NSTextStorage(string: makeURLHeavyText(targetBytes: 100_000))

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            TextDecoratorPipeline.runInteractive(on: storage)
        }

        let fullRange = NSRange(location: 0, length: storage.length)
        var foundHTTPLink = false
        storage.enumerateAttribute(.link, in: fullRange) { value, _, stop in
            if let url = value as? URL, url.scheme?.hasPrefix("http") == true {
                foundHTTPLink = true
                stop.pointee = true
            }
        }
        XCTAssertFalse(foundHTTPLink)
    }

    func testFullDecoratorDetectsHTTPLinks() {
        let prefix = "Visit "
        let storage = NSTextStorage(string: "\(prefix)https://example.com for details")

        TextDecoratorPipeline.runAll(on: storage)

        let link = storage.attribute(.link, at: prefix.utf16.count, effectiveRange: nil) as? URL
        XCTAssertEqual(link?.absoluteString, "https://example.com")
    }

    func testRunAllURLHeavyPerformance_100KB() {
        let storage = NSTextStorage(string: makeURLHeavyText(targetBytes: 100_000))

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            TextDecoratorPipeline.runAll(on: storage)
        }
    }

    private func makeURLHeavyText(targetBytes: Int) -> String {
        var text = "# Heading\n"
        var index = 0
        while text.utf8.count < targetBytes {
            text += "Line \(index) https://example.com/\(index) [[Wiki \(index)]] [done]\n"
            index += 1
        }
        return text
    }
}
