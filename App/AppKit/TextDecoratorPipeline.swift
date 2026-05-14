import AppKit

enum TextDecoratorPipeline {
    static func runAll(on storage: NSTextStorage) {
        storage.beginEditing()
        defer { storage.endEditing() }

        let fullRange = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: fullRange)
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
        storage.removeAttribute(.strikethroughStyle, range: fullRange)
        storage.removeAttribute(.link, range: fullRange)
        storage.removeAttribute(.underlineStyle, range: fullRange)

        MarkdownHeadingDecorator.decorate(storage)
        LinkDecorator.decorate(storage)
        WikiLinkDecorator.decorate(storage)
        DoneTagDecorator.decorate(storage)
    }
}

enum MarkdownHeadingDecorator {
    static func decorate(_ storage: NSTextStorage) {
        let content = storage.string as NSString
        content.enumerateSubstrings(in: NSRange(location: 0, length: content.length),
                                     options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = content.substring(with: lineRange)
            let hashes = line.prefix { $0 == "#" }
            guard !hashes.isEmpty, hashes.count <= 6,
                  line.count > hashes.count, line[line.index(line.startIndex, offsetBy: hashes.count)] == " " else {
                return
            }
            let level = hashes.count
            let size: CGFloat = max(14, 26 - CGFloat(level * 2))
            storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: size), range: lineRange)
        }
    }
}

enum LinkDecorator {
    static func decorate(_ storage: NSTextStorage) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }
        let range = NSRange(location: 0, length: storage.length)
        detector.enumerateMatches(in: storage.string, options: [], range: range) { match, _, _ in
            guard let match = match, let url = match.url else { return }
            storage.addAttribute(.link, value: url, range: match.range)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: match.range)
        }
    }
}

enum WikiLinkDecorator {
    static func decorate(_ storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\[\]]+)\]\]"#) else { return }
        let range = NSRange(location: 0, length: storage.length)
        let nsString = storage.string as NSString
        regex.enumerateMatches(in: storage.string, options: [], range: range) { match, _, _ in
            guard let match = match, match.numberOfRanges > 1 else { return }
            let title = nsString.substring(with: match.range(at: 1))
            let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
            if let url = URL(string: "nv5://note/\(encoded)") {
                storage.addAttribute(.link, value: url, range: match.range)
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
                storage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: match.range)
            }
        }
    }
}

enum DoneTagDecorator {
    static func decorate(_ storage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: #"\[(?:done|x|✓)\]"#, options: .caseInsensitive) else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        let nsString = storage.string as NSString

        regex.enumerateMatches(in: storage.string, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            // Extend strikethrough to the whole line containing the tag
            let lineRange = nsString.lineRange(for: match.range)
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: lineRange)
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: lineRange)
        }
    }
}