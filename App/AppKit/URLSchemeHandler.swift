import Foundation

@MainActor
final class URLSchemeHandler {
    let coordinator: AppCoordinator

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func handle(_ url: URL) {
        guard url.scheme == "nv5" else { return }
        let comp = URLComponents(url: url, resolvingAgainstBaseURL: false)

        switch url.host {
        case "new":
            let title = comp?.queryItems?.first(where: { $0.name == "title" })?.value ?? ""
            let body = comp?.queryItems?.first(where: { $0.name == "body" })?.value ?? ""
            Task { await coordinator.newNoteFromURL(title: title, body: body) }
        case "search":
            let q = comp?.queryItems?.first(where: { $0.name == "q" })?.value ?? ""
            coordinator.query = q
            coordinator.focusTarget = .searchField
        case "open":
            if let idStr = comp?.queryItems?.first(where: { $0.name == "id" })?.value,
               let id = UUID(uuidString: idStr) {
                coordinator.selectedNoteID = id
                coordinator.focusTarget = .editor
            }
        default: break
        }
    }
}