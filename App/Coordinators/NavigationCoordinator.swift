import Foundation
import NVModel

/// 管理笔记导航状态：历史记录、前后切换
@MainActor
final class NavigationCoordinator {
    private let history = NavigationHistory()
    private(set) var previousNoteID: UUID?

    func didSelect(_ noteID: UUID, previous: UUID?) {
        previousNoteID = previous
        history.record(noteID)
    }

    func goBack() -> UUID? {
        history.goBack()
    }

    func goForward() -> UUID? {
        history.goForward()
    }

    func previousNote(existingIn notes: [Note], archived: [Note]) -> UUID? {
        guard let prev = previousNoteID else { return nil }
        let exists = notes.contains(where: { $0.id == prev })
            || archived.contains(where: { $0.id == prev })
        return exists ? prev : nil
    }
}
