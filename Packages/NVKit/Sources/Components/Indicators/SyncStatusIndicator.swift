import SwiftUI

public struct SyncStatusIndicator: View {
    public enum State: Sendable, Equatable, Hashable {
        case unconfigured
        case idle(lastSync: Date?)
        case syncing
        case error(message: String)
    }

    public let state: State
    public let onClick: @MainActor () -> Void

    public init(state: State, onClick: @escaping @MainActor () -> Void) {
        self.state = state
        self.onClick = onClick
    }

    public var body: some View {
        Button(action: onClick) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .unconfigured:
            Label("Not Configured", systemImage: "icloud.slash")
                .foregroundStyle(.secondary)
        case .idle(let date):
            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                .help(idleHelpText(date: date))
        case .syncing:
            ProgressView().controlSize(.small)
        case .error(let msg):
            Label("Sync Error", systemImage: "exclamationmark.icloud")
                .foregroundStyle(.red)
                .help(msg)
        }
    }

    private func idleHelpText(date: Date?) -> String {
        guard let date = date else { return "Never synced" }
        return "Last synced \(date.formatted(.relative(presentation: .named)))"
    }
}

#Preview("SyncStatusIndicator states") {
    VStack(spacing: 16) {
        SyncStatusIndicator(state: .unconfigured) {}
        SyncStatusIndicator(state: .idle(lastSync: Date())) {}
        SyncStatusIndicator(state: .syncing) {}
        SyncStatusIndicator(state: .error(message: "Network failed")) {}
    }
    .padding()
}