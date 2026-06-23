import AppKit

enum TextDecoratorPipeline {
    /// 编辑时的实时装饰：通过 NSLayoutManager 临时属性实现，不修改 NSTextStorage，
    /// 避免 processEditing → 全文重排 → 闪动。仅 .link（用于点击跳转）写入 storage。
    static func runInteractive(on storage: NSTextStorage) {
        guard let layoutManager = storage.layoutManagers.first else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return }

        let theme = EditorTheme(rawValue: UserDefaults.standard.string(forKey: "editorTheme") ?? "system") ?? .system
        let fgColor = theme.editorForeground

        let baseFontName = UserDefaults.standard.string(forKey: "editorFont") ?? "Menlo"
        let storedSize = UserDefaults.standard.double(forKey: "editorFontSize")
        let baseFontSize = CGFloat(storedSize > 0 ? storedSize : 14)
        let baseFont = NSFont(name: baseFontName, size: baseFontSize)
            ?? .monospacedSystemFont(ofSize: baseFontSize, weight: .regular)

        // 清空旧的临时属性（不触发 processEditing，只 invalidate display）
        layoutManager.removeTemporaryAttribute(.font, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.strikethroughStyle, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)

        // 基础字体与前景色（覆盖全文，display-only）
        layoutManager.addTemporaryAttribute(.font, value: baseFont, forCharacterRange: fullRange)
        layoutManager.addTemporaryAttribute(.foregroundColor, value: fgColor, forCharacterRange: fullRange)

        // Markdown 标题：按行覆盖字体
        let content = storage.string as NSString
        content.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = content.substring(with: lineRange)
            let hashes = line.prefix { $0 == "#" }
            guard !hashes.isEmpty, hashes.count <= 6,
                  line.count > hashes.count,
                  line[line.index(line.startIndex, offsetBy: hashes.count)] == " " else { return }
            let size: CGFloat = max(14, 26 - CGFloat(hashes.count * 2))
            layoutManager.addTemporaryAttribute(.font, value: NSFont.boldSystemFont(ofSize: size), forCharacterRange: lineRange)
        }

        // [done]/[x]/[✓] 行：临时删除线 + 灰色前景
        if let regex = try? NSRegularExpression(pattern: #"\[(?:done|x|✓)\]"#, options: .caseInsensitive) {
            regex.enumerateMatches(in: storage.string, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                let lineRange = content.lineRange(for: match.range)
                layoutManager.addTemporaryAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: lineRange)
                layoutManager.addTemporaryAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, forCharacterRange: lineRange)
            }
        }

        // Wiki 链接：仅 .link 写 storage（点击跳转需要），下划线/颜色走临时属性。
        // 临时属性的优先级高于 storage 属性（display 层覆盖），无需清除 storage 中的
        // .underlineStyle / .foregroundColor；只需更新可点击区域 (.link)。
        let text = storage.string
        storage.beginEditing()
        defer { storage.endEditing() }
        storage.removeAttribute(.link, range: fullRange)

        if text.contains("[["), let regex = try? NSRegularExpression(pattern: #"\[\[([^\[\]]+)\]\]"#) {
            let nsText = text as NSString
            regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match, match.numberOfRanges > 1 else { return }
                let title = nsText.substring(with: match.range(at: 1))
                let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
                if let url = URL(string: "nv5://note/\(encoded)") {
                    storage.addAttribute(.link, value: url, range: match.range)
                }
                layoutManager.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: match.range)
                layoutManager.addTemporaryAttribute(.foregroundColor, value: NSColor.systemPurple, forCharacterRange: match.range)
            }
        }
    }

    /// 序列化用（RTFD 快照）：在副本 storage 上写入完整属性，不修改 live storage。
    static func runAll(on storage: NSTextStorage) {
        runAllAttributes(on: storage)
        let makeLinks = UserDefaults.standard.object(forKey: "makeLinksClickable")
                            .flatMap { $0 as? Bool } ?? true
        guard makeLinks else { return }
        storage.beginEditing()
        defer { storage.endEditing() }
        LinkDecorator.decorate(storage)
    }

    private static func runAllAttributes(on storage: NSTextStorage) {
        storage.beginEditing()
        defer { storage.endEditing() }

        let fgColor: NSColor = {
            let theme = EditorTheme(rawValue: UserDefaults.standard.string(forKey: "editorTheme") ?? "system") ?? .system
            return theme.editorForeground
        }()

        let fullRange = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: fullRange)
        storage.addAttribute(.foregroundColor, value: fgColor, range: fullRange)
        storage.removeAttribute(.strikethroughStyle, range: fullRange)
        storage.removeAttribute(.link, range: fullRange)
        storage.removeAttribute(.underlineStyle, range: fullRange)

        MarkdownHeadingDecorator.decorate(storage)
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
            let lineRange = nsString.lineRange(for: match.range)
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: lineRange)
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: lineRange)
        }
    }
}
