import SwiftUI
import Sparkle

@MainActor
final class UpdaterController: ObservableObject {
    let updater: SPUStandardUpdaterController
    @Published var canCheckForUpdates = false

    init() {
        updater = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updater.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updater.checkForUpdates(nil)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject var controller: UpdaterController

    var body: some View {
        Button("检查更新…") {
            controller.checkForUpdates()
        }
        .disabled(!controller.canCheckForUpdates)
    }
}
