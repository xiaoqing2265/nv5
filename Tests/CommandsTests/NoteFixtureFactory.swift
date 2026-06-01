import Foundation
import NVModel

enum NoteFixtureFactory {
    enum BodySize {
        case short
        case medium
        case large

        var byteCount: Int {
            switch self {
            case .short: 160
            case .medium: 2_048
            case .large: 10_240
            }
        }
    }

    static func notes(
        count: Int,
        bodySize: BodySize,
        matchingEvery stride: Int = 10,
        token: String = "needle",
        labelEvery labelStride: Int = 7
    ) -> [Note] {
        (0..<count).map { index in
            var note = Note(
                id: deterministicUUID(index),
                title: index.isMultiple(of: stride) ? "Fixture \(index) \(token)" : "Fixture \(index)",
                body: body(index: index, targetBytes: bodySize.byteCount, token: index.isMultiple(of: stride) ? token : nil),
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                modifiedAt: Date(timeIntervalSince1970: TimeInterval(count - index))
            )
            if index.isMultiple(of: labelStride) {
                note.labels = ["label-\(index % 5)", token]
            } else {
                note.labels = ["label-\(index % 5)"]
            }
            return note
        }
    }

    private static func deterministicUUID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }

    private static func body(index: Int, targetBytes: Int, token: String?) -> String {
        let seed = "Body \(index) swift markdown notes sync editor "
        var text = seed
        while text.utf8.count < targetBytes {
            text += seed
        }
        if let token {
            text += " \(token)"
        }
        return text
    }
}
