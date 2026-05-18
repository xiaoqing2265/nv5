import Foundation
import NVModel

/// 多选和范围选择逻辑。
/// 不持有 observable 状态，所有状态由 AppCoordinator 管理。
@MainActor
final class SelectionManager {
    func extendSelection(
        to noteID: UUID,
        allNotes: [Note],
        anchorNoteID: inout UUID?,
        selectedNoteIDs: inout Set<UUID>,
        selectedNoteID: inout UUID?
    ) {
        guard let anchor = anchorNoteID,
              let anchorIdx = allNotes.firstIndex(where: { $0.id == anchor }),
              let targetIdx = allNotes.firstIndex(where: { $0.id == noteID }) else {
            selectedNoteIDs = [noteID]
            anchorNoteID = noteID
            selectedNoteID = noteID
            return
        }
        let range = anchorIdx <= targetIdx ? anchorIdx...targetIdx : targetIdx...anchorIdx
        selectedNoteIDs = Set(allNotes[range].map { $0.id })
        selectedNoteID = noteID
    }

    func selectAllNotes(in notes: [Note], anchorNoteID: inout UUID?, selectedNoteIDs: inout Set<UUID>) {
        selectedNoteIDs = Set(notes.map { $0.id })
        anchorNoteID = notes.first?.id
    }
}
