import Foundation

enum MultistatusParser {
    static func parse(_ data: Data, baseURL: URL) throws -> [WebDAVResource] {
        let delegate = ParserDelegate(baseURL: baseURL)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        guard parser.parse() else { throw WebDAVError.parseFailed }
        return delegate.resources
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        let baseURL: URL
        var resources: [WebDAVResource] = []

        private var currentHref: String?
        private var currentEtag: String?
        private var currentLastModified: Date?
        private var currentLength: Int64 = 0
        private var currentIsDirectory = false
        private var currentText = ""

        private let httpDateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }()

        init(baseURL: URL) { self.baseURL = baseURL }

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes: [String: String]) {
            currentText = ""
            if elementName == "response" {
                currentHref = nil
                currentEtag = nil
                currentLastModified = nil
                currentLength = 0
                currentIsDirectory = false
            } else if elementName == "collection" {
                currentIsDirectory = true
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            currentText += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            switch elementName {
            case "href":
                currentHref = trimmed.removingPercentEncoding
            case "getetag":
                currentEtag = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            case "getlastmodified":
                currentLastModified = httpDateFormatter.date(from: trimmed)
            case "getcontentlength":
                currentLength = Int64(trimmed) ?? 0
            case "response":
                if let href = currentHref {
                    let basePath = baseURL.path
                    var relative = href
                    if let range = href.range(of: basePath) {
                        relative = String(href[range.upperBound...])
                    }
                    relative = relative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    if !relative.isEmpty {
                        resources.append(WebDAVResource(
                            path: relative,
                            etag: currentEtag,
                            lastModified: currentLastModified,
                            contentLength: currentLength,
                            isDirectory: currentIsDirectory
                        ))
                    }
                }
            default: break
            }
        }
    }
}