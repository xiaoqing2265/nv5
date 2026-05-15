import AppKit
import NVModel

@objc final class ServicesProvider: NSObject {
    let coordinator: AppCoordinator

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()
    }

    @objc func sendToNV5(_ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pasteboard.string(forType: .string) else { return }
        let currentCoordinator = coordinator
        Task { @MainActor in
            let note = Note(title: text.prefix(40).description, body: text)
            try? await currentCoordinator.store.upsert(note)
        }
    }
}