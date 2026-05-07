import Foundation
import NVKit
import NVSync

enum SyncStatusBridge {
    static func uiState(
        from status: SyncCoordinator.SyncStatus,
        lastSync: Date?,
        isConfigured: Bool
    ) -> SyncStatusIndicator.State {
        guard isConfigured else { return .unconfigured }
        switch status {
        case .idle: return .idle(lastSync: lastSync)
        case .syncing: return .syncing
        case .error(let m): return .error(message: m)
        }
    }
}