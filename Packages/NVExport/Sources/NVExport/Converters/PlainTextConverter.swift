import Foundation
import NVModel

public enum PlainTextConverter {
    public static func convert(_ note: Note) throws -> ExportContent {
        var output = ""
        if !note.title.isEmpty {
            output += note.title + "\n\n"
        }
        output += note.body
        return .text(output)
    }
}