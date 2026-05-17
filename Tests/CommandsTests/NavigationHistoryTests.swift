import XCTest
@testable import NV5

@MainActor
final class NavigationHistoryTests: XCTestCase {
    var history: NavigationHistory!

    override func setUp() {
        super.setUp()
        history = NavigationHistory()
    }

    override func tearDown() {
        history = nil
        super.tearDown()
    }

    func test_record_single_note() {
        let noteID = UUID()
        history.record(noteID)
        XCTAssertNotNil(history)
    }

    func test_goBack_returns_previous_note() {
        let note1 = UUID()
        let note2 = UUID()
        let note3 = UUID()

        history.record(note1)
        history.record(note2)
        history.record(note3)

        let back = history.goBack()
        XCTAssertEqual(back, note2)
    }

    func test_goBack_at_start_returns_nil() {
        let note1 = UUID()
        history.record(note1)

        let back = history.goBack()
        XCTAssertNil(back)
    }

    func test_goForward_returns_next_note() {
        let note1 = UUID()
        let note2 = UUID()
        let note3 = UUID()

        history.record(note1)
        history.record(note2)
        history.record(note3)

        history.goBack()
        history.goBack()

        let forward = history.goForward()
        XCTAssertEqual(forward, note2)
    }

    func test_goForward_at_end_returns_nil() {
        let note1 = UUID()
        let note2 = UUID()

        history.record(note1)
        history.record(note2)

        let forward = history.goForward()
        XCTAssertNil(forward)
    }

    func test_record_truncates_forward_history() {
        let note1 = UUID()
        let note2 = UUID()
        let note3 = UUID()
        let note4 = UUID()

        history.record(note1)
        history.record(note2)
        history.record(note3)

        history.goBack()
        history.goBack()

        history.record(note4)

        let forward = history.goForward()
        XCTAssertNil(forward)
    }

    func test_duplicate_consecutive_notes_not_recorded() {
        let note1 = UUID()

        history.record(note1)
        history.record(note1)

        let back = history.goBack()
        XCTAssertNil(back)
    }

    func test_max_size_limit() {
        for _ in 0..<60 {
            history.record(UUID())
        }

        let note = UUID()
        history.record(note)

        for _ in 0..<50 {
            history.goBack()
        }

        let back = history.goBack()
        XCTAssertNil(back)
    }

    func test_back_and_forward_cycle() {
        let note1 = UUID()
        let note2 = UUID()
        let note3 = UUID()

        history.record(note1)
        history.record(note2)
        history.record(note3)

        let back1 = history.goBack()
        XCTAssertEqual(back1, note2)

        let back2 = history.goBack()
        XCTAssertEqual(back2, note1)

        let forward1 = history.goForward()
        XCTAssertEqual(forward1, note2)

        let forward2 = history.goForward()
        XCTAssertEqual(forward2, note3)
    }
}
