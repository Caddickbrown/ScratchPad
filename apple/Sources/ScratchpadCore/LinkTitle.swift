import Foundation

/// Page title for a pasted link. Best effort: 5 s timeout, first 256 KB, http(s) only.
public enum LinkTitle {
    public static func fetch(_ urlString: String) async -> String? {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.setValue("Scratchpad/0.1", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        let html = String(decoding: data.prefix(256 * 1024), as: UTF8.self)
        return parse(html)
    }

    /// `<title>` text, entities decoded and whitespace collapsed.
    public static func parse(_ html: String) -> String? {
        guard let r = html.range(of: #"(?is)<title\b[^>]*>(.*?)</title>"#, options: .regularExpression) else { return nil }
        let inner = String(html[r]).replacingOccurrences(of: #"(?is)^<title\b[^>]*>|</title>$"#, with: "", options: .regularExpression)
        let text = TableParser.decodeEntities(inner).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return text.isEmpty ? nil : text
    }
}
