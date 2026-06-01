# nv5 Test Documentation

## Overview

nv5 is a macOS note-taking application built with a layered architecture separating concerns across UI (AppKit/SwiftUI), storage (NVStore/GRDB), and synchronization (NVSync/WebDAV). This document provides comprehensive guidance on testing strategy, test organization, performance baselines, and regression protection for the nv5 project.

### Architecture at a Glance

The test strategy mirrors nv5's architecture:

- **UI Layer (AppKit/SwiftUI)**: NoteEditor coordinator, EditorColumn, NoteListColumn
- **Storage Layer (NVStore/GRDB)**: NoteStore with reactive ValueObservation, search with incremental caching
- **Sync Layer (NVSync/WebDAV)**: SyncCoordinator with 3-way merge, conflict resolution, tombstone tracking
- **Shared Data**: Notes with optional attributes (RTFD), rich formatting, local dirty flags, remote state (etag, remotePath)

### Testing Philosophy

nv5's test strategy is built on **five core principles** aligned with its layered architecture:

1. **Determinism over reality**: All I/O is faked (temp SQLite in-memory databases per test, MockWebDAVClient instead of real servers, NoteFixtureFactory with deterministic UUIDs).
2. **Isolate by layer, integrate at seams**: Pure business logic (FuzzyMatcher scoring, search ranking, decorator regex, conflict resolution) is unit-tested; risky cross-layer behavior (Editor→Store commit dispatch, Store→Sync snapshot flow, debounce/cancellation) gets integration tests.
3. **Time and concurrency must be controllable**: Debounce/idle timers (300ms text, 5s rich, 150ms filter) and Task cancellation are critical; tests assert state-machine transitions via expectations/awaits, not wall-clock sleeps.
4. **Performance is a contract with explicit baselines**: XCTClockMetric + XCTMemoryMetric tests encode timing/memory targets and fail on regression; inspectable counters (localSnapshotReadCount, uploadCount) make invisible optimizations assertable.
5. **Refactors require characterization + regression locks**: Every modified component ships a regression test pinning the new contract AND verifying the property it must NOT break (e.g., lightweight commit never clears bodyAttributes).

---

## Quick Start

### Running the Test Suite

```bash
# Run all CommandsTests (app-level logic)
xcodebuild test -scheme NV5App -only-testing NV5AppTests

# Run NVSync package tests
swift test --package-path Packages/NVSync

# Run a single test file
xcodebuild test -scheme NV5App -only-testing NV5AppTests/NoteStoreSearchTests

# Run performance tests (slower, optional for nightly)
xcodebuild test -scheme NV5App -only-testing NV5AppTests/NoteStoreSearchPerformanceTests
```

### For Writing a New Test

1. Identify the test layer: unit (pure logic) → unit with GRDB → integration → performance.
2. Create the test file next to peers: `/Tests/CommandsTests/MyFeatureTests.swift`.
3. Use `NoteFixtureFactory.notes(count:bodySize:matchingEvery:token:labelEvery:)` for test data.
4. Create a temp database with `try Database(url: tempDBURL)` and tear it down in `tearDown()`.
5. For timing-critical code, annotate `@MainActor` and use `async/await` with `XCTestExpectation`.
6. Assert optimizations via inspectable counters (e.g., `coordinator.localSnapshotReadCount`).
7. Run `gitnexus_detect_changes()` before commit to confirm only intended symbols changed.

---

## Test File Map

| # | File | Test Class | Coverage Status | Priority | Purpose |
|---|------|-----------|-----------------|----------|---------|
| 1 | NoteEditorAutosaveTests.swift | NoteEditorAutosaveTests | Partial | **HIGH** | Editor coordinator's two-callback autosave (300ms text, 5s rich). Lightweight path must NOT serialize RTFD or clear bodyAttributes; note-switch/app-resign must flush pending commits. |
| 2 | ConflictResolutionTests.swift | ConflictResolutionTests | Partial | **HIGH** | Sync conflict resolution and tombstone lifecycle. Local-dirty-wins, etag-mismatch detection, both-sides-modified conflict copy. Must exercise real SyncCoordinator methods, not inline logic. |
| 3 | NoteStoreSearchTests.swift | NoteStoreSearchTests | Partial | **MEDIUM** | NoteStore query/search/cache/update semantics. updateBodyText vs updateBody contract; summary projection SQL correctness; body-text search beyond 200-char truncation. **Suite has compile errors** (XCTAssertGreater→XCTAssertGreaterThan, Data UInt8 overflow). |
| 4 | TextDecoratorPipelineTests.swift | TextDecoratorPipelineTests | Not started | **MEDIUM** | TextDecoratorPipeline functional correctness: interactive vs full decoration, markdown headings, wiki-links, done tags, link detection. No functional tests yet; only perf assertions exist. |
| 5 | SyncCoordinatorSnapshotTests.swift | SyncCoordinatorSnapshotTests | Partial | **MEDIUM** | Sync orchestration: single-read and upload-count assertions exist; status state-machine, error-state, and reentrancy missing. |
| 6 | NoteStoreSearchPerformanceTests.swift | NoteStoreSearchPerformanceTests | Partial | **MEDIUM** | Search latency/memory baselines. 1000-note baseline exists; 5000/10000 tiers and worst-case scenarios missing. |
| 7 | NoteListFilterTests.swift | NoteListFilterTests | Not started | **HIGH** | List filtering by all/archived/label with debounce. Flagged high-risk in CLAUDE.md; no test file exists. Must cover rapid query input throttling, cancellation, and projection correctness. |
| 8 | TextDecoratorPipelinePerformanceTests.swift | TextDecoratorPipelinePerformanceTests | Partial | **MEDIUM** | Interactive vs full decoration speed; URL-heavy document baselines. 100KB baseline exists; 1MB and variant coverage missing. |
| 9 | NoteRepositoryTests.swift | NoteRepositoryTests | Not started | **LOW** | Async search await fix regression test. Shipped without dedicated test; one-line test locks the behavior. |
| 10 | NoteFixtureFactory.swift | N/A | Partial | **LOW** | Fixture factory with deterministic UUIDs. count/body-size/token/label variations exist; dirty/archived/deleted/etag/remotePath/seed variations needed. |

---

## Test Layers

### Layer 1: Unit Tests — Pure Business Logic

Test deterministic algorithms in isolation with no I/O or mocking complexity.

**Scope**: Algorithms that convert inputs to outputs with zero side effects.

**Examples**:
- FuzzyMatcher scoring rules
- Search ranking tokenization
- Command registry filtering
- Text decorator regex output (headings, wiki-links)
- Conflict resolution decision logic (local-dirty-wins, etag comparison)
- RemoteNotePayload ↔ Note serialization

**Key traits**:
- No database, no network, no main thread requirement
- @MainActor not required
- Tests run in <10ms
- Can run in parallel safely

**Example**:
```swift
final class FuzzyMatcherTests: XCTestCase {
    func test_consecutive_chars_score_higher() {
        let score1 = FuzzyMatcher.score(query: "swift", title: "swift sync", keywords: [], subtitle: nil)
        let score2 = FuzzyMatcher.score(query: "swft", title: "swift sync", keywords: [], subtitle: nil)
        XCTAssertEqual(score1, 1.0)
        XCTAssertLessThan(score2!, 1.0)
    }
}
```

### Layer 2: Unit Tests with GRDB (Temp SQLite)

Test persistence, queries, and reactive updates against real database behavior using disposable temp databases.

**Scope**: NoteStore CRUD, search, cache invalidation, database observation semantics.

**Examples**:
- updateBodyText vs updateBody contract (text-only vs full RTFD)
- Search finds full body beyond 200-char summary projection
- Cache invalidation on note-count change but persistence across content edits
- Summary SQL projection correctness
- Archived search bypasses cache

**Key traits**:
- One temp SQLite database per test method
- @MainActor required (ValueObservation is MainActor)
- Tests typically 100-500ms
- Tear down database in tearDown()

**Example**:
```swift
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

    func test_updateBodyText_preserves_existing_bodyAttributes() async throws {
        var note = Note(title: "Test", body: "Initial")
        note.bodyAttributes = .rtfdData(richData)
        try await store.upsert(note)

        // Lightweight path: update text only
        try await store.updateBodyText(id: note.id, body: "Updated", selection: nil)

        let updated = try await database.writer.read { db in
            try Note.fetchOne(db, id: note.id)
        }
        XCTAssertEqual(updated?.body, "Updated")
        XCTAssertNotNil(updated?.bodyAttributes, "Lightweight path must preserve bodyAttributes")
    }
}
```

### Layer 3: Integration Tests

Test cross-component data flows, state machines, and timing contracts.

**Scope**: Editor autosave coordination, Store→Sync data flow, debounce/cancellation, note-switch flushing.

**Examples**:
- Editor coordinator's two-callback autosave (300ms text-only, 5s rich)
- Note-switch flush pending rich commit before loading another note
- App-resign-active flush pending commits
- Stale note ID snapshot prevents cross-note commit
- SyncCoordinator reads local snapshot exactly once across all phases
- Sync reconciliation and tombstone application

**Key traits**:
- Multiple components working together
- @MainActor required
- Combines real objects (NoteEditor.Coordinator, NoteStore, SyncCoordinator) with mocks (MockWebDAVClient)
- Tests 500ms–5000ms (some use real timers; refactoring to inject clock is in progress)
- Assert state transitions, not timing

**Example**:
```swift
@MainActor
final class NoteEditorAutosaveTests: XCTestCase {
    func test_lightweight_commit_does_not_serialize_rtfd() async throws {
        let harness = EditorHarness()
        harness.load(body: "Initial text")

        harness.textView.string = "Edited text"
        harness.coordinator.textDidChange(
            Notification(name: NSText.didChangeNotification, object: harness.textView)
        )

        // Wait for lightweight save (300ms) to fire
        try await Task.sleep(nanoseconds: 350_000_000)

        // Verify: onTextCommit called, onRichCommit not called
        XCTAssertEqual(harness.textCommits.count, 1)
        XCTAssertTrue(harness.richCommits.isEmpty, "onRichCommit must not be called in 300ms window")
    }
}
```

### Layer 4: Performance Tests

Establish and enforce timing and memory contracts using XCTClockMetric and XCTMemoryMetric.

**Scope**: Operations with measurable performance contracts (search at scale, decoration speed, sync throughput).

**Examples**:
- NoteStore body search latency at 1000+ notes
- TextDecoratorPipeline.runInteractive vs runAll speed
- Local snapshot read count per sync
- WebDAV upload count per sync
- Editor lightweight commit cost

**Key traits**:
- measure(metrics:options:block:) captures XCTClockMetric and XCTMemoryMetric
- Baseline is recorded; threshold is set conservatively (allow 20–50% regression for developer machines)
- Tests are deterministic but may be marked @testable(XCode) for nightly runs
- Inspectable counters (e.g., `coordinator.localSnapshotReadCount`, `mockClient.uploadCount()`) assert invisible optimizations

**Example**:
```swift
final class NoteStoreSearchPerformanceTests: XCTestCase {
    func testSearchBodyMatchPerformance_1000Notes() async throws {
        let notes = NoteFixtureFactory.notes(count: 1_000, bodySize: .medium, matchingEvery: 10, token: "needle")
        try await insertNotes(notes)

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: measureOptions()) {
            let expectation = expectation(description: "search completes")
            Task {
                let results = await store.search(query: "needle")
                XCTAssertEqual(results.count, 100)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 5)
        }
    }
}
```

---

## Performance Baselines

Performance contracts encode invisible optimizations that are easy to regress. Every baseline is paired with an assertion that the optimization actually happened (e.g., upload count, snapshot read count).

### Search Latency

**NoteStore body search at 1000 notes (~100 matching)**
- **Baseline**: Establish current run as committed baseline (typical: 50–150ms on MacBook Pro)
- **Threshold**: Fail on >20% regression via XCTClockMetric
- **Test**: NoteStoreSearchPerformanceTests.testSearchBodyMatchPerformance_1000Notes
- **Dataset**: 1000-note fixture from NoteFixtureFactory with ~100 title/body matches for query "needle"
- **Path tested**: Full DB LIKE scan (incremental cache miss)
- **Assertion**: Results count == 100 (correctness); clock metric recorded

**NoteStore search at 5000 / 10000 notes**
- **5000 notes**: Within standard CI budget (target: <500ms)
- **10000 notes**: Nightly only (record absolute ms once hardware baseline captured)
- **Tests**: NoteStoreSearchPerformanceTests (stubs exist; 5000/10000 variants not yet implemented)
- **Threshold**: Record baseline; set guardrail at 1.5× baseline

### Incremental Prefix Search vs Cold Scan

**Property**: Prefix-narrowed cache (s→sw→swift) is measurably cheaper than cold full scan

- **Test**: NoteStoreSearchPerformanceTests.testIncrementalSearchPerformance_1000Notes
- **Assertion**: 
  ```swift
  _ = await store.search(query: "s")   // populate cache
  _ = await store.search(query: "sw")  // hit cache, narrow results
  let results = await store.search(query: "swift")  // final cached results
  // Verify cache was used (implicit: final search is faster than a cold "swift" search)
  ```

### Interactive Text Decoration

**Property**: runInteractive on 100KB URL-heavy document is within interactive responsiveness budget AND produces zero HTTP link attributes

- **Baseline**: Establish current latency (typical: 5–15ms on MacBook Pro for 100KB)
- **Threshold**: Fail on >50% regression (to allow some variance on loaded CI)
- **Test**: TextDecoratorPipelinePerformanceTests (100KB baseline exists; 1MB tier not yet implemented)
- **Dataset**: 100KB URL-heavy fixture (mix of http:// and https:// URLs)
- **Assertions**:
  ```swift
  let decoratedAttributes = TextDecoratorPipeline.runInteractive(on: storage)
  // Assertion 1: clock metric shows acceptable latency
  // Assertion 2: decoratedAttributes contains no link attributes (LinkDecorator was skipped)
  XCTAssertFalse(decoratedAttributes.contains { attr in attr.name == .link })
  ```

### Interactive vs Full Decoration Speedup

**Property**: runInteractive is strictly faster than runAll on identical URL-heavy content (LinkDecorator skipped)

- **Test**: TextDecoratorPipelinePerformanceTests
- **Assertions**:
  ```swift
  let content = makeURLHeavyText(size: 100_000)
  var storage = NSTextStorage(string: content)
  
  var interactiveTime: Int64 = 0
  measure(metrics: [XCTClockMetric()]) {
      TextDecoratorPipeline.runInteractive(on: storage)
  }
  
  var fullTime: Int64 = 0
  measure(metrics: [XCTClockMetric()]) {
      TextDecoratorPipeline.runAll(on: storage)
  }
  
  XCTAssertLessThan(interactiveTime, fullTime)
  ```

### Decoration on 1MB Document

**Property**: Interactive latency stays interactive at scale; full latency bounded; memory peak reasonable

- **Test**: TextDecoratorPipelinePerformanceTests (not yet implemented)
- **Dataset**: 1MB fixture (nightly tier)
- **Baselines**:
  - Interactive: target <50ms (may vary per machine)
  - Full: target <500ms
  - Memory peak: record baseline
- **Assertions**:
  ```swift
  measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
      TextDecoratorPipeline.runInteractive(on: largeStorage)
  }
  ```

### Local Snapshot Reads Per Sync Cycle

**Property**: Exactly 1 local snapshot read regardless of number of sync phases or notes

- **Baseline**: 1 (hardcoded, not measured)
- **Test**: SyncCoordinatorSnapshotTests.testSyncReadsLocalSnapshotOnceWhenUploadingNewLocalNotes
- **Assertion**:
  ```swift
  try await syncCoordinator.sync()
  XCTAssertEqual(coordinator.localSnapshotReadCount, 1)
  ```
- **Why this matters**: The single-snapshot refactor is the core sync performance contract. A regression to per-phase reads degrades sync at scale.

### WebDAV Uploads Per Sync

**Property**: Exactly N uploads for N new notes (no redundant uploads)

- **Baseline**: count == new notes with no remotePath
- **Test**: SyncCoordinatorSnapshotTests.testSyncReadsLocalSnapshotOnceWhenUploadingNewLocalNotes
- **Assertion**:
  ```swift
  try await store.upsert(Note(...))
  try await store.upsert(Note(...))
  try await coordinator.sync()
  XCTAssertEqual(await mockClient.uploadCount(), 2)
  ```

### Editor Lightweight Commit Cost

**Property**: 300ms path never serializes RTFD; commit work bounded (no RTFD Data produced)

- **Baseline**: zero RTFD serializations
- **Test**: NoteEditorAutosaveTests.test_lightweight_commit_does_not_serialize_rtfd
- **Assertion**:
  ```swift
  // Spy on RTFD serialization
  XCTAssertTrue(harness.capturedRTFDDuringLightweight.isEmpty, 
                "No RTFD Data should be produced during 300ms save")
  ```
- **Optional XCTClockMetric**: Measure commitPendingIfNeeded(includeAttributes:false) on large document

### Note List Filter Recomputation Frequency

**Property**: One filter computation per 150ms debounce window, not per keystroke

- **Test**: NoteListFilterTests (not yet implemented)
- **Assertion**:
  ```swift
  var filterInvocationCount = 0
  let injectedHook = { filterInvocationCount += 1 }
  
  // Emit rapid query changes (10 changes in <150ms)
  for i in 0..<10 {
      setQuery("q\(i)")
      // Each emission does NOT trigger filter immediately
  }
  
  // Wait for 150ms debounce
  try await Task.sleep(nanoseconds: 150_000_000)
  
  XCTAssertEqual(filterInvocationCount, 1, "Only one computation for the settled query")
  ```

---

## Critical Regression Checklist

### Before Every PR

- [x] Run `xcodebuild test -scheme NV5App` to confirm **suite compiles** (two hard errors in NoteStoreSearchTests must be fixed)
- [x] Run affected test targets:
  - Editor changes → NoteEditorAutosaveTests
  - Store changes → NoteStoreSearchTests + NoteStoreSearchPerformanceTests
  - Sync changes → ConflictResolutionTests + SyncCoordinatorSnapshotTests
  - Decorator changes → TextDecoratorPipelineTests + TextDecoratorPipelinePerformanceTests

### [CRITICAL FIX REQUIRED] Compile Errors

**File**: NoteStoreSearchTests.swift

**Error 1** (~line 446):
```swift
// WRONG:
XCTAssertGreater(...)

// CORRECT:
XCTAssertGreaterThan(...)
```

**Error 2** (~line 562):
```swift
// WRONG:
Data([0xDEAD, 0xBEEF])  // 0xDEAD = 57005, overflows UInt8

// CORRECT:
Data([0xDE, 0xAD, 0xBE, 0xEF])  // all < 256
```

### [P0] Lightweight (300ms) Autosave Contract

**Invariant**: 300ms path never serializes RTFD or clears bodyAttributes.

**Why critical**: Lightweight commit must route to NoteStore.updateBodyText (text-only); if it routes to updateBody, every rapid edit silently destroys the user's bold/italic/link formatting — irrecoverable data loss.

**Tests**:
- [ ] NoteEditorAutosaveTests.test_lightweight_commit_does_not_serialize_rtfd
- [ ] NoteStoreSearchTests.test_updateBodyText_preserves_existing_bodyAttributes

**Manual verification** (before release):
1. Open an RTFD note with bold/italic text.
2. Tap into body and type plain text rapidly.
3. Confirm in DB that body updates while bodyAttributes is unchanged.
4. Verify no rich commit fired (check editor logs or test harness).

### [P0] Note-Switch / Stale-ID / App-Resign Flush

**Invariant**: Pending rich commit flushes before loading another note / backgrounding app / ending edit session. Stale note ID snapshot prevents committing note A's text onto note B.

**Why critical**: nvALT-style immediate save depends on flushes firing. A regression here loses the last edits when the user switches notes or the app backgrounds.

**Tests**:
- [ ] NoteEditorAutosaveTests.test_switching_notes_flushes_pending_rich_commit
- [ ] NoteEditorAutosaveTests.test_stale_note_id_snapshot_prevents_cross_note_commit
- [ ] NoteEditorAutosaveTests.test_app_resign_active_flushes_rich_commit

**Manual verification** (before release):
1. Edit note A, immediately click note B before 300ms timer fires.
2. Confirm note A keeps edits and note B is untouched.
3. Switch to another app (resign active).
4. Return and confirm note A edits are saved.

### [P0] Sync Conflict Resolution

**Invariant**: local-dirty-wins over remote-changed; etag-mismatch detected; no remote overwrite of unsync'd local edits; tombstones applied once.

**Why critical**: Highest-severity sync data-loss paths. Local edits overwritten by stale remote state, or notes resurrected after delete.

**Tests**:
- [ ] ConflictResolutionTests.test_local_dirty_wins_over_remote_change
- [ ] ConflictResolutionTests.test_etag_mismatch_detected_during_reconcile
- [ ] ConflictResolutionTests.test_both_sides_modified_remote_newer_creates_conflict_copy
- [ ] ConflictResolutionTests.test_remote_tombstone_soft_deletes_local
- [ ] ConflictResolutionTests.test_tombstone_application_is_idempotent

**IMPORTANT**: Tests must call real SyncCoordinator methods (sync(), reconcileExistingNotes, applyRemoteDeletion, pushDeletion), NOT inline DB writes or partial mocking. Current inline-logic tests will NOT catch regressions in SyncCoordinator's actual methods.

**Manual verification** (before release):
1. Create a note locally and sync (sets etag).
2. Edit remotely via WebDAV client; change etag.
3. Edit locally without syncing.
4. Force sync.
5. Confirm local edits win and note keeps local content.

### [P1] Single Local Snapshot Per Sync

**Invariant**: localSnapshotReadCount == 1 after a sync that exercises download+upload+reconcile.

**Why important**: The single-snapshot refactor is the core sync performance contract. A regression to per-phase reads degrades sync at scale and risks inconsistent state across phases.

**Tests**:
- [ ] SyncCoordinatorSnapshotTests.testSyncReadsLocalSnapshotOnceWhenUploadingNewLocalNotes
- [ ] SyncCoordinatorSnapshotTests.testSyncReadsLocalSnapshotOnceWhenDownloadingRemoteNotes
- [ ] SyncCoordinatorSnapshotTests (new) test mixed upload+download+reconcile scenario

**Assertion**:
```swift
try await coordinator.sync()
XCTAssertEqual(coordinator.localSnapshotReadCount, 1)
```

### [P1] Search Finds Full Body Beyond 200 Chars

**Invariant**: Search hits the DB over full body; list/search projection stays truncated (summary is substr(body,1,200)); bodyAttributes is NULL in all projections.

**Why important**: The list observation truncates body to 200 chars for memory efficiency, but search must hit full body. If search accidentally runs against the in-memory projection, notes matching only deep in their body become unfindable — silent correctness loss.

**Tests**:
- [ ] NoteStoreSearchTests.test_search_finds_text_beyond_200_chars_via_db
- [ ] NoteStoreSearchTests.test_summary_projection_truncates_to_200_chars_exactly
- [ ] NoteStoreSearchTests.test_bodyAttributes_null_in_all_projections

### [P1] Interactive Decoration Never Runs LinkDecorator

**Invariant**: runInteractive skips LinkDecorator; runAll always includes LinkDecorator.

**Why important**: The split exists for keystroke responsiveness on large documents. If LinkDecorator leaks into runInteractive, typing in long notes janks; if it drops from runAll, links stop rendering on load.

**Tests**:
- [ ] TextDecoratorPipelineTests.test_interactive_does_not_run_link_detector
- [ ] TextDecoratorPipelineTests.test_full_decoration_includes_link_detector
- [ ] TextDecoratorPipelinePerformanceTests.test_interactive_faster_than_full_on_url_heavy_content

**Assertion**:
```swift
let interactive = TextDecoratorPipeline.runInteractive(on: storage)
XCTAssertFalse(interactive.contains { attr in attr.name == .link })

let full = TextDecoratorPipeline.runAll(on: storage)
XCTAssertTrue(full.contains { attr in attr.name == .link })
```

### [P2] Search Cache Invalidation

**Invariant**: Cache invalidates on note-count change but persists across content-only edits. Archived search bypasses cache.

**Why important**: If invalidation breaks, deleted/added notes appear in stale results; if it over-clears, the incremental-search performance optimization is lost.

**Tests**:
- [ ] NoteStoreSearchTests.test_cache_clears_only_on_note_count_didSet
- [ ] NoteStoreSearchTests.test_cache_survives_content_change_but_clears_on_count_change
- [ ] NoteStoreSearchTests.test_prefix_cache_not_used_for_archived_search

### [P2] Repository Search Awaits Completion

**Invariant**: NoteRepository.search awaits store.search; Intents layer does not return partial results.

**Why important**: The recent fix added the missing await; without regression test, a future edit could drop it again and the Intents layer would return empty/partial results before async search resolves.

**Tests**:
- [ ] NoteRepositoryTests.test_repository_search_awaits_completion (one-liner; not yet written)

---

## Adding Tests for New Features

### Step-by-Step Workflow

1. **Identify test layer**: Does the feature operate on pure input→output (Unit)? Persist to DB (Unit+GRDB)? Span multiple components (Integration)? Measure latency/memory (Performance)?

2. **Run impact analysis**:
   ```bash
   gitnexus_impact({target: "symbolName", direction: "upstream"})
   ```
   Report blast radius to the user before editing. If HIGH/CRITICAL risk, flag it.

3. **Create test file** next to peers:
   - App/editor/store/command logic → `/Tests/CommandsTests/MyFeatureTests.swift`
   - Sync/package logic → `/Packages/NVSync/Tests/MyFeatureTests.swift` or relevant package
   
4. **Use NoteFixtureFactory** for all note data:
   ```swift
   let notes = NoteFixtureFactory.notes(
       count: 100,
       bodySize: .medium,
       matchingEvery: 10,
       token: "search_term",
       labelEvery: 7
   )
   ```

5. **Set up temp database** (for GRDB layer):
   ```swift
   override func setUp() async throws {
       let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("NV5Test-\(UUID().uuidString)")
       try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
       tempDBURL = tempDir.appendingPathComponent("notes.sqlite")
       let database = try Database(url: tempDBURL)
       store = NoteStore(database: database)
   }
   ```

6. **Tear down database** in tearDown():
   ```swift
   override func tearDown() async throws {
       store = nil
       database = nil
       try? FileManager.default.removeItem(at: tempDBURL.deletingLastPathComponent())
       try await super.tearDown()
   }
   ```

7. **For @MainActor types**, annotate test class and use async/await:
   ```swift
   @MainActor
   final class MyFeatureTests: XCTestCase {
       func test_something() async throws {
           // test code
       }
   }
   ```

8. **For time-sensitive code**, use XCTestExpectation:
   ```swift
   let expectation = expectation(description: "save completes")
   Task {
       try await store.updateBodyText(id: note.id, body: "new", selection: nil)
       expectation.fulfill()
   }
   wait(for: [expectation], timeout: 2)
   ```

9. **Make optimizations assertable** by exposing counters:
   ```swift
   // In feature code:
   public var localSnapshotReadCount: Int { ... }
   
   // In test:
   try await coordinator.sync()
   XCTAssertEqual(coordinator.localSnapshotReadCount, 1)
   ```

10. **For refactors**, add two tests:
    - **Contract test**: Pin new behavior
    - **Regression lock**: Verify property that MUST NOT break

    Example:
    ```swift
    // Contract test
    func test_updateBodyText_returns_to_store() async throws {
        try await store.updateBodyText(id: note.id, body: "new", selection: nil)
        let updated = try await database.read { db in
            try Note.fetchOne(db, id: note.id)
        }
        XCTAssertEqual(updated?.body, "new")
    }
    
    // Regression lock
    func test_updateBodyText_preserves_bodyAttributes() async throws {
        // ... (as shown in Layer 2 example)
    }
    ```

11. **Run impact analysis** before committing:
    ```bash
    gitnexus_detect_changes()
    ```
    Confirm only intended symbols/flows changed.

12. **Run affected test targets** locally:
    ```bash
    xcodebuild test -scheme NV5App -only-testing NV5AppTests/MyFeatureTests
    swift test --package-path Packages/NVSync
    ```

### Swift Test Template

```swift
import XCTest
import GRDB
@testable import NVModel
@testable import NVStore
@testable import NV5

@MainActor
final class MyFeatureTests: XCTestCase {
    // MARK: - Setup & Teardown
    
    private var tempDBURL: URL!
    private var database: Database!
    private var store: NoteStore!
    
    override func setUp() async throws {
        try await super.setUp()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("NV5Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDBURL = tempDir.appendingPathComponent("notes.sqlite")
        database = try Database(url: tempDBURL)
        store = NoteStore(database: database)
    }
    
    override func tearDown() async throws {
        store = nil
        database = nil
        try? FileManager.default.removeItem(at: tempDBURL.deletingLastPathComponent())
        try await super.tearDown()
    }
    
    // MARK: - Functional Tests
    
    /// Test core behavior: input → expected output.
    func test_feature_does_something_correctly() async throws {
        // Arrange
        let notes = NoteFixtureFactory.notes(count: 10, bodySize: .short)
        for note in notes {
            try await store.upsert(note)
        }
        
        // Act
        let result = await store.search(query: "needle")
        
        // Assert
        XCTAssertEqual(result.count, 1)
    }
    
    /// Test regression invariant: property that refactor MUST NOT break.
    func test_refactor_preserves_important_invariant() async throws {
        // Arrange & Act
        var note = Note(title: "Test", body: "Initial")
        note.bodyAttributes = .rtfdData(someData)
        try await store.updateBodyText(id: note.id, body: "Updated", selection: nil)
        
        // Assert
        let updated = try await database.writer.read { db in
            try Note.fetchOne(db, id: note.id)
        }
        XCTAssertNotNil(updated?.bodyAttributes, "Lightweight path must preserve bodyAttributes")
    }
    
    // MARK: - Performance Tests (optional)
    
    /// Test performance contract: latency/memory baseline.
    func test_search_performance_at_1000_notes() async throws {
        let notes = NoteFixtureFactory.notes(count: 1_000, bodySize: .medium)
        try await insertNotes(notes)
        
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let expectation = expectation(description: "search completes")
            Task {
                let results = await store.search(query: "needle")
                XCTAssertGreaterThan(results.count, 0)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 5)
        }
    }
    
    // MARK: - Helpers
    
    private func insertNotes(_ notes: [Note]) async throws {
        try await database.writer.write { db in
            for note in notes {
                var note = note
                try note.insert(db)
            }
        }
        await waitForStore(expectedCount: notes.count)
    }
    
    private func waitForStore(_ expectedCount: Int, timeout: TimeInterval = 2) async {
        let start = Date()
        while store.notes.count < expectedCount, Date().timeIntervalSince(start) < timeout {
            await Task.yield()
        }
    }
}
```

---

## Test Data & Fixtures

### NoteFixtureFactory

`NoteFixtureFactory` generates deterministic, reproducible test data. Every Note gets a UUID derived from its index, ensuring the same index always produces the same UUID.

**Current API**:
```swift
static func notes(
    count: Int,
    bodySize: BodySize,
    matchingEvery stride: Int = 10,
    token: String = "needle",
    labelEvery labelStride: Int = 7
) -> [Note]
```

**Example usage**:
```swift
// 1000 notes, ~100 matching "needle"
let notes = NoteFixtureFactory.notes(
    count: 1_000,
    bodySize: .medium,
    matchingEvery: 10,  // every 10th note matches
    token: "needle",
    labelEvery: 7       // add token to labels every 7th note
)
```

**Deterministic UUIDs**:
```swift
// Index 0 → UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
// Index 5 → UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
```

### BodySize Variants

| Size | Bytes | Use case |
|------|-------|----------|
| short | 160 | Quick tests, cache tests, list observation |
| medium | 2,048 | Typical notes, balanced perf testing |
| large | 10,240 | Large documents, stress tests, memory baselines |

### Extending NoteFixtureFactory

**Current limitations** (to be extended):
- No dirty flag variation (localDirty, archived, deletedLocally)
- No remote state variation (etag, remotePath)
- No seed parameter for custom determinism

**Extend when adding**:
- Conflict/tombstone tests (need dirty, etag, remotePath, modifiedAt distribution)
- Filter tests (need archived, deleted, label distribution)
- Larger perf tiers (5000/10000 nodes with state variation)

**Example extension**:
```swift
enum NoteFixtureFactory {
    enum State {
        case clean          // synchronized, no local changes
        case localDirty     // local edits, not synced
        case archived       // archived
        case deletedLocally // soft-deleted locally
    }
    
    static func notes(
        count: Int,
        bodySize: BodySize,
        matchingEvery stride: Int = 10,
        token: String = "needle",
        labelEvery labelStride: Int = 7,
        stateDistribution: [State: Double] = ["clean": 0.8, "localDirty": 0.2],
        seed: UInt32? = nil
    ) -> [Note] {
        // ...
    }
}
```

### MockWebDAVClient

`MockWebDAVClient` replaces real WebDAV for sync testing. It records all operations and allows predictable state injection.

**API**:
```swift
await mockClient.setMockFile(path: "notes/uuid.json", data: data, etag: "tag-123")
let data = await mockClient.download(path: "notes/uuid.json")
await mockClient.upload(path: "notes/uuid.json", data: data, onConflict: .replace)
await mockClient.delete(path: "notes/uuid.json")
let count = await mockClient.uploadCount()
```

**Example usage**:
```swift
let mockClient = MockWebDAVClient()

// Stage a remote note
let remote = Note(title: "Remote", body: "Body")
let payload = RemoteNotePayload(from: remote)
let data = try JSONEncoder.iso8601.encode(payload)
await mockClient.setMockFile(path: "notes/\(remote.id.uuidString).json", data: data, etag: "etag-1")

// Run sync
let coordinator = SyncCoordinator(client: mockClient, store: store, database: database)
try await coordinator.sync()

// Assert
XCTAssertEqual(await mockClient.uploadCount(), 0)  // No new local notes to upload
```

---

## Known Gaps & Roadmap

### Blocking Issues

#### [CRITICAL] Suite Does Not Compile

**File**: NoteStoreSearchTests.swift
**Errors**:
- Line ~446: `XCTAssertGreater(...)` → **must change to** `XCTAssertGreaterThan(...)`
- Line ~562: `Data([0xDEAD, 0xBEEF])` → **must change to** `Data([0xDE, 0xAD, 0xBE, 0xEF])` (Data([UInt8]))

**Impact**: A non-compiling test file means **zero coverage** from every test in it (not just the two lines). The suite cannot run until this is fixed.

**Action**: Fix both errors and run `xcodebuild test -scheme NV5App` + `swift test --package-path Packages/NVSync` to confirm full suite builds.

#### [HIGH] Conflict/Tombstone Tests Use Inline Logic

**Files**: ConflictResolutionTests.swift (test_clean_remote_change_downloads_when_not_dirty, test_remote_tombstone_soft_deletes_local, test_local_tombstone_deletes_remote)

**Issue**: Tests re-implement sync steps inline (calling mockClient.download/delete and writing DB directly, or only calling store.markTombstoneApplied) instead of invoking the real code paths (downloadAndUpdate, applyRemoteDeletion, pushDeletion). They assert the test's own logic, so a regression in SyncCoordinator's actual methods would NOT be caught.

**Action**: Drive tests through SyncCoordinator:
1. Stage local + remote state in the temp DB and MockWebDAVClient.
2. Call syncCoordinator.sync() (or specific reconcile/apply methods via @testable).
3. Assert the store/mock end state.

Example fix for "local-tombstone" case:
```swift
// WRONG (today):
try await store.markTombstoneApplied(id: noteID)
let deleted = try await database.read { db in
    try Note.fetchOne(db, id: noteID)
}
XCTAssertNil(deleted)  // Asserts store.markTombstoneApplied worked, not SyncCoordinator

// RIGHT:
// 1. Stage local tombstone in store
var tombstoneNote = Note(id: noteID, ...)
tombstoneNote.deletedLocally = true
try await store.upsert(tombstoneNote)

// 2. Stage remote note in mockClient
let remotePayload = RemoteNotePayload(from: Note(id: noteID, ...))
let data = try JSONEncoder.iso8601.encode(remotePayload)
await mockClient.setMockFile(path: "notes/\(noteID.uuidString).json", data: data, etag: "remote")

// 3. Call the real sync path
try await coordinator.sync()

// 4. Assert end state: tombstone applied, remote deleted
let updated = try await database.read { db in
    try Note.fetchOne(db, id: noteID)
}
XCTAssertTrue(updated?.deletedLocally ?? false)

let uploadedTombstone = await mockClient.downloadTombstone(path: "notes/\(noteID.uuidString).json")
XCTAssertNotNil(uploadedTombstone)  // SyncCoordinator pushed tombstone

let remoteAfterSync = try await mockClient.download(path: "notes/\(noteID.uuidString).json")
XCTAssertNil(remoteAfterSync)  // SyncCoordinator deleted remote
```

#### [MEDIUM-HIGH] Time-Based Tests Use Real Wall-Clock Sleeps

**Files**: NoteEditorAutosaveTests.swift (idle-5s, no-duplicate, rapid-typing tests sleep 5.1s+; total runtime many seconds)

**Issue**: NoteEditor.Coordinator hardcodes 300ms/5s debounce durations with no injectable clock. Multi-second sleeps are inherently flake-prone on loaded CI runners.

**Action**: Introduce an injectable debounce interval (or a Clock abstraction) into Coordinator:
```swift
class Coordinator {
    var textDebounceInterval: TimeInterval = 0.3  // injectable, defaults to 300ms
    var richDebounceInterval: TimeInterval = 5.0   // injectable, defaults to 5s
    
    // In tests:
    coordinator.textDebounceInterval = 0.001  // 1ms
    coordinator.richDebounceInterval = 0.005  // 5ms
}
```

Short term, gate the 5s idle tests behind a @slowTests or nightly annotation so PR runs stay quick.

#### [MEDIUM] deinit Test Does Not Actually Verify Cleanup

**File**: NoteEditorAutosaveTests.swift (test_deinit_cancels_both_tasks_and_removes_observer)

**Issue**: Test asserts only `XCTAssertNil(harness)` after setting `harness=nil`, which proves nothing about saveTask/richSaveTask cancellation or NotificationCenter observer removal. It is a placeholder masquerading as coverage of a leak-prone path.

**Action**: Make the assertion real:
1. Post willResignActive AFTER releasing the coordinator and assert no commit fires (observer removed).
2. Start an edit then release before the 300ms timer and assert no onTextCommit fires (task cancelled).
3. Capture commits via a closure that outlives the coordinator.

```swift
func test_deinit_cancels_both_tasks() async throws {
    var harness: EditorHarness? = EditorHarness()
    harness?.load(body: "Initial")
    
    var commitFiredAfterDeinit = false
    
    harness?.onTextCommit = { _ in
        commitFiredAfterDeinit = true  // Closure outlives coordinator
    }
    
    // Start an edit
    harness?.textView.string = "Edited"
    harness?.coordinator.textDidChange(...)
    
    // Release before 300ms timer
    harness = nil
    
    // Wait past 300ms and verify no commit fired
    try await Task.sleep(nanoseconds: 350_000_000)
    XCTAssertFalse(commitFiredAfterDeinit, "Deinitialized coordinator must cancel saveTask")
}
```

### Medium Priority Gaps

#### [P4] NoteFixtureFactory Missing State Variations

**File**: NoteFixtureFactory.swift

**Issue**: Factory only varies count/body/token/label. Conflict/tombstone tests (P2) and not-yet-written filter tests (P7) need localDirty/archived/deletedLocally/etag/remotePath/seed variation. Today, conflict tests hand-build each Note, which is fine but means the factory cannot support larger fixtures (5000/10000-node perf tiers).

**Action**: Extend factory with:
```swift
static func notes(
    count: Int,
    bodySize: BodySize,
    matchingEvery: Int = 10,
    token: String = "needle",
    labelEvery: Int = 7,
    stateDistribution: [State: Double]? = nil,  // ["clean": 0.8, "dirty": 0.2]
    seed: UInt32? = nil
) -> [Note] {
    // Support dirty, archived, deleted, etag, remotePath distributions
}
```

Add self-tests for factory (e.g., verify seed produces same UUIDs, state distribution is correct).

#### [P5] Functional TextDecoratorPipelineTests Missing

**File**: TextDecoratorPipelineTests.swift (does not exist)

**Issue**: Only performance-level assertions of the split exist today; functional correctness tests are missing. User-visible gap: wrong styling on markdown headings, wiki-links, done tags.

**Action**: Add functional test file covering:
- Markdown headings: "### Heading" → detected as heading
- Wiki-links: "[[Note Title]]" → detected as wiki-link
- Done tags: "DONE the task" → detected as done
- Link detection in runAll but not runInteractive
- Attribute ranges correct (start/length boundaries)

Example:
```swift
final class TextDecoratorPipelineTests: XCTestCase {
    func test_heading_detected_in_line() {
        let text = "Some text\n### My Heading\nMore text"
        let storage = NSTextStorage(string: text)
        
        TextDecoratorPipeline.runAll(on: storage)
        
        // Assert "### My Heading" range has heading attribute
        let headingRange = (text as NSString).range(of: "### My Heading")
        let attributes = storage.attributes(at: headingRange.location, effectiveRange: nil)
        XCTAssertNotNil(attributes[.headingLevel])  // or however heading is encoded
    }
}
```

#### [P6] NoteListFilterTests Missing

**File**: NoteListFilterTests.swift (does not exist)

**Issue**: List filtering by all/archived/label with debounce is flagged as high-risk in CLAUDE.md. No test file exists. Must cover rapid query input throttling, cancellation, and projection correctness.

**Action**: Add integration test covering:
- Filter recomputation happens once per 150ms debounce window, not per keystroke
- Rapid query changes (10 changes in <150ms) result in only one final computation
- Cancelled query does not run filter
- Archived filter bypasses search cache

#### [P7] NoteRepositoryTests Missing

**File**: NoteRepositoryTests.swift (does not exist)

**Issue**: Async search await fix shipped without dedicated test. One-liner regression test locks the behavior.

**Action**: Add:
```swift
@MainActor
final class NoteRepositoryTests: XCTestCase {
    func test_repository_search_awaits_completion() async throws {
        let repo = NoteRepository(store: store)
        let results = await repo.search(query: "test")
        XCTAssertNotNil(results, "Search must await and return results, not empty/partial")
    }
}
```

#### [P8] Large-Scale Perf Tiers Not Implemented

**Files**: NoteStoreSearchPerformanceTests.swift, TextDecoratorPipelinePerformanceTests.swift

**Missing**:
- 5000-note search baseline (within standard CI budget)
- 10,000-note search (nightly only; record absolute ms once hardware baseline captured)
- 1MB document decoration (interactive + full; memory peak)
- Worst-case query patterns (e.g., single-char query matching 50% of notes)

**Action**: Extend perf tests with conditional skipping for nightly:
```swift
func testSearch_5000Notes() async throws {
    let notes = NoteFixtureFactory.notes(count: 5_000, bodySize: .medium)
    try await insertNotes(notes)
    
    measure(metrics: [XCTClockMetric()]) {
        // search
    }
}

@testable(slowTests)
func testSearch_10000Notes() async throws {
    // nightly only; requires hardware baseline
}
```

### Low Priority Enhancements

- **CI integration**: Gate 5000/10000-node tests to nightly; 1000-node tests run per-commit.
- **Hardware baseline capture**: Document testing machine specs and establish regression thresholds once baseline captured.
- **Instrumentation improvements**: Add logging hooks for filter invocation count, observation update count, snapshot read count (already exists for localSnapshotReadCount).

---

## Naming Conventions

### Test Classes

**Pattern**: `<Feature>Tests`

- Suffix: always `Tests`
- Match file name: `NoteEditorAutosaveTests.swift` → `NoteEditorAutosaveTests` class
- One class per component/behavior area
- Use PascalCase: `NoteStoreSearchTests`, `ConflictResolutionTests`, `FuzzyMatcherTests`

**Examples**:
- `NoteEditorAutosaveTests` (editor coordinator autosave state machine)
- `NoteStoreSearchTests` (store search, cache, update semantics)
- `SyncCoordinatorSnapshotTests` (sync orchestration and snapshot optimization)
- `TextDecoratorPipelineTests` (functional decoration tests — not yet written)
- `NoteListFilterTests` (list filtering and debounce — not yet written)

### Test Methods

**Pattern**: `test_<subject>_<scenario>_<expectedResult>`

- Prefix: always `test_`
- Structure: snake_case
- Subject: what is being tested (e.g., `lightweight_commit`, `updateBodyText`, `search`)
- Scenario: under what conditions (e.g., `does_not_serialize_rtfd`, `preserves_existing_bodyAttributes`, `finds_text_beyond_200_chars`)
- Expected result: what should happen (e.g., `routes_to_onTextCommit_only`, `clears_only_on_note_count_didSet`)

**Examples** (existing in codebase):
- `test_lightweight_commit_routes_to_onTextCommit_only`
- `test_lightweight_commit_does_not_serialize_rtfd`
- `test_idle_5s_triggers_rich_commit_with_attributes`
- `test_title_match_ranks_higher_than_body_match`
- `test_search_finds_text_beyond_200_chars_via_db`

**Performance methods**: End in `_performance` or `_baseline`
- `testSearchBodyMatchPerformance_1000Notes`
- `test_interactive_decoration_baseline_100KB`
- `testIncrementalSearchPerformance_1000Notes`

**Regression locks**: Read as `test_<refactor>_preserves_<invariant>` or `test_<feature>_does_not_<sideEffect>`
- `test_updateBodyText_preserves_existing_bodyAttributes`
- `test_lightweight_commit_does_not_serialize_rtfd`
- `test_interactive_decoration_does_not_run_link_detector`

### Import Statements

**Pattern**: @testable imports for internal symbol access

```swift
import XCTest
import GRDB                    // Only if using database
import Combine                  // Only if testing Combine publishers
@testable import NV5           // App-level logic
@testable import NVModel       // Note model
@testable import NVStore       // Store and database
@testable import NVSync        // Sync coordinator
```

### Fixture and Mock Naming

- **Fixtures**: `NoteFixtureFactory.notes(...)`, variables like `notes`, `fixture`, `testData`
- **Mocks**: `MockWebDAVClient`, `MockNotificationCenter` (prefix Mock + real name)
- **Harnesses**: `EditorHarness` (encapsulates test doubles for coordinator + store + UI)

### Test Organization Within a File

```swift
final class MyTests: XCTestCase {
    // MARK: - Setup & Teardown
    override func setUp() { ... }
    override func tearDown() { ... }
    
    // MARK: - Feature Area 1
    func test_feature_1_scenario_1() { ... }
    func test_feature_1_scenario_2() { ... }
    
    // MARK: - Feature Area 2
    func test_feature_2_scenario_1() { ... }
    
    // MARK: - Performance
    func test_operation_performance_baseline() { ... }
    
    // MARK: - Regression Locks
    func test_refactor_preserves_invariant() { ... }
    
    // MARK: - Helpers
    private func insertNotes(_ notes: [Note]) async throws { ... }
    private func waitForStore(expectedCount: Int) async { ... }
}
```

---

## Summary

nv5's test strategy balances **fidelity** (real GRDB, real NSTextView, real SyncCoordinator logic) with **determinism** (temp databases, MockWebDAVClient, no real network). The five principles — determinism, layered isolation, controllable time, explicit performance baselines, and regression locks — ensure tests stay maintainable as the codebase evolves.

**Before shipping any PR**:
1. Fix compile errors in NoteStoreSearchTests (XCTAssertGreater, Data UInt8).
2. Ensure affected test targets pass (`xcodebuild test`, `swift test`).
3. Run gitnexus_detect_changes() and report any regressions.
4. Verify critical regression tests pass (lightweight autosave, sync conflict, snapshot reads).

**Before each release**:
1. Run full suite: `xcodebuild test -scheme NV5App` + `swift test --package-path Packages/NVSync`.
2. Run performance smoke tests (1000-note search, 100KB decoration).
3. Manual verification of autosave flushing, sync conflict resolution, and editor UI responsiveness.
