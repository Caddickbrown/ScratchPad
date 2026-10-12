import Foundation

/// Everything a clipboard or drop can hand us, already reduced to plain values.
public struct ClipboardContents: Sendable {
    public var plain: String?
    public var html: String?
    public var fileURLs: [URL]
    public var imageData: Data?
    public var imageExtension: String

    public init(plain: String? = nil, html: String? = nil, fileURLs: [URL] = [], imageData: Data? = nil, imageExtension: String = "png") {
        self.plain = plain; self.html = html; self.fileURLs = fileURLs; self.imageData = imageData; self.imageExtension = imageExtension
    }
}

/// What a paste becomes, before it is placed and before any asset is written.
public enum PasteResult: Equatable, Sendable {
    case text(String)
    case code(String, language: String?)
    case link(url: String, title: String?)
    case table([[String]])
    case image(Data, ext: String)
    case file(URL)

    public var kind: BlockKind {
        switch self {
        case .text: return .text; case .code: return .code; case .link: return .link
        case .table: return .table; case .image: return .image; case .file: return .file
        }
    }
}

/// Components board, left column: the clipboard type picks the block. Order matters: files and images win,
/// then HTML tables, then TSV, then URLs, then fenced code, then plain text.
public enum PasteClassifier {
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff"]

    public static func classify(_ c: ClipboardContents) -> [PasteResult] {
        if !c.fileURLs.isEmpty {
            return c.fileURLs.map { url in
                if imageExtensions.contains(url.pathExtension.lowercased()), let data = try? Data(contentsOf: url) {
                    return .image(data, ext: url.pathExtension.lowercased())
                }
                return .file(url)
            }
        }
        if let data = c.imageData { return [.image(data, ext: c.imageExtension)] }
        if let html = c.html, let rows = TableParser.rows(fromHTML: html), rows.count >= 1 { return [.table(rows)] }
        guard let plain = c.plain?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty else { return [] }
        if let rows = TableParser.rows(fromTSV: plain) { return [.table(rows)] }
        if let url = singleURL(plain) { return [.link(url: url, title: nil)] }
        if let code = fenced(plain) { return [.code(code.body, language: code.lang)] }
        return [.text(plain)]
    }

    static func singleURL(_ s: String) -> String? {
        guard !s.contains("\n"), !s.contains(" "), let url = URL(string: s),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else { return nil }
        return s
    }

    static func fenced(_ s: String) -> (body: String, lang: String?)? {
        guard s.hasPrefix("```"), s.hasSuffix("```"), s.count > 6 else { return nil }
        let inner = String(s.dropFirst(3).dropLast(3))
        guard let nl = inner.firstIndex(of: "\n") else { return nil }
        let lang = String(inner[..<nl]).trimmingCharacters(in: .whitespaces)
        let body = String(inner[inner.index(after: nl)...]).trimmingCharacters(in: .newlines)
        return (body, lang.isEmpty ? nil : lang)
    }
}

public enum TableParser {
    /// Tab-separated text with at least two rows and a consistent column count is a table.
    public static func rows(fromTSV s: String) -> [[String]]? {
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 2, lines.allSatisfy({ $0.contains("\t") }) else { return nil }
        let rows = lines.map { $0.split(separator: "\t", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) } }
        let cols = rows[0].count
        guard cols >= 2, rows.allSatisfy({ $0.count == cols }) else { return nil }
        return rows
    }

    /// Minimal HTML table reader: first <table>, each <tr>, each <td>/<th>, tags stripped, entities decoded.
    public static func rows(fromHTML html: String) -> [[String]]? {
        guard let table = firstMatch(#"(?is)<table\b.*?</table>"#, in: html) else { return nil }
        let trs = allMatches(#"(?is)<tr\b.*?</tr>"#, in: table)
        var rows: [[String]] = []
        for tr in trs {
            let cells = allMatches(#"(?is)<t[dh]\b[^>]*>(.*?)</t[dh]>"#, in: tr, group: 1).map { cell in
                decodeEntities(cell.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !cells.isEmpty { rows.append(cells) }
        }
        guard !rows.isEmpty else { return nil }
        let cols = rows.map(\.count).max() ?? 0
        return rows.map { $0 + Array(repeating: "", count: cols - $0.count) }
    }

    static func firstMatch(_ pattern: String, in s: String) -> String? {
        guard let r = s.range(of: pattern, options: .regularExpression) else { return nil }
        return String(s[r])
    }

    static func allMatches(_ pattern: String, in s: String, group: Int = 0) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let r = m.range(at: group)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }

    static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&nbsp;", with: " ")
         .replacingOccurrences(of: "&amp;", with: "&")
         .replacingOccurrences(of: "&lt;", with: "<")
         .replacingOccurrences(of: "&gt;", with: ">")
         .replacingOccurrences(of: "&quot;", with: "\"")
         .replacingOccurrences(of: "&#39;", with: "'")
    }
}
