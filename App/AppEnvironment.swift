import Foundation
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
            fatalError("Failed to init database: \(error)")
        }
    }
}