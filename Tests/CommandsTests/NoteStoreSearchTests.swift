import XCTest
@testable import NVModel
@testable import NVStore

@MainActor
final class NoteStoreSearchTests: XCTestCase {

    private var tempDBURL: URL!
    private var store: NoteStore!

    override func setUp() async throws {
        try await super.setUp()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("NV5Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDBURL = tempDir.appendingPathComponent("notes.sqlite")
        let database = try Database(url: tempDBURL)
        store = NoteStore(database: database)
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDBURL.deletingLastPathComponent())
        try await super.tearDown()
    }

    private func insertNotes(_ notes: [Note]) async throws {
        for note in notes {
            try await store.upsert(note)
        }
        try await waitForStore(expectedCount: notes.count)
    }

    private func waitForStore(expectedCount: Int, timeout: TimeInterval = 2) async {
        let start = Date()
        while store.notes.count < expectedCount, Date().timeIntervalSince(start) < timeout {
            await Task.yield()
        }
    }

    // MARK: - Empty query

    func test_empty_query_returns_all_notes() async throws {
        let notes = (0..<3).map { i in Note(title: "Note \(i)", body: "body") }
        try await insertNotes(notes)

        let result = store.search(query: "")
        XCTAssertEqual(result.count, 3)
    }

    func test_empty_query_clears_cache() async throws {
        let note = Note(title: "Alpha")
        try await insertNotes([note])

        _ = store.search(query: "Alpha") // populate cache
        _ = store.search(query: "")       // should clear cache
        let result = store.search(query: "Alpha") // should re-search all notes
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - Title matching

    func test_title_match_returns_note() async throws {
        let note = Note(title: "Meeting Notes", body: "discussed budget")
        try await insertNotes([note])

        let result = store.search(query: "Meeting")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, note.id)
    }

    func test_title_match_is_case_insensitive() async throws {
        let note = Note(title: "Project Plan", body: "details")
        try await insertNotes([note])

        let result = store.search(query: "project")
        XCTAssertEqual(result.count, 1)
    }

    func test_title_match_ranks_higher_than_body_match() async throws {
        let titleHit = Note(title: "Budget Report", body: "nothing here")
        let bodyHit = Note(title: "Random File", body: "budget allocation")
        try await insertNotes([titleHit, bodyHit])

        let result = store.search(query: "budget")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.id, titleHit.id, "Title match should rank first")
    }

    func test_title_match_with_all_tokens() async throws {
        let note = Note(title: "SwiftUI Performance Tips", body: "some details")
        try await insertNotes([note])

        let result = store.search(query: "swiftui performance")
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - Body matching

    func test_body_match_returns_note() async throws {
        let note = Note(title: "Unrelated", body: "the secret password is alpha")
        try await insertNotes([note])

        let result = store.search(query: "password")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, note.id)
    }

    // MARK: - Label matching

    func test_label_match_returns_note() async throws {
        var note = Note(title: "Tagged Note", body: "body")
        note.labels = ["work", "important"]
        try await insertNotes([note])

        let result = store.search(query: "work")
        XCTAssertEqual(result.count, 1)
    }

    func test_label_match_is_case_insensitive() async throws {
        var note = Note(title: "Note", body: "body")
        note.labels = ["Urgent"]
        try await insertNotes([note])

        let result = store.search(query: "urgent")
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - Multi-token search

func test_multi_token_search_requires_all_tokens() async throws {
    let match = Note(title: "SwiftUI Guide", body: "iOS development tips")
    let partial = Note(title: "SwiftUI Only", body: "no reference here")
    try await insertNotes([match, partial])

    let result = store.search(query: "swiftui guide")
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result.first?.id, match.id)
}

    func test_no_match_returns_empty() async throws {
        let note = Note(title: "Hello World", body: "foo bar")
        try await insertNotes([note])

        let result = store.search(query: "nonexistent")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Incremental search caching

    func test_incremental_search_uses_cache_when_query_is_prefix() async throws {
        let note1 = Note(title: "foobar")
        let note2 = Note(title: "foobaz")
        let note3 = Note(title: "other")
        try await insertNotes([note1, note2, note3])

        let first = store.search(query: "foo")
        XCTAssertEqual(first.count, 2)

        // "foobar" is a prefix extension of "foo" — should use cached results
        let second = store.search(query: "foobar")
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.id, note1.id)
    }

    func test_incremental_search_falls_back_to_full_scan_when_not_prefix() async throws {
        let note1 = Note(title: "abcdef")
        let note2 = Note(title: "xyzabc")
        try await insertNotes([note1, note2])

        _ = store.search(query: "abc")
        // "xyz" is NOT a prefix of "abc" — should fall back to full scan
        let result = store.search(query: "xyz")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, note2.id)
    }

    // MARK: - Cache invalidation on note count change

    func test_cache_invalidates_when_note_added() async throws {
        let note1 = Note(title: "alpha")
        try await insertNotes([note1])
        _ = store.search(query: "alpha")
        XCTAssertEqual(store.search(query: "alpha").count, 1)

        let note2 = Note(title: "beta")
        try await insertNotes([note2])

        // wait for observation to fire with new count
        try await waitForStore(expectedCount: 2)

        let cachedSearch = store.search(query: "alpha")
        XCTAssertEqual(cachedSearch.count, 1, "Cache should have been cleared on count change, re-search succeeds")
    }

    // MARK: - noteTitlePrefixedBy

    func test_noteTitlePrefixedBy_empty_prefix_returns_nil() {
        let result = store.noteTitlePrefixedBy("")
        XCTAssertNil(result)
    }

    func test_noteTitlePrefixedBy_no_match_returns_nil() async throws {
        let note = Note(title: "Hello World")
        try await insertNotes([note])
        let result = store.noteTitlePrefixedBy("xyz")
        XCTAssertNil(result)
    }

    func test_noteTitlePrefixedBy_returns_shortest_match() async throws {
        let long = Note(title: "foobarbaz")
        let short = Note(title: "foobar")
        try await insertNotes([long, short])
        let result = store.noteTitlePrefixedBy("foo")
        XCTAssertEqual(result, "foobar", "Should return shortest matching title")
    }

    func test_noteTitlePrefixedBy_is_case_insensitive() async throws {
        let note = Note(title: "Project Plan")
        try await insertNotes([note])
        let result = store.noteTitlePrefixedBy("project")
        XCTAssertEqual(result, "Project Plan")
    }
}
