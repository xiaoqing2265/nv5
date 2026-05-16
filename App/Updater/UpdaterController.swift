import SwiftUI
import Sparkle

@Observable
final class UpdaterController {
    let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject var updater: ObservableUpdater

    var body: some View {
        Button("检查更新…") {
            updater.updaterController.checkForUpdates(nil)
        }
        .disabled(!updater.updaterController.updater.canCheckForUpdates)
    }
}

@MainActor
@Observable
final class ObservableUpdater: ObservableObject {
    let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
}
