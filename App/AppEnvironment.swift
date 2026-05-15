import Foundation
import AppKit
import NVModel
import NVStore

@MainActor
public final class AppEnvironment {
    public static let shared = AppEnvironment()

    public let database: Database
    public let store: NoteStore

    private init() {
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ).appendingPathComponent("NV5", isDirectory: true)
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            let dbURL = appSupport.appendingPathComponent("notes.sqlite")
            let db = try Database(url: dbURL)
            self.database = db
            self.store = NoteStore(database: db)
        } catch {
            let dbPath = (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: false
            ).appendingPathComponent("NV5/notes.sqlite").path) ?? "~/Library/Application Support/NV5/notes.sqlite"

            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "无法启动 NV5"
            alert.informativeText = "数据库初始化失败：\(error.localizedDescription)\n\n可能的解决方法：删除 \(dbPath) 后重试。"
            alert.addButton(withTitle: "退出")
            alert.runModal()
            // swiftlint:disable:next fatal_error
            fatalError("AppEnvironment init failed: \(error). DB path: \(dbPath)")
        }
    }
}