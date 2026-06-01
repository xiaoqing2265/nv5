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

        let result = await store.search(query: "")
        XCTAssertEqual(result.count, 3)
    }

    func test_empty_query_clears_cache() async throws {
        let note = Note(title: "Alpha")
        try await insertNotes([note])

        _ = await store.search(query: "Alpha") // populate cache
        _ = await store.search(query: "")       // should clear cache
        let result = await store.search(query: "Alpha") // should re-search all notes
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - Title matching

    func test_title_match_returns_note() async throws {
        let note = Note(title: "Meeting Notes", body: "discussed budget")
        try await insertNotes([note])

        let result = await store.search(query: "Meeting")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, note.id)
    }

    func test_title_match_is_case_insensitive() async throws {
        let note = Note(title: "Project Plan", body: "details")
        try await insertNotes([note])

        let result = await store.search(query: "project")
        XCTAssertEqual(result.count, 1)
    }

    func test_title_match_ranks_higher_than_body_match() async throws {
        let titleHit = Note(title: "Budget Report", body: "nothing here")
        let bodyHit = Note(title: "Random File", body: "budget allocation")
        try await insertNotes([titleHit, bodyHit])

        let result = await store.search(query: "budget")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.id, titleHit.id, "Title match should rank first")
    }

    func test_title_match_with_all_tokens() async throws {
        let note = Note(title: "SwiftUI Performance Tips", body: "some details")
        try await insertNotes([note])

        let result = await store.search(query: "swiftui performance")
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - Body matching

    func test_body_match_returns_note() async throws {
        let note = Note(title: "Unrelated", body: "the secret password is alpha")
        try await insertNotes([note])

        let result = await store.search(query: "password")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, note.id)
    }

    // MARK: - Label matching

    func test_label_match_returns_note() async throws {
        var note = Note(title: "Tagged Note", body: "body")
        note.labels = ["work", "important"]
        try await insertNotes([note])

        let result = await store.search(query: "work")
        XCTAssertEqual(result.count, 1)
    }

    func test_label_match_is_case_insensitive() async throws {
        var note = Note(title: "Note", body: "body")
        note.labels = ["Urgent"]
        try await insertNotes([note])

        let result = await store.search(query: "urgent")
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - Multi-token search

    func test_multi_token_search_requires_all_tokens() async throws {
        let match = Note(title: "SwiftUI Guide", body: "iOS development tips")
        let partial = Note(title: "SwiftUI Only", body: "no reference here")
        try await insertNotes([match, partial])

        let result = await store.search(query: "swiftui guide")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, match.id)
    }

    func test_no_match_returns_empty() async throws {
        let note = Note(title: "Hello World", body: "foo bar")
        try await insertNotes([note])

        let result = await store.search(query: "nonexistent")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Incremental search caching

    func test_incremental_search_uses_cache_when_query_is_prefix() async throws {
        let note1 = Note(title: "foobar")
        let note2 = Note(title: "foobaz")
        let note3 = Note(title: "other")
        try await insertNotes([note1, note2, note3])

        let first = await store.search(query: "foo")
        XCTAssertEqual(first.count, 2)

        // "foobar" is a prefix extension of "foo" — should use cached results
        let second = await store.search(query: "foobar")
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.id, note1.id)
    }

    func test_incremental_search_falls_back_to_full_scan_when_not_prefix() async throws {
        let note1 = Note(title: "abcdef")
        let note2 = Note(title: "xyzabc")
        try await insertNotes([note1, note2])

        _ = await store.search(query: "abc")
        // "xyz" is NOT a prefix of "abc" — should fall back to full scan
        let result = await store.search(query: "xyz")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, note2.id)
    }

    // MARK: - Cache invalidation on note count change

    func test_cache_invalidates_when_note_added() async throws {
        let note1 = Note(title: "alpha")
        try await insertNotes([note1])
        _ = await store.search(query: "alpha")
        let check = await store.search(query: "alpha")
        XCTAssertEqual(check.count, 1)

        let note2 = Note(title: "beta")
        try await insertNotes([note2])

        // wait for observation to fire with new count
        try await waitForStore(expectedCount: 2)

        let cachedSearch = await store.search(query: "alpha")
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

    // MARK: - updateBodyText vs updateBody contract

    func test_updateBodyText_preserves_existing_bodyAttributes() async throws {
        var note = Note(title: "Test Note", body: "original body")
        note.bodyAttributes = Data([0x01, 0x02, 0x03])
        try await insertNotes([note])

        // 完整数据只在 DB：内存 store.notes 是摘要投影（body 截断、bodyAttributes 为 NULL），
        // 验证持久化必须直接查库。
        let beforeUpdate = await store.fullNote(id: note.id)
        XCTAssertNotNil(beforeUpdate?.bodyAttributes, "bodyAttributes should be set initially")

        try await store.updateBodyText(id: note.id, body: "updated body", selection: NSRange(location: 0, length: 5))

        let afterUpdate = await store.fullNote(id: note.id)
        XCTAssertEqual(afterUpdate?.body, "updated body", "body should be updated")
        XCTAssertEqual(afterUpdate?.lastSelectedRange, NSRange(location: 0, length: 5), "selection should be updated")
        XCTAssertNotNil(afterUpdate?.bodyAttributes, "bodyAttributes should remain unchanged after updateBodyText")
        XCTAssertEqual(afterUpdate?.bodyAttributes, Data([0x01, 0x02, 0x03]), "bodyAttributes should preserve original value")
    }

    func test_updateBody_overwrites_attributes_as_before() async throws {
        var note = Note(title: "Test Note", body: "original body")
        note.bodyAttributes = Data([0x01, 0x02, 0x03])
        try await insertNotes([note])

        let beforeUpdate = await store.fullNote(id: note.id)
        XCTAssertNotNil(beforeUpdate?.bodyAttributes)

        // updateBody with new attributes should overwrite
        try await store.updateBody(id: note.id, body: "new body", attributes: Data([0x04, 0x05]), selection: NSRange(location: 0, length: 3))

        let afterUpdate = await store.fullNote(id: note.id)
        XCTAssertEqual(afterUpdate?.body, "new body")
        XCTAssertEqual(afterUpdate?.bodyAttributes, Data([0x04, 0x05]), "attributes should be overwritten")
    }

    func test_updateBody_sets_attributes_to_nil() async throws {
        var note = Note(title: "Test Note", body: "original body")
        note.bodyAttributes = Data([0x01, 0x02])
        try await insertNotes([note])

        // updateBody with nil attributes should clear them
        try await store.updateBody(id: note.id, body: "new body", attributes: nil, selection: nil)

        // 查库验证：store.notes 摘要的 bodyAttributes 恒为 NULL，无法区分「真清空」与「投影掩盖」。
        let afterUpdate = await store.fullNote(id: note.id)
        XCTAssertEqual(afterUpdate?.body, "new body")
        XCTAssertNil(afterUpdate?.bodyAttributes, "attributes should be set to nil")
    }

    // MARK: - Body truncation in summary projection

    func test_summary_observation_truncates_body_to_200_chars() async throws {
        // Create a note with body much longer than 200 chars
        let longBody = String(repeating: "x", count: 500)
        let note = Note(title: "Long Note", body: longBody)
        try await insertNotes([note])

        let observed = store.notes.first { $0.id == note.id }
        XCTAssertNotNil(observed)
        XCTAssertEqual(observed?.body.count, 200, "observed body should be truncated to 200 chars")
        // bodyAttributes 不再需要运行时断言：NoteSummary 类型本身就不含该字段（编译期保证）。
    }

    func test_search_finds_text_beyond_200_chars_via_db() async throws {
        // Create a note where the match token appears after char 200
        let beforeMatch = String(repeating: "x", count: 250)
        let matchToken = "uniqueSearchToken"
        let body = beforeMatch + matchToken
        let note = Note(title: "Unrelated Title", body: body)
        try await insertNotes([note])

        // The in-memory projection only has first 200 chars (no matchToken)
        let projected = store.notes.first { $0.id == note.id }
        XCTAssertFalse(projected?.body.contains(matchToken) ?? false, "projected body should not contain match token")

        // But database search should still find it via LIKE over full body
        let results = await store.search(query: matchToken)
        XCTAssertEqual(results.count, 1, "search should find note via DB LIKE despite token being beyond 200 chars")
        XCTAssertEqual(results.first?.id, note.id)
    }

    // MARK: - Archived search behavior

    func test_archived_search_includes_archived_when_flagged() async throws {
        var archivedNote = Note(title: "Archived Meeting", body: "archived content")
        archivedNote.archived = true
        var activeNote = Note(title: "Active Note", body: "active content")
        try await insertNotes([archivedNote, activeNote])

        // Wait for both regular and archived observations
        try await waitForStore(expectedCount: 1) // only active in notes
        let start = Date()
        while store.archivedNotes.count < 1, Date().timeIntervalSince(start) < 2 {
            await Task.yield()
        }

        // Search without archived flag
        var result = await store.search(query: "archived", includeArchived: false)
        XCTAssertEqual(result.count, 0, "archived note should not be included with includeArchived: false")

        // Search with archived flag
        result = await store.search(query: "archived", includeArchived: true)
        XCTAssertEqual(result.count, 1, "archived note should be included with includeArchived: true")
        XCTAssertEqual(result.first?.id, archivedNote.id)
    }

    func test_archived_search_not_cached() async throws {
        var archivedNote = Note(title: "Archived", body: "content")
        archivedNote.archived = true
        var activeNote = Note(title: "Active", body: "content")
        try await insertNotes([archivedNote, activeNote])

        // Wait for observations
        try await waitForStore(expectedCount: 1)
        let start = Date()
        while store.archivedNotes.count < 1, Date().timeIntervalSince(start) < 2 {
            await Task.yield()
        }

        // Search with includeArchived: true
        var result = await store.search(query: "content", includeArchived: true)
        XCTAssertEqual(result.count, 2, "should find both archived and active notes")

        // The cache should NOT have been populated for this includeArchived search
        // (according to the code, cache is only populated when !includeArchived)
        // Verify by searching the same query with includeArchived: false — should only find active
        result = await store.search(query: "content", includeArchived: false)
        XCTAssertEqual(result.count, 1, "non-archived search should only find active note")
    }

    // MARK: - Regression: updateBodyText vs updateBody contract

    func test_updateBodyText_does_not_modify_bodyAttributes() async throws {
        // Regression test: updateBodyText is a lightweight commit (for autosave).
        // It MUST NOT touch bodyAttributes or any formatting state.
        var note = Note(title: "Rich Text Note", body: "original content")
        let originalAttrs = Data([0x00, 0x01, 0x02, 0xFF, 0xFE])
        note.bodyAttributes = originalAttrs
        try await insertNotes([note])

        let beforeUpdateNote = await store.fullNote(id: note.id)
        XCTAssertEqual(beforeUpdateNote?.bodyAttributes, originalAttrs, "setup: attributes should be stored")

        // Call the lightweight updateBodyText with new body
        try await store.updateBodyText(
            id: note.id,
            body: "completely new text that is very different",
            selection: NSRange(location: 10, length: 3)
        )

        let afterUpdateNote = await store.fullNote(id: note.id)
        XCTAssertEqual(
            afterUpdateNote?.body,
            "completely new text that is very different",
            "body should be updated"
        )
        XCTAssertEqual(
            afterUpdateNote?.lastSelectedRange,
            NSRange(location: 10, length: 3),
            "selection should be updated"
        )
        XCTAssertEqual(
            afterUpdateNote?.bodyAttributes,
            originalAttrs,
            "bodyAttributes MUST be preserved (not cleared or modified)"
        )
    }

    func test_updateBodyText_updates_modifiedAt_and_localDirty() async throws {
        // updateBodyText must update modifiedAt and set localDirty flag for sync
        var note = Note(title: "Draft Note", body: "initial")
        try await insertNotes([note])

        // 直接查库：内容更新不改变笔记数量，waitForStore 会立即返回而 store.notes 可能尚未刷新。
        let before = await store.fullNote(id: note.id)
        let beforeModifiedAt = before?.modifiedAt ?? Date(timeIntervalSince1970: 0)
        _ = before?.localDirty ?? false

        try await Task.sleep(nanoseconds: 10_000_000) // 10ms to ensure time difference

        try await store.updateBodyText(
            id: note.id,
            body: "revised content",
            selection: nil
        )

        let after = await store.fullNote(id: note.id)
        XCTAssertGreaterThan(
            after?.modifiedAt ?? Date(timeIntervalSince1970: 0),
            beforeModifiedAt,
            "modifiedAt should be updated"
        )
        XCTAssertTrue(after?.localDirty ?? false, "localDirty should be true")
    }

    func test_updateBody_with_nil_attributes_clears_them() async throws {
        // updateBody (the full-format setter) should respect the attributes parameter exactly
        var note = Note(title: "Formatted Note", body: "text")
        note.bodyAttributes = Data([0xFF, 0xAA, 0xBB])
        try await insertNotes([note])

        let before = await store.fullNote(id: note.id)
        XCTAssertNotNil(before?.bodyAttributes, "setup: should have attributes")

        // updateBody with explicit nil should clear attributes
        try await store.updateBody(
            id: note.id,
            body: "new text",
            attributes: nil,
            selection: NSRange(location: 0, length: 0)
        )

        let after = await store.fullNote(id: note.id)
        XCTAssertEqual(after?.body, "new text")
        XCTAssertNil(after?.bodyAttributes, "attributes should be nil after updateBody with nil")
    }

    func test_updateBody_with_new_attributes_replaces_them() async throws {
        // updateBody should replace attributes entirely
        var note = Note(title: "Attribute Test", body: "text")
        note.bodyAttributes = Data([0x01, 0x02])
        try await insertNotes([note])

        let newAttrs = Data([0xAA, 0xBB, 0xCC, 0xDD])
        try await store.updateBody(
            id: note.id,
            body: "updated",
            attributes: newAttrs,
            selection: nil
        )
        let after = await store.fullNote(id: note.id)
        XCTAssertEqual(after?.bodyAttributes, newAttrs, "attributes should be completely replaced")
    }

    // MARK: - Regression: 200-char truncation in summary vs DB search

    func test_summary_projection_truncates_to_200_chars_exactly() async throws {
        // The summarySQL uses substr(body, 1, 200) to reduce memory and diff cost
        let body180 = String(repeating: "a", count: 180)
        let body200 = String(repeating: "b", count: 200)
        let body250 = String(repeating: "c", count: 250)
        let body500 = String(repeating: "d", count: 500)

        let note180 = Note(title: "Note180", body: body180)
        let note200 = Note(title: "Note200", body: body200)
        let note250 = Note(title: "Note250", body: body250)
        let note500 = Note(title: "Note500", body: body500)

        try await insertNotes([note180, note200, note250, note500])

        let observed180 = store.notes.first { $0.title == "Note180" }
        XCTAssertEqual(observed180?.body.count, 180, "body under 200 should not be truncated")

        let observed200 = store.notes.first { $0.title == "Note200" }
        XCTAssertEqual(observed200?.body.count, 200, "body at exactly 200 should remain")

        let observed250 = store.notes.first { $0.title == "Note250" }
        XCTAssertEqual(observed250?.body.count, 200, "body over 200 should be truncated to 200")

        let observed500 = store.notes.first { $0.title == "Note500" }
        XCTAssertEqual(observed500?.body.count, 200, "large body should be truncated to 200")
    }

    func test_search_returns_truncated_body_but_finds_via_full_db() async throws {
        // Search results use the same summarySQL, so returned bodies are truncated.
        // But the search query LIKE runs against the full body in the database.
        // 前缀必须 ≥200，token 才真正落在摘要投影（substr 1..200）之外
        let beforeMatch = String(repeating: "x", count: 250)
        let matchToken = "FINDME"
        let afterMatch = String(repeating: "y", count: 50)
        let fullBody = beforeMatch + matchToken + afterMatch

        let note = Note(title: "Hidden Match", body: fullBody)
        try await insertNotes([note])

        // The in-memory projection should not have the match token (only first 200 chars)
        let projected = store.notes.first { $0.id == note.id }
        XCTAssertLessThanOrEqual(projected?.body.count ?? 0, 200, "projected should be ≤200 chars")
        XCTAssertFalse(
            projected?.body.contains(matchToken) ?? false,
            "projected body should not contain token beyond 200 chars"
        )

        // But search should find it because DB LIKE runs on the full body
        let searchResults = await store.search(query: matchToken)
        XCTAssertEqual(searchResults.count, 1, "search must find via full-body DB LIKE")
        XCTAssertEqual(searchResults.first?.id, note.id)

        // The returned search result is also truncated (uses same summarySQL)
        let returned = searchResults.first
        XCTAssertLessThanOrEqual(returned?.body.count ?? 0, 200, "returned body should also be truncated")
        XCTAssertFalse(
            returned?.body.contains(matchToken) ?? false,
            "returned body in search results should also be truncated"
        )
    }

    func test_full_note_retains_attributes_stripped_from_summary() async throws {
        // 设计契约：内存摘要（NoteSummary）与 search 结果不含 bodyAttributes（类型即保证），
        // 完整数据仍在 DB —— fullNote 应取回属性。这验证「摘要剥离 / fullNote 保留」的边界。
        var note = Note(title: "Has Attributes", body: "content")
        note.bodyAttributes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        try await insertNotes([note])

        // 摘要可见且可搜索（NoteSummary 类型上无 bodyAttributes，无需也无法断言）
        XCTAssertTrue(store.notes.contains { $0.id == note.id }, "summary should be present in memory")
        let searchResults = await store.search(query: "content")
        XCTAssertTrue(searchResults.contains { $0.id == note.id }, "search should find the note")

        // 完整笔记保留属性
        let full = await store.fullNote(id: note.id)
        XCTAssertEqual(full?.bodyAttributes, Data([0xDE, 0xAD, 0xBE, 0xEF]), "fullNote retains bodyAttributes")
    }

    func test_prefix_cache_not_used_for_archived_search() async throws {
        // The prefix-cache optimization only applies to non-archived searches.
        // includeArchived:true bypasses the cache and always does full DB scan.
        var activeNote = Note(title: "foo", body: "active")
        var archivedNote = Note(title: "foobar", body: "archived")
        archivedNote.archived = true
        try await insertNotes([activeNote, archivedNote])

        try await waitForStore(expectedCount: 1)
        let start = Date()
        while store.archivedNotes.count < 1, Date().timeIntervalSince(start) < 2 {
            await Task.yield()
        }

        // First search: non-archived "foo" — caches the result
        var result = await store.search(query: "foo", includeArchived: false)
        XCTAssertEqual(result.count, 1)

        // Second search: archived "foobar" — should NOT use the cache
        // (cache is only populated for !includeArchived)
        result = await store.search(query: "foobar", includeArchived: true)
        XCTAssertEqual(
            result.count,
            1,
            "archived search should not attempt prefix-cache optimization"
        )
    }

    func test_incremental_search_with_multiple_token_narrowing() async throws {
        // Test the prefix-based incremental cache with multi-token refinement
        let n1 = Note(title: "swift performance tips")
        let n2 = Note(title: "swift ui guide")
        let n3 = Note(title: "python tips")
        try await insertNotes([n1, n2, n3])

        // Query 1: "swift" → caches [n1, n2]
        var result = await store.search(query: "swift")
        XCTAssertEqual(result.count, 2)

        // Query 2: "swift performance" → should use cache, narrow to [n1]
        result = await store.search(query: "swift performance")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, n1.id)

        // Query 3: "python" → not a prefix of "swift performance", falls back to full scan
        result = await store.search(query: "python")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, n3.id)
    }

    // MARK: - Edge cases and robustness

    func test_updateBodyText_with_empty_body() async throws {
        var note = Note(title: "Empty Body Test", body: "has content")
        note.bodyAttributes = Data([0x01])
        try await insertNotes([note])

        try await store.updateBodyText(id: note.id, body: "", selection: nil)

        let after = await store.fullNote(id: note.id)
        XCTAssertEqual(after?.body, "")
        XCTAssertEqual(after?.bodyAttributes, Data([0x01]), "attributes preserved even with empty body")
    }

    func test_updateBodyText_with_very_long_body() async throws {
        var note = Note(title: "Long Update", body: "short")
        note.bodyAttributes = Data([0xFF])
        try await insertNotes([note])

        let veryLongBody = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 100)
        try await store.updateBodyText(id: note.id, body: veryLongBody, selection: NSRange(location: 0, length: 0))

        let after = await store.fullNote(id: note.id)
        XCTAssertEqual(after?.body, veryLongBody, "long body should be stored completely")
        XCTAssertEqual(after?.bodyAttributes, Data([0xFF]), "attributes preserved with large body")
    }

    func test_search_with_special_sql_characters() async throws {
        // SQL LIKE has special characters: % (wildcard) and _ (single char wildcard)
        // The search code should escape them
        let note = Note(title: "test_file_%name", body: "content")
        try await insertNotes([note])

        // Search for the literal underscore and percent
        let result = await store.search(query: "test_file_%")
        XCTAssertEqual(result.count, 1, "should find note despite SQL special chars in the query")
    }

    func test_search_with_unicode_characters() async throws {
        let note = Note(title: "北京 会议纪录", body: "讨论了项目进展")
        try await insertNotes([note])

        var result = await store.search(query: "北京")
        XCTAssertEqual(result.count, 1, "should find unicode in title")

        result = await store.search(query: "项目")
        XCTAssertEqual(result.count, 1, "should find unicode in body")
    }

    func test_search_ranking_with_multiword_title_match() async throws {
        // Notes that match ALL query tokens in the title should rank highest
        let allInTitle = Note(title: "swift performance optimization", body: "unrelated")
        let someInTitle = Note(title: "swift guide", body: "performance tips")
        let noneInTitle = Note(title: "guide", body: "swift performance optimization tips")
        try await insertNotes([allInTitle, someInTitle, noneInTitle])

        let result = await store.search(query: "swift performance")
        XCTAssertEqual(result.count, 3)
        // First should be the one with both tokens in title
        XCTAssertEqual(result[0].id, allInTitle.id)
    }

    func test_note_not_found_on_updateBodyText() async throws {
        // updateBodyText on non-existent note should gracefully do nothing
        let fakeUUID = UUID()
        try await store.updateBodyText(id: fakeUUID, body: "text", selection: nil)
        // Should not throw; should just be a no-op
        XCTAssertEqual(store.notes.count, 0)
    }

    func test_note_not_found_on_updateBody() async throws {
        // updateBody on non-existent note should gracefully do nothing
        let fakeUUID = UUID()
        try await store.updateBody(id: fakeUUID, body: "text", attributes: nil, selection: nil)
        // Should not throw; should just be a no-op
        XCTAssertEqual(store.notes.count, 0)
    }
}
