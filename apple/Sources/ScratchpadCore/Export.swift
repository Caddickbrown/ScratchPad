import Foundation

/// Exports (spec section 6). Text formats match linux/src/markdown.ts.
public enum TodoExportScope: String, CaseIterable, Identifiable, Sendable {
    case thisSheet, todaysSheets, everyOpen
    public var id: String { rawValue }
    public var label: String {
        switch self { case .thisSheet: return "This sheet"; case .todaysSheets: return "All of today's sheets"; case .everyOpen: return "Every open to-do" }
    }

    /// Sheets the scope covers.
    public func sheets(current: Pad?, all: [Pad], today: String) -> [Pad] {
        switch self {
        case .thisSheet: return current.map { [$0] } ?? []
        case .todaysSheets: return all.filter { $0.date == today }
        case .everyOpen: return all
        }
    }
}

public enum ExportMarkdown {
    static func sortedNewestFirst(_ sheets: [Pad]) -> [Pad] { sheets.sorted(by: PadStore.newestFirst) }

    public static func todoLine(_ t: Todo) -> String {
        "- [\(t.status == .done ? "x" : " ")] \(t.text.trimmingCharacters(in: .whitespacesAndNewlines))\(t.status == .deferred ? " (deferred)" : "")"
    }

    /// One section per sheet, newest first, blank line between sections:
    /// `## <title or "Untitled sheet">, <ddd d MMM yyyy | Pinned>` then the checkbox list.
    /// `openOnly` (Every open to-do) keeps open rows (and deferred when ticked) and omits empty sections;
    /// empty sections are also dropped when several sheets are exported.
    public static func todos(_ sheets: [Pad], includeDone: Bool = false, includeDeferred: Bool = true, openOnly: Bool = false) -> String {
        var sections: [String] = []
        for p in sortedNewestFirst(sheets) {
            let rows = p.todos.filter(\.isFilled).filter { t in
                switch t.status {
                case .open: return true
                case .deferred: return includeDeferred
                case .done: return !openOnly && includeDone
                }
            }
            if rows.isEmpty && (openOnly || sheets.count > 1) { continue }
            sections.append((["## \(p.displayTitle), \(DayLabel.longDate(p.date))", ""] + rows.map(todoLine)).joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n") + "\n"
    }

    static func escapeCell(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }

    /// GFM table with computed values; the first row is the header.
    public static func table(_ rows: [[String]]) -> String {
        guard !rows.isEmpty else { return "" }
        let eval = TableEvaluator(rows: rows)
        let cols = max(1, eval.columnCount)
        func line(_ r: Int) -> String {
            "| " + (0..<cols).map { c in escapeCell(c < rows[r].count ? eval.display(row: r, col: c) : "") }.joined(separator: " | ") + " |"
        }
        var out = [line(0), "| " + Array(repeating: "---", count: cols).joined(separator: " | ") + " |"]
        for r in 1..<rows.count { out.append(line(r)) }
        return out.joined(separator: "\n")
    }

    /// Blocks in reading order: y, then x.
    public static func readingOrder(_ blocks: [Block]) -> [Block] {
        blocks.enumerated().sorted { a, b in
            if a.element.y != b.element.y { return a.element.y < b.element.y }
            if a.element.x != b.element.x { return a.element.x < b.element.x }
            return a.offset < b.offset
        }.map(\.element)
    }

    public static func sheet(_ p: Pad) -> String {
        let tagLine = p.tags.isEmpty ? "" : " · " + p.tags.map { "#\($0)" }.joined(separator: " ")
        var out = ["# \(p.displayTitle)", "", "_\(DayLabel.longDate(p.date))\(tagLine)_"]
        for b in readingOrder(p.blocks) {
            out.append("")
            switch b.kind {
            case .text: out.append((b.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
            case .code: out += ["```" + (b.language ?? ""), b.text ?? "", "```"]
            case .table:
                if let c = b.caption, !c.isEmpty { out += ["**\(c)**", ""] }
                out.append(table(b.rows ?? []))
            case .image: out.append("![\(b.caption ?? "")](\(b.asset ?? ""))")
            case .file: out.append("[\(b.name ?? "file")](\(b.asset ?? ""))")
            case .link:
                let title = (b.text ?? "").isEmpty ? (b.url ?? "") : b.text!
                out.append("[\(title)](\(b.url ?? ""))")
            case .divider: out.append("---")
            }
        }
        let todos = p.todos.filter(\.isFilled)
        if !todos.isEmpty { out += ["", "## To-do", ""] + todos.map(todoLine) }
        return out.joined(separator: "\n")
    }

    /// Everything, one Markdown file: sheets newest first, separated by a rule.
    public static func everything(_ sheets: [Pad]) -> String {
        sortedNewestFirst(sheets).map(sheet).joined(separator: "\n\n---\n\n") + "\n"
    }
}

public enum EverythingFormat: String, CaseIterable, Identifiable, Sendable {
    case archive, markdown, json
    public var id: String { rawValue }
    public var label: String {
        switch self { case .archive: return "Scratchpad archive"; case .markdown: return "Markdown"; case .json: return "JSON" }
    }
    public var fileExtension: String {
        switch self { case .archive: return "scratchpad"; case .markdown: return "md"; case .json: return "json" }
    }
}

/// `.scratchpad` archive: `{ format, v, exportedAt, sheets, assets: { "assets/<file>": base64 } }`.
public struct ScratchpadArchive: Codable, Equatable, Sendable {
    public static let formatName = "scratchpad-archive"

    public var format: String
    public var v: Int
    public var exportedAt: Date
    public var sheets: [Pad]
    public var assets: [String: String]

    public init(sheets: [Pad], assets: [String: String], exportedAt: Date = Date()) {
        self.format = ScratchpadArchive.formatName; self.v = 1; self.exportedAt = exportedAt
        self.sheets = sheets; self.assets = assets
    }

    public enum ArchiveError: Error, LocalizedError {
        case notAnArchive
        public var errorDescription: String? { "This file is not a Scratchpad archive." }
    }

    public struct ImportResult: Equatable, Sendable {
        public var sheets: Int
        public var overwritten: Int
        public var assetsWritten: Int
        public var skipped: Int
    }

    /// Asset keys must be a plain file directly under assets/.
    public static func isSafeAssetPath(_ path: String) -> Bool {
        path.range(of: #"^assets/[A-Za-z0-9][A-Za-z0-9._-]{0,200}$"#, options: .regularExpression) != nil && !path.contains("..")
    }

    /// Builds an archive of `sheets`, embedding every asset they reference that exists in the store.
    public static func build(sheets: [Pad], store: PadStore, now: Date = Date()) -> ScratchpadArchive {
        var assets: [String: String] = [:]
        for p in sheets {
            for b in p.blocks {
                guard let a = b.asset, isSafeAssetPath(a), assets[a] == nil,
                      let data = try? Data(contentsOf: store.assetURL(a)) else { continue }
                assets[a] = data.base64EncodedString()
            }
        }
        return ScratchpadArchive(sheets: sheets.map(\.compacted).sorted(by: PadStore.newestFirst), assets: assets, exportedAt: now)
    }

    public func encoded() throws -> Data { try PadJSON.encoder.encode(self) }

    public static func decode(_ data: Data) throws -> ScratchpadArchive {
        guard let a = try? PadJSON.decoder.decode(ScratchpadArchive.self, from: data), a.format == formatName else {
            throw ArchiveError.notAnArchive
        }
        return a
    }

    /// Merges into the store: sheets with an existing id are overwritten, assets written only if missing.
    /// Invalid ids and unsafe asset paths are skipped.
    @discardableResult
    public func importInto(_ store: PadStore) throws -> ImportResult {
        var result = ImportResult(sheets: 0, overwritten: 0, assetsWritten: 0, skipped: 0)
        let existing = Set(try store.list().map(\.id))
        for s in sheets {
            guard SheetID.isValid(s.id) else { result.skipped += 1; continue }
            if existing.contains(s.id) { result.overwritten += 1 }
            try store.save(s, touch: false)
            result.sheets += 1
        }
        for (path, b64) in assets.sorted(by: { $0.key < $1.key }) {
            guard ScratchpadArchive.isSafeAssetPath(path), let data = Data(base64Encoded: b64) else { result.skipped += 1; continue }
            let url = store.assetURL(path)
            if FileManager.default.fileExists(atPath: url.path) { continue }
            try data.write(to: url, options: .atomic)
            result.assetsWritten += 1
        }
        return result
    }
}

public enum ExportJSON {
    /// Everything as JSON: an array of v2 sheets, newest first.
    public static func sheets(_ sheets: [Pad]) throws -> Data {
        try PadJSON.encoder.encode(sheets.map(\.compacted).sorted(by: PadStore.newestFirst))
    }
}
