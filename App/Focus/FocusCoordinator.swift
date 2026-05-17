import Foundation
import Combine

@MainActor
@Observable
public final class FocusCoordinator {
    public var current: FocusTarget = .searchField
    public var sidebarVisible: Bool = true
    public var showPalette: Bool = false
    
    /// 浮层是否激活（命令面板、TagEditor 等）
    public var isOverlayActive: Bool = false
    public var showCheatSheet: Bool = false
    
    /// 焦点栈，用于模态返回
    private var focusStack: [FocusTarget] = []

    public let selectAllSubject = PassthroughSubject<Void, Never>()
    public let returnInListSubject = PassthroughSubject<Void, Never>()

    public init() {}

    public func focus(_ target: FocusTarget) {
        current = target
    }

    public func focusNext() {
        guard !isOverlayActive else { return }
        current = current.next()
    }

    public func focusPrevious() {
        guard !isOverlayActive else { return }
        current = current.previous()
    }

    public func escapeToSearch() {
        if current != .searchField {
            current = .searchField
        }
        DispatchQueue.main.async { [weak self] in
            self?.selectAllSubject.send()
        }
    }

    public func escapeToList() {
        current = .noteList
    }

    /// §3.5 QA #5: Return in list → focus editor with cursor at end
    public func returnInList() {
        current = .editor
        returnInListSubject.send()
    }

    public func toggleSidebar() {
        sidebarVisible.toggle()
    }
    
    /// 推入当前焦点到栈（打开模态对话框前调用）
    public func pushFocus() {
        focusStack.append(current)
    }
    
    /// 弹出并恢复焦点（关闭模态对话框后调用）
    public func popFocus() {
        if let last = focusStack.popLast() {
            current = last
        }
    }
}
