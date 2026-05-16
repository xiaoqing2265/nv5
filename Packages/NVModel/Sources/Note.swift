import Foundation

public struct Note: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var body: String
    public var bodyAttributes: Data?
    public var labels: Set<String>
    public var createdAt: Date
    public var modifiedAt: Date
    public var lastSelectedRange: NSRange?
    public var isEncrypted: Bool
    public var etag: String?
    public var remotePath: String?
    public var lastSyncedAt: Date?
    public var localDirty: Bool
    public var deletedLocally: Bool
    public var archived: Bool

    public init(
        id: UUID = UUID(),
        title: String = "",
        body: String = "",
        bodyAttributes: Data? = nil,
        labels: Set<String> = [],
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        lastSelectedRange: NSRange? = nil,
        isEncrypted: Bool = false,
        etag: String? = nil,
        remotePath: String? = nil,
        lastSyncedAt: Date? = nil,
        localDirty: Bool = true,
        deletedLocally: Bool = false,
        archived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.bodyAttributes = bodyAttributes
        self.labels = labels
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.lastSelectedRange = lastSelectedRange
        self.isEncrypted = isEncrypted
        self.etag = etag
        self.remotePath = remotePath
        self.lastSyncedAt = lastSyncedAt
        self.localDirty = localDirty
        self.deletedLocally = deletedLocally
        self.archived = archived
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    enum CodingKeys: String, CodingKey {
        case id, title, body, bodyAttributes, labels
        case createdAt, modifiedAt
        case lastSelectedLocation, lastSelectedLength, isEncrypted
        case etag, remotePath, lastSyncedAt, localDirty, deletedLocally, archived
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        bodyAttributes = try container.decodeIfPresent(Data.self, forKey: .bodyAttributes)
        labels = try container.decode(Set<String>.self, forKey: .labels)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        let location = try container.decodeIfPresent(Int.self, forKey: .lastSelectedLocation)
        let length = try container.decodeIfPresent(Int.self, forKey: .lastSelectedLength)
        if let loc = location, let len = length {
            lastSelectedRange = NSRange(location: loc, length: len)
        } else {
            lastSelectedRange = nil
        }
        isEncrypted = try container.decode(Bool.self, forKey: .isEncrypted)
        etag = try container.decodeIfPresent(String.self, forKey: .etag)
        remotePath = try container.decodeIfPresent(String.self, forKey: .remotePath)
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        localDirty = try container.decode(Bool.self, forKey: .localDirty)
        deletedLocally = try container.decode(Bool.self, forKey: .deletedLocally)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encodeIfPresent(bodyAttributes, forKey: .bodyAttributes)
        try container.encode(labels, forKey: .labels)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(modifiedAt, forKey: .modifiedAt)
        try container.encodeIfPresent(lastSelectedRange?.location, forKey: .lastSelectedLocation)
        try container.encodeIfPresent(lastSelectedRange?.length, forKey: .lastSelectedLength)
        try container.encode(isEncrypted, forKey: .isEncrypted)
        try container.encodeIfPresent(etag, forKey: .etag)
        try container.encodeIfPresent(remotePath, forKey: .remotePath)
        try container.encodeIfPresent(lastSyncedAt, forKey: .lastSyncedAt)
        try container.encode(localDirty, forKey: .localDirty)
        try container.encode(deletedLocally, forKey: .deletedLocally)
        try container.encode(archived, forKey: .archived)
    }
}