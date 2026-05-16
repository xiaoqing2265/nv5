import XCTest
import NV5

@MainActor
final class FocusCoordinatorTests: XCTestCase {
    var coordinator: FocusCoordinator!

    override func setUp() {
        super.setUp()
        coordinator = FocusCoordinator()
    }

    override func tearDown() {
        coordinator = nil
        super.tearDown()
    }

    func test_initial_focus_is_searchField() {
        XCTAssertEqual(coordinator.current, .searchField)
    }

    func test_focusNext_cycles_through_all_targets() {
        let expectedOrder: [FocusTarget] = [.noteList, .editor, .sidebar, .searchField]
        for target in expectedOrder {
            coordinator.focusNext()
            XCTAssertEqual(coordinator.current, target)
        }
    }

    func test_focusPrevious_cycles_reverse() {
        let expectedOrder: [FocusTarget] = [.sidebar, .editor, .noteList, .searchField]
        for target in expectedOrder {
            coordinator.focusPrevious()
            XCTAssertEqual(coordinator.current, target)
        }
    }

    func test_focus_sets_target() {
        coordinator.focus(.editor)
        XCTAssertEqual(coordinator.current, .editor)
        coordinator.focus(.sidebar)
        XCTAssertEqual(coordinator.current, .sidebar)
    }

    func test_escapeToSearch_returns_to_searchField() {
        coordinator.focus(.editor)
        coordinator.escapeToSearch()
        XCTAssertEqual(coordinator.current, .searchField)
    }

    func test_escapeToSearch_sends_selectAll_signal() {
        let expectation = XCTestExpectation(description: "selectAll signal received")
        let cancellable = coordinator.selectAllSubject.sink { _ in
            expectation.fulfill()
        }
        coordinator.escapeToSearch()
        wait(for: [expectation], timeout: 1.0)
        _ = cancellable
    }

    func test_toggleSidebar_toggles_visibility() {
        XCTAssertTrue(coordinator.sidebarVisible)
        coordinator.toggleSidebar()
        XCTAssertFalse(coordinator.sidebarVisible)
        coordinator.toggleSidebar()
        XCTAssertTrue(coordinator.sidebarVisible)
    }

    func test_returnInList_sends_signal() {
        let expectation = XCTestExpectation(description: "returnInList signal received")
        let cancellable = coordinator.returnInListSubject.sink { _ in
            expectation.fulfill()
        }
        coordinator.returnInList()
        wait(for: [expectation], timeout: 1.0)
        _ = cancellable
    }

    func test_focusNext_full_cycle_returns_to_start() {
        XCTAssertEqual(coordinator.current, .searchField)
        for _ in 0..<4 {
            coordinator.focusNext()
        }
        XCTAssertEqual(coordinator.current, .searchField)
    }
}
