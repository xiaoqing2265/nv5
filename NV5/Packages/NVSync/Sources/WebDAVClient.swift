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

public actor WebDAVClient {
    private let config: WebDAVConfig
    private let session: URLSession
    private var password: String

    public init(config: WebDAVConfig, password: String) {
        self.config = config
        self.password = password
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        let credential = URLCredential(user: config.username, password: password, persistence: .forSession)
        let protectionSpace = URLProtectionSpace(
            host: config.serverURL.host ?? "",
            port: config.serverURL.port ?? (config.serverURL.scheme == "https" ? 443 : 80),
            protocol: config.serverURL.scheme,
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
        URLCredentialStorage.shared.setDefaultCredential(credential, for: protectionSpace)
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
        <?xml version="1.0" encoding="utf-8" ?>
        <D:propfind xmlns:D="DAV:">
          <D:prop>
            <D:getetag/>
            <D:getlastmodified/>
            <D:getcontentlength/>
            <D:resourcetype/>
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

    public func ensureDirectory(_ path: String) async throws {
        let request = makeRequest(method: "MKCOL", path: path)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.invalidResponse }
        guard http.statusCode == 201 || http.statusCode == 405 else {
            throw WebDAVError.httpError(http.statusCode)
        }
    }

    public func download(path: String, ifNoneMatch etag: String? = nil) async throws -> (Data, String?)? {
        var headers: [String: String] = [:]
        if let etag = etag { headers["If-None-Match"] = etag }
        let request = makeRequest(method: "GET", path: path, headers: headers)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.invalidResponse }
        if http.statusCode == 304 { return nil }
        if http.statusCode == 404 { throw WebDAVError.notFound }
        guard http.statusCode == 200 else { throw WebDAVError.httpError(http.statusCode) }
        let newEtag = http.value(forHTTPHeaderField: "ETag")
        return (data, newEtag)
    }

    public func upload(path: String, data: Data, ifMatch etag: String? = nil) async throws -> String? {
        var headers: [String: String] = ["Content-Type": "application/json"]
        if let etag = etag { headers["If-Match"] = etag }
        let request = makeRequest(method: "PUT", path: path, headers: headers, body: data)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.invalidResponse }
        if http.statusCode == 412 { throw WebDAVError.preconditionFailed }
        guard (200..<300).contains(http.statusCode) else {
            throw WebDAVError.httpError(http.statusCode)
        }
        return http.value(forHTTPHeaderField: "ETag")
    }

    public func delete(path: String, ifMatch etag: String? = nil) async throws {
        var headers: [String: String] = [:]
        if let etag = etag { headers["If-Match"] = etag }
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