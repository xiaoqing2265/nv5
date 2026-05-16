public enum FocusTarget: Hashable, CaseIterable, Sendable {
    case searchField
    case noteList
    case editor
    case sidebar

    public static let allCases: [FocusTarget] = [.searchField, .noteList, .editor, .sidebar]

    func next() -> FocusTarget {
        switch self {
        case .searchField: return .noteList
        case .noteList: return .editor
        case .editor: return .sidebar
        case .sidebar: return .searchField
        }
    }

    func previous() -> FocusTarget {
        switch self {
        case .searchField: return .sidebar
        case .noteList: return .searchField
        case .editor: return .noteList
        case .sidebar: return .editor
        }
    }
}
