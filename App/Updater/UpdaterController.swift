import SwiftUI
import Sparkle

@MainActor
final class UpdaterController: ObservableObject {
    let updater: SPUStandardUpdaterController
    @Published var canCheckForUpdates = false

    init() {
        // UI 测试模式下不启动更新器：ad-hoc 签名的测试构建无法启动更新助手，
        // 否则会弹「无法检查更新」模态框，抢焦点、挡住 UI 测试交互。
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
        updater = SPUStandardUpdaterController(
            startingUpdater: !isUITesting,
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
