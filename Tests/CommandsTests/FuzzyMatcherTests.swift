import XCTest
import NV5

final class FuzzyMatcherTests: XCTestCase {

    func test_title_contains_full_match() {
        let score = FuzzyMatcher.score(
            query: "导出",
            title: "导出到文件",
            keywords: ["export", "save", "导出"],
            subtitle: nil
        )
        XCTAssertNotNil(score)
        XCTAssertEqual(score, 1.0)
    }

    func test_keywords_match() {
        let score = FuzzyMatcher.score(
            query: "export",
            title: "导出到文件",
            keywords: ["export", "save", "导出"],
            subtitle: nil
        )
        XCTAssertNotNil(score)
        XCTAssertEqual(score, 0.5)
    }

    func test_subsequence_partial_match() {
        let score = FuzzyMatcher.score(
            query: "复制md",
            title: "复制为 Markdown",
            keywords: ["copy", "markdown", "md"],
            subtitle: nil
        )
        XCTAssertNotNil(score)
    }

    func test_no_match_returns_nil() {
        let score = FuzzyMatcher.score(
            query: "xyzabc",
            title: "新建笔记",
            keywords: ["new", "新建", "create"],
            subtitle: nil
        )
        XCTAssertNil(score)
    }

    func test_empty_query_returns_nil() {
        let score = FuzzyMatcher.score(
            query: "",
            title: "新建笔记",
            keywords: ["new", "新建", "create"],
            subtitle: nil
        )
        XCTAssertNil(score)
    }

    func test_consecutive_chars_score_higher() {
        let score1 = FuzzyMatcher.score(
            query: "新建",
            title: "新建笔记",
            keywords: [],
            subtitle: nil
        )
        let score2 = FuzzyMatcher.score(
            query: "新记",
            title: "新建笔记",
            keywords: [],
            subtitle: nil
        )
        XCTAssertNotNil(score1)
        XCTAssertNotNil(score2)
        XCTAssertEqual(score1, 1.0)
        XCTAssertLessThan(score2!, 1.0)
    }

    func test_subtitle_low_weight() {
        let score = FuzzyMatcher.score(
            query: "剪贴板",
            title: "复制为 Markdown",
            keywords: ["copy", "markdown", "md"],
            subtitle: "将当前笔记转为 Markdown 写入剪贴板"
        )
        XCTAssertNotNil(score)
        XCTAssertLessThanOrEqual(score!, 0.3)
    }
}
