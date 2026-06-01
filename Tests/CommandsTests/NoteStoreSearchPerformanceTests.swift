import XCTest
import GRDB
@testable import NVModel
@testable import NVStore

final class NoteStoreSearchPerformanceTests: XCTestCase {
    private var tempDBURL: URL!
    private var database: NVStore.Database!
    private var store: NoteStore!

    override func setUp() async throws {
        try await super.setUp()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("NV5Perf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDBURL = tempDir.appendingPathComponent("notes.sqlite")
        database = try NVStore.Database(url: tempDBURL)
        store = try await MainActor.run {
            NoteStore(database: database)
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            store = nil
        }
        database = nil
        try await super.tearDown()
    }

    func testSearchBodyMatchPerformance_1000Notes() async throws {
        try await insertFixtureNotes(count: 1_000, bodySize: .medium, matchingEvery: 10, token: "needle")

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

    func testIncrementalSearchPerformance_1000Notes() async throws {
        try await insertFixtureNotes(count: 1_000, bodySize: .short, matchingEvery: 8, token: "swift")

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: measureOptions()) {
            let expectation = expectation(description: "incremental search completes")
            Task {
                _ = await store.search(query: "s")
                _ = await store.search(query: "sw")
                let results = await store.search(query: "swift")
                XCTAssertFalse(results.isEmpty)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 5)
        }
    }

    func testSearchCacheInvalidatesAfterTitleAndBodyUpdates() async throws {
        let note = Note(title: "Original", body: "old body")
        try await insertNotes([note])

        let staleResults = await store.search(query: "replacement")
        XCTAssertTrue(staleResults.isEmpty)
        try await store.updateTitle(id: note.id, title: "Replacement")
        try await store.updateBodyText(id: note.id, body: "new body token", selection: nil)

        let titleResults = await store.search(query: "replacement")
        let bodyResults = await store.search(query: "token")
        XCTAssertEqual(titleResults.map(\.id), [note.id])
        XCTAssertEqual(bodyResults.map(\.id), [note.id])
    }

    private func insertFixtureNotes(count: Int, bodySize: NoteFixtureFactory.BodySize, matchingEvery: Int, token: String) async throws {
        try await insertNotes(
            NoteFixtureFactory.notes(
                count: count,
                bodySize: bodySize,
                matchingEvery: matchingEvery,
                token: token,
                labelEvery: count + 1
            )
        )
    }

    private func insertNotes(_ notes: [Note]) async throws {
        try await database.writer.write { db in
            for note in notes {
                var note = note
                try note.insert(db)
            }
        }
        await waitForStore(expectedCount: notes.count)
    }

    private func waitForStore(expectedCount: Int, timeout: TimeInterval = 5) async {
        let start = Date()
        while await noteCount() < expectedCount, Date().timeIntervalSince(start) < timeout {
            await Task.yield()
        }
    }

    private func noteCount() async -> Int {
        await MainActor.run {
            store.notes.count
        }
    }

    private func measureOptions() -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        return options
    }
}
