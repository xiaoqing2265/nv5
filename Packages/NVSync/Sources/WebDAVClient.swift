import Foundation

public struct WebDAVConfig: Codable, Sendable {
    public var serverURL: URL
    public var username: String
    public var basePath: String
    public var allowsInsecure: Bool

    public var rootURL: URL {
        serverURL.appendingPathComponent(basePath)
    }

    public init(serverURL: URL, username: String, basePath: String, allowsInsecure: Bool = false) {
        self.serverURL = serverURL
        self.username = username
        self.basePath = basePath
        self.allowsInsecure = allowsInsecure
    }
}

public struct WebDAVResource: Sendable {
    public let path: String
    public let etag: String?
    public let lastModified: Date?
    public let contentLength: Int64
    public let isDirectory: Bool

    public init(path: String, etag: String?, lastModified: Date?, contentLength: Int64, isDirectory: Bool) {
        self.path = path
        self.etag = etag
        self.lastModified = lastModified
        self.contentLength = contentLength
        self.isDirectory = isDirectory
    }
}

public protocol WebDAVClientProtocol: Sendable {
    func upload(path: String, data: Data, ifMatch: String?, ifNoneMatch: String?) async throws -> String?
    func download(path: String, ifNoneMatch: String?) async throws -> (Data, String?)?
    func listDirectory(path: String) async throws -> [WebDAVResource]
    func ensureBasePath() async throws
    func ensureDirectory(_ path: String) async throws
    func ensureDirectoryRecursively(_ path: String) async throws
    func delete(path: String, ifMatch: String?) async throws
}

public actor WebDAVClient: WebDAVClientProtocol {
    private let config: WebDAVConfig
    private let session: URLSession
    private var password: String

    public init(config: WebDAVConfig, password: String) {
        self.config = config
        self.password = password
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: cfg)
    }

    private func authHeader() -> String {
        let creds = "\(config.username):\(password)"
        let encoded = Data(creds.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    private func makeRequest(method: String, path: String, headers: [String: String] = [:], body: Data? = nil) -> URLRequest {
        let url = config.rootURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(authHeader(), forHTTPHeaderField: "Authorization")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = body
        return request
    }

    public func listDirectory(path: String = "") async throws -> [WebDAVResource] {
        let propfindBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:propfind xmlns:D="DAV:">
            <D:prop>
                <D:resourcetype/>
                <D:getetag/>
                <D:getlastmodified/>
                <D:getcontentlength/>
            </D:prop>
        </D:propfind>
        """
        let request = makeRequest(
            method: "PROPFIND",
            path: path,
            headers: ["Depth": "1", "Content-Type": "application/xml; charset=utf-8"],
            body: Data(propfindBody.utf8)
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.invalidResponse
        }
        if http.statusCode == 404 { return [] }
        guard http.statusCode == 207 else {
            throw WebDAVError.httpError(http.statusCode)
        }
        return try MultistatusParser.parse(data, baseURL: config.rootURL)
    }

    public func ensureBasePath() async throws {
        let parts = config.basePath.split(separator: "/").map(String.init)
        var current = ""
        for p in parts {
            current = current.isEmpty ? p : "\(current)/\(p)"
            let url = config.serverURL.appendingPathComponent(current)
            var request = URLRequest(url: url)
            request.httpMethod = "MKCOL"
            request.setValue(authHeader(), forHTTPHeaderField: "Authorization")
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw WebDAVError.invalidResponse }
            guard http.statusCode == 201 || http.statusCode == 405 || http.statusCode == 409 else {
                throw WebDAVError.httpError(http.statusCode)
            }
        }
    }

    public func ensureDirectory(_ path: String) async throws {
        let request = makeRequest(method: "MKCOL", path: path)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.invalidResponse }
        guard http.statusCode == 201 || http.statusCode == 405 || http.statusCode == 409 else {
            throw WebDAVError.httpError(http.statusCode)
        }
    }

    public func ensureDirectoryRecursively(_ path: String) async throws {
        let parts = path.split(separator: "/").map(String.init)
        var current = ""
        for p in parts {
            current = current.isEmpty ? p : "\(current)/\(p)"
            try await ensureDirectory(current)
        }
    }

    public func download(path: String, ifNoneMatch: String? = nil) async throws -> (Data, String?)? {
        var headers: [String: String] = [:]
        if let e = ifNoneMatch { headers["If-None-Match"] = "\"\(e)\"" }
        let request = makeRequest(method: "GET", path: path, headers: headers)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.invalidResponse }
        if http.statusCode == 304 { return nil }
        if http.statusCode == 404 { throw WebDAVError.notFound }
        guard http.statusCode == 200 else { throw WebDAVError.httpError(http.statusCode) }
        return (data, normalizeETag(http.value(forHTTPHeaderField: "ETag")))
    }

    public func upload(
        path: String,
        data: Data,
        ifMatch: String? = nil,
        ifNoneMatch: String? = nil
    ) async throws -> String? {
        var headers: [String: String] = ["Content-Type": "application/json"]
        if let e = ifMatch { headers["If-Match"] = "\"\(e)\"" }
        if let e = ifNoneMatch {
            headers["If-None-Match"] = (e == "*") ? "*" : "\"\(e)\""
        }
        let request = makeRequest(method: "PUT", path: path, headers: headers, body: data)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.invalidResponse }
        if http.statusCode == 412 { throw WebDAVError.preconditionFailed }
        guard (200..<300).contains(http.statusCode) else {
            throw WebDAVError.httpError(http.statusCode)
        }
        return normalizeETag(http.value(forHTTPHeaderField: "ETag"))
    }

    public func delete(path: String, ifMatch: String? = nil) async throws {
        var headers: [String: String] = [:]
        if let e = ifMatch { headers["If-Match"] = "\"\(e)\"" }
        let request = makeRequest(method: "DELETE", path: path, headers: headers)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.invalidResponse }
        guard http.statusCode == 204 || http.statusCode == 404 else {
            throw WebDAVError.httpError(http.statusCode)
        }
    }
}

public enum WebDAVError: Error, Sendable {
    case invalidResponse
    case notFound
    case preconditionFailed
    case httpError(Int)
    case parseFailed
}

func normalizeETag(_ raw: String?) -> String? {
    guard var s = raw, !s.isEmpty else { return nil }
    if s.hasPrefix("W/") { s = String(s.dropFirst(2)) }
    s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    return s.isEmpty ? nil : s
}

public enum ServerURLParser {
    public static func parse(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        s = s.replacingOccurrences(of: ";//", with: "://")

        if !s.contains("://") {
            let host = s.components(separatedBy: ":").first ?? s
            let isIP = isIPAddress(host)
            let scheme = isIP ? "http" : "https"
            s = "\(scheme)://\(s)"
        }

        guard let url = URL(string: s),
              let scheme = url.scheme,
              let host = url.host,
              scheme == "http" || scheme == "https" else { return nil }

        let port = url.port.map { ":\($0)" } ?? ""
        return URL(string: "\(scheme)://\(host)\(port)")
    }

    private static func isIPAddress(_ host: String) -> Bool {
        if host == "localhost" { return true }
        let parts = host.split(separator: ".").map(String.init)
        if parts.count == 4, parts.allSatisfy({ Int($0) != nil }) { return true }
        return false
    }
}