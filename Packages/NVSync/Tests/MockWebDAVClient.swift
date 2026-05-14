import Foundation
@testable import NVSync

actor MockWebDAVClient: WebDAVClientProtocol {
    var files: [String: (Data, String)] = [:]
    var uploads: [(path: String, data: Data)] = []
    var deletes: [String] = []

    func setMockFile(path: String, data: Data, etag: String) {
        files[path] = (data, etag)
    }

    func upload(path: String, data: Data, ifMatch etag: String?) async throws -> String? {
        // If ifMatch is provided and doesn't match the current ETag, simulate precondition failed.
        if let ifMatch = etag, let existing = files[path], existing.1 != ifMatch {
            throw WebDAVError.preconditionFailed
        }
        let newEtag = UUID().uuidString
        files[path] = (data, newEtag)
        uploads.append((path, data))
        return newEtag
    }

    func download(path: String, ifNoneMatch etag: String? = nil) async throws -> (Data, String?)? {
        guard let file = files[path] else { return nil }
        if let etag = etag, etag == file.1 {
            return nil // Unchanged
        }
        return (file.0, file.1)
    }

    func listDirectory(path: String) async throws -> [WebDAVResource] {
        return files.keys.filter { $0.hasPrefix(path) }.map {
            WebDAVResource(
                path: $0,
                etag: files[$0]?.1,
                lastModified: Date(),
                contentLength: Int64(files[$0]?.0.count ?? 0),
                isDirectory: false
            )
        }
    }

    func ensureDirectory(_ path: String) async throws {
        // no-op for mock
    }

    func delete(path: String, ifMatch etag: String? = nil) async throws {
        files.removeValue(forKey: path)
        deletes.append(path)
    }
}
