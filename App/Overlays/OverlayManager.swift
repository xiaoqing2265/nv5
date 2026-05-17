import Foundation
import Observation

public enum OverlayType: String, CaseIterable, Hashable, Sendable {
    case tagEditor
    case cheatSheet
    case commandPalette
}

@MainActor
@Observable
public final class OverlayManager {
    public static let shared = OverlayManager()

    private var activeOverlays: Set<OverlayType> = []

    public var isAnyActive: Bool { !activeOverlays.isEmpty }

    public func isActive(_ type: OverlayType) -> Bool {
        activeOverlays.contains(type)
    }

    public func open(_ type: OverlayType) {
        activeOverlays.insert(type)
    }

    public func close(_ type: OverlayType) {
        activeOverlays.remove(type)
    }

    public func closeAll() {
        activeOverlays.removeAll()
    }

    private init() {}
}
