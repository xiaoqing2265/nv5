import Foundation
import Combine

@MainActor
@Observable
public final class FocusCoordinator {
    public var current: FocusTarget = .searchField
    public var sidebarVisible: Bool = true
    public var showPalette: Bool = false

    public let selectAllSubject = PassthroughSubject<Void, Never>()
    public let returnInListSubject = PassthroughSubject<Void, Never>()

    public func focus(_ target: FocusTarget) {
        current = target
    }

    public func focusNext() {
        current = current.next()
    }

    public func focusPrevious() {
        current = current.previous()
    }

    public func escapeToSearch() {
        current = .searchField
        selectAllSubject.send()
    }

    /// §3.5 QA #5: Return in list → focus editor with cursor at end
    public func returnInList() {
        current = .editor
        returnInListSubject.send()
    }

    public func toggleSidebar() {
        sidebarVisible.toggle()
    }
}
