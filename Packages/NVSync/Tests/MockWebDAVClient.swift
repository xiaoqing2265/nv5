import Foundation
@testable import NVSync

actor MockWebDAVClient: WebDAVClientProtocol {
    var files: [String: (Data, String)] = [:]
    var uploads: [(path: String, data: Data)] = []
    var deletes: [String] = []

    func setMockFile(path: String, data: Data, etag: String) {
        files[path] = (data, etag)
    }

    func upload(path: String, data: Data, ifMatch: String?, ifNoneMatch: String?) async throws -> String? {
        if let ifMatch = ifMatch, let existing = files[path], existing.1 != ifMatch {
            throw WebDAVError.preconditionFailed
        }
        if let ifNoneMatch = ifNoneMatch, ifNoneMatch == "*", files[path] != nil {
            throw WebDAVError.preconditionFailed
        }
        let newEtag = UUID().uuidString
        files[path] = (data, newEtag)
        uploads.append((path, data))
        return newEtag
    }

    func download(path: String, ifNoneMatch: String?) async throws -> (Data, String?)? {
        guard let file = files[path] else { throw WebDAVError.notFound }
        if let etag = ifNoneMatch, etag == file.1 {
            return nil
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

    func ensureBasePath() async throws {
        // no-op for mock
    }

    func ensureDirectory(_ path: String) async throws {
        // no-op for mock
    }

    func ensureDirectoryRecursively(_ path: String) async throws {
        // no-op for mock
    }

    func delete(path: String, ifMatch: String?) async throws {
        files.removeValue(forKey: path)
        deletes.append(path)
    }
}
