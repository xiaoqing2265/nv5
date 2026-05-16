import Foundation
import Observation

@MainActor
@Observable
final class NavigationHistory {
    private var stack: [UUID] = []
    private var index: Int = -1
    private let maxSize = 50
    
    func record(_ noteID: UUID) {
        // 如果不是从历史前进/后退而来，截断后续历史
        if index < stack.count - 1 {
            stack = Array(stack.prefix(index + 1))
        }
        if stack.last != noteID {
            stack.append(noteID)
            if stack.count > maxSize { stack.removeFirst() }
        }
        index = stack.count - 1
    }
    
    func goBack() -> UUID? {
        guard index > 0 else { return nil }
        index -= 1
        return stack[index]
    }
    
    func goForward() -> UUID? {
        guard index < stack.count - 1 else { return nil }
        index += 1
        return stack[index]
    }
}
