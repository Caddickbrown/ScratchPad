import Foundation

/// Shared JSON model, file format v2. Mirrors shared/schema/pad.schema.json and linux/src/model.ts.
/// UI copy says "sheet"; the type stays `Pad` for continuity with the file format.
public let gridSize = 24

public enum BlockKind: String, Codable, CaseIterable, Sendable {
    case text, table, image, file, link, code, divider

    /// "Text", "Table"... for the undo toast and menus.
    public var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

public enum BlockFont: String, Codable, CaseIterable, Identifiable, Sendable {
    case sans, serif, mono, hand
    public var id: String { rawValue }
    public var label: String {
        switch self { case .sans: return "Sans"; case .serif: return "Serif"; case .mono: return "Mono"; case .hand: return "Hand" }
    }
}

public struct Block: Codable, Identifiable, Equatable, Sendable {
    public static let minWidth = 48
    public static let minHeight = 24
    public static let fontSizeRange = 10...48
    public static let defaultFontSize = 14

    public var id: String
    public var kind: BlockKind
    public var x: Int
    public var y: Int
    public var w: Int
    /// Null means content height. Set by a corner resize.
    public var h: Int?
    public var text: String?
    public var rows: [[String]]?
    public var asset: String?
    public var name: String?
    public var size: Int?
    public var url: String?
    public var caption: String?
    public var language: String?
    /// Degrees, normalised to (-180, 180].
    public var rotation: Double
    public var font: BlockFont
    public var fontSize: Int
    public var bold: Bool
    public var italic: Bool
    /// Tables only: px per column.
    public var colWidths: [Int]?

    public init(id: String = UUID().uuidString, kind: BlockKind, x: Int, y: Int, w: Int, h: Int? = nil,
                text: String? = nil, rows: [[String]]? = nil, asset: String? = nil, name: String? = nil,
                size: Int? = nil, url: String? = nil, caption: String? = nil, language: String? = nil,
                rotation: Double = 0, font: BlockFont = .sans, fontSize: Int = Block.defaultFontSize,
                bold: Bool = false, italic: Bool = false, colWidths: [Int]? = nil) {
        self.id = id; self.kind = kind; self.x = x; self.y = y; self.w = w; self.h = h
        self.text = text; self.rows = rows; self.asset = asset; self.name = name
        self.size = size; self.url = url; self.caption = caption; self.language = language
        self.rotation = rotation; self.font = font; self.fontSize = fontSize
        self.bold = bold; self.italic = italic; self.colWidths = colWidths
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, x, y, w, h, text, rows, asset, name, size, url, caption, language
        case rotation, font, fontSize, bold, italic, colWidths
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(BlockKind.self, forKey: .kind)
        x = try c.decode(Int.self, forKey: .x)
        y = try c.decode(Int.self, forKey: .y)
        w = try c.decode(Int.self, forKey: .w)
        h = try c.decodeIfPresent(Int.self, forKey: .h)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        rows = try c.decodeIfPresent([[String]].self, forKey: .rows)
        asset = try c.decodeIfPresent(String.self, forKey: .asset)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        size = try c.decodeIfPresent(Int.self, forKey: .size)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        rotation = Block.normalizedRotation(try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0)
        font = (try? c.decodeIfPresent(BlockFont.self, forKey: .font)) ?? .sans
        let fs = try c.decodeIfPresent(Int.self, forKey: .fontSize) ?? Block.defaultFontSize
        fontSize = min(max(fs, Block.fontSizeRange.lowerBound), Block.fontSizeRange.upperBound)
        bold = try c.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        italic = try c.decodeIfPresent(Bool.self, forKey: .italic) ?? false
        colWidths = try c.decodeIfPresent([Int].self, forKey: .colWidths)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(w, forKey: .w)
        if let h { try c.encode(h, forKey: .h) } else { try c.encodeNil(forKey: .h) }
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(rows, forKey: .rows)
        try c.encodeIfPresent(asset, forKey: .asset)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(size, forKey: .size)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(caption, forKey: .caption)
        try c.encodeIfPresent(language, forKey: .language)
        try c.encode(rotation, forKey: .rotation)
        try c.encode(font, forKey: .font)
        try c.encode(fontSize, forKey: .fontSize)
        try c.encode(bold, forKey: .bold)
        try c.encode(italic, forKey: .italic)
        try c.encodeIfPresent(colWidths, forKey: .colWidths)
    }

    /// Snaps the origin to the dot grid.
    public mutating func snap() {
        x = max(0, Block.snapped(x)); y = max(0, Block.snapped(y)); w = max(2 * gridSize, Block.snapped(w))
    }

    public static func snapped(_ v: Int) -> Int {
        Int((Double(v) / Double(gridSize)).rounded()) * gridSize
    }

    /// Degrees into (-180, 180], rounded to 0.1.
    public static func normalizedRotation(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        var r = degrees.truncatingRemainder(dividingBy: 360)
        if r <= -180 { r += 360 }
        if r > 180 { r -= 360 }
        r = (r * 10).rounded() / 10
        return r == -180 ? 180 : (r == 0 ? 0 : r)
    }

    /// Toolbar click: +15 degrees.
    public mutating func rotateStep() { rotation = Block.normalizedRotation(rotation + 15) }

    /// Copy offset by one grid step each way, with a fresh id.
    public func duplicated(id newID: String = UUID().uuidString) -> Block {
        var b = self
        b.id = newID
        b.x += gridSize
        b.y += gridSize
        return b
    }

    /// Corner resize result. `corner` is which handle moved; dx/dy are pointer deltas in canvas points.
    /// Left and top corners move the origin. `keepAspect` (Shift) scales h with w. Min 48 x 24.
    public func resized(corner: Corner, dx: Double, dy: Double, startHeight: Double, keepAspect: Bool) -> Block {
        var b = self
        let w0 = Double(w), h0 = max(Double(Block.minHeight), startHeight)
        var nw = corner.isLeft ? w0 - dx : w0 + dx
        var nh = corner.isTop ? h0 - dy : h0 + dy
        if keepAspect, w0 > 0 { nh = nw * h0 / w0 }
        nw = max(Double(Block.minWidth), nw)
        nh = max(Double(Block.minHeight), nh)
        if keepAspect, w0 > 0 { nh = max(Double(Block.minHeight), nw * h0 / w0) }
        if corner.isLeft { b.x = Int((Double(x) + w0 - nw).rounded()) }
        if corner.isTop { b.y = Int((Double(y) + h0 - nh).rounded()) }
        b.w = Int(nw.rounded())
        b.h = Int(nh.rounded())
        b.x = max(0, b.x); b.y = max(0, b.y)
        return b
    }

    public enum Corner: CaseIterable, Sendable {
        case topLeft, topRight, bottomLeft, bottomRight
        public var isLeft: Bool { self == .topLeft || self == .bottomLeft }
        public var isTop: Bool { self == .topLeft || self == .topRight }
    }
}

public enum TodoStatus: String, Codable, Sendable {
    case open, done, deferred

    /// Click order from the design: open, done, deferred, open.
    public var next: TodoStatus {
        switch self { case .open: return .done; case .done: return .deferred; case .deferred: return .open }
    }
}

public struct Todo: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var status: TodoStatus
    public var createdAt: Date
    public var carriedFrom: String?

    public init(id: String = UUID().uuidString, text: String = "", status: TodoStatus = .open,
                createdAt: Date = Date(), carriedFrom: String? = nil) {
        self.id = id; self.text = text; self.status = status; self.createdAt = createdAt; self.carriedFrom = carriedFrom
    }

    enum CodingKeys: String, CodingKey { case id, text, status, createdAt, carriedFrom }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(status, forKey: .status)
        try c.encode(createdAt, forKey: .createdAt)
        if let carriedFrom { try c.encode(carriedFrom, forKey: .carriedFrom) } else { try c.encodeNil(forKey: .carriedFrom) }
    }

    /// Non-empty after trimming. Only filled rows count, carry and export.
    public var isFilled: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Open, non-empty and three or more days old counts as overdue.
    public func isOverdue(now: Date = Date()) -> Bool {
        status == .open && isFilled && now.timeIntervalSince(createdAt) >= 3 * 86_400
    }
}

public struct Pad: Codable, Identifiable, Equatable, Sendable {
    public static let formatVersion = 2

    /// Always 2 once decoded; kept as a field so the JSON carries it.
    public var v: Int = Pad.formatVersion
    public var id: String
    public var date: String?
    public var title: String
    public var tags: [String]
    public var pinned: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var blocks: [Block]
    public var todos: [Todo]

    public init(id: String, date: String?, title: String = "", tags: [String] = [], pinned: Bool = false,
                createdAt: Date = Date(), updatedAt: Date = Date(), blocks: [Block] = [], todos: [Todo] = []) {
        self.id = id; self.date = date; self.title = title; self.tags = Tags.normalized(tags); self.pinned = pinned
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.blocks = blocks; self.todos = todos
    }

    enum CodingKeys: String, CodingKey { case v, id, date, title, tag, tags, pinned, createdAt, updatedAt, blocks, todos }

    /// Reads v1 (`tag` string) and v2 (`tags` array). Missing fields take defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = Pad.formatVersion
        id = try c.decode(String.self, forKey: .id)
        date = try c.decodeIfPresent(String.self, forKey: .date)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        var raw: [String] = []
        if let tag = try c.decodeIfPresent(String.self, forKey: .tag) { raw.append(tag) }
        if let list = try c.decodeIfPresent([String].self, forKey: .tags) { raw += list }
        tags = Tags.normalized(raw)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? (date == nil)
        let now = Date()
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        blocks = try c.decodeIfPresent([Block].self, forKey: .blocks) ?? []
        todos = try c.decodeIfPresent([Todo].self, forKey: .todos) ?? []
    }

    /// Always writes v2: `v: 2`, `tags`, never `tag`.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Pad.formatVersion, forKey: .v)
        try c.encode(id, forKey: .id)
        if let date { try c.encode(date, forKey: .date) } else { try c.encodeNil(forKey: .date) }
        try c.encode(title, forKey: .title)
        try c.encode(tags, forKey: .tags)
        try c.encode(pinned, forKey: .pinned)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(todos, forKey: .todos)
    }

    /// A new dated sheet with a fresh `YYYY-MM-DD-xxxxxx` id.
    public static func dated(_ day: String, tags: [String] = [], title: String = "", now: Date = Date()) -> Pad {
        Pad(id: SheetID.make(for: day), date: day, title: title, tags: tags, createdAt: now, updatedAt: now)
    }

    /// v1 helper kept for tests and callers that want a sheet whose id is the bare day key.
    public static func daily(_ day: String, now: Date = Date()) -> Pad {
        Pad(id: day, date: day, createdAt: now, updatedAt: now)
    }

    public var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Untitled sheet" : t
    }

    /// Case-insensitive search across title, tags, id, block text, table cells, file names, URLs,
    /// captions and to-do text. A leading `#` searches tags the same way.
    public func matches(_ query: String) -> Bool {
        var q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.hasPrefix("#") { q.removeFirst() }
        if q.isEmpty { return true }
        func hit(_ s: String?) -> Bool { s?.lowercased().contains(q) ?? false }
        return hit(title) || tags.contains(where: hit) || hit(id)
            || blocks.contains { hit($0.text) || hit($0.name) || hit($0.url) || hit($0.caption) || ($0.rows?.contains { $0.contains(where: hit) } ?? false) }
            || todos.contains { hit($0.text) }
    }

    /// Moves the to-do with `id` so it sits before `beforeID` (or at the end when nil).
    public mutating func moveTodo(_ id: String, before beforeID: String?) {
        guard id != beforeID, let moving = todos.first(where: { $0.id == id }) else { return }
        todos.removeAll { $0.id == id }
        if let b = beforeID, let i = todos.firstIndex(where: { $0.id == b }) { todos.insert(moving, at: i) } else { todos.append(moving) }
    }

    public var doneCount: Int { todos.filter { $0.status == .done && $0.isFilled }.count }
    public var openCount: Int { todos.filter { $0.status == .open && $0.isFilled }.count }
    public var filledCount: Int { todos.filter { $0.isFilled }.count }
    /// Rows that would carry to tomorrow: open and deferred, non-empty.
    public var carryCount: Int { todos.filter { $0.status != .done && $0.isFilled }.count }

    /// "N of M done".
    public var countLabel: String { "\(doneCount) of \(filledCount) done" }

    /// To-do column footer copy.
    public var footerLabel: String {
        if filledCount == 0 { return "Nothing here yet" }
        if carryCount == 0 { return "Nothing to carry. Nice." }
        return "\(carryCount) open will carry to tomorrow"
    }

    /// Drops empty rows, for writing to disk.
    public var compacted: Pad {
        var p = self
        p.todos = todos.filter { !$0.text.isEmpty }
        return p
    }

    /// Duplicate this sheet: blocks and open to-dos copied with new ids, title + " copy".
    public func duplicate(id newID: String, now: Date = Date()) -> Pad {
        var p = Pad(id: newID, date: date, title: title + " copy", tags: tags, pinned: pinned, createdAt: now, updatedAt: now)
        p.blocks = blocks.map { b in var c = b; c.id = UUID().uuidString; return c }
        p.todos = todos.filter { $0.status == .open && $0.isFilled }.map {
            Todo(text: $0.text, status: .open, createdAt: $0.createdAt, carriedFrom: $0.carriedFrom)
        }
        return p
    }

    /// The same sheet on another date: unpinned, re-keyed to `date-suffix` (suffix kept when the id already has one).
    public func moved(to day: String) -> Pad {
        var p = self
        p.date = day
        p.pinned = false
        // The id stays put: it is the file name and other sheets' carriedFrom points at it.
        return p
    }
}

/// `YYYY-MM-DD-xxxxxx` ids for dated sheets, slugs for pinned ones.
public enum SheetID {
    static let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")

    public static func suffix<G: RandomNumberGenerator>(using rng: inout G) -> String {
        String((0..<6).map { _ in alphabet[Int.random(in: 0..<36, using: &rng)] })
    }

    public static func make(for day: String) -> String {
        var rng = SystemRandomNumberGenerator()
        return "\(day)-\(suffix(using: &rng))"
    }

    public static func isValid(_ id: String) -> Bool {
        id.range(of: #"^[A-Za-z0-9_-]{1,80}$"#, options: .regularExpression) != nil
    }

    /// True for `YYYY-MM-DD-xxxxxx`.
    public static func isDated(_ id: String) -> Bool {
        id.range(of: #"^\d{4}-\d{2}-\d{2}-[a-z0-9]{6}$"#, options: .regularExpression) != nil
    }

    /// Slug for a pinned sheet title, unique against `existing`.
    public static func slug(_ title: String, existing: Set<String> = []) -> String {
        var s = title.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if s.count > 60 { s = String(s.prefix(60)).trimmingCharacters(in: CharacterSet(charactersIn: "-")) }
        if s.isEmpty {
            var rng = SystemRandomNumberGenerator()
            s = "sheet-\(suffix(using: &rng))"
        }
        var candidate = s, n = 2
        while existing.contains(candidate) { candidate = "\(s)-\(n)"; n += 1 }
        return candidate
    }
}

public enum Tags {
    /// Lowercase, no `#`, no spaces, only `[a-z0-9_-]`, starting with a letter or digit. Empty when nothing is left.
    public static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while s.hasPrefix("#") { s.removeFirst() }
        s = String(s.unicodeScalars.filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "-" }.map(Character.init))
        while let f = s.first, f == "_" || f == "-" { s.removeFirst() }
        return s
    }

    /// Normalised, unique, in insertion order.
    public static func normalized(_ list: [String]) -> [String] {
        var out: [String] = []
        for t in list {
            let n = normalize(t)
            if !n.isEmpty && !out.contains(n) { out.append(n) }
        }
        return out
    }

    /// Tags in use with sheet counts, most used first then A to Z.
    public static func counts(_ pads: [Pad]) -> [(tag: String, count: Int)] {
        var m: [String: Int] = [:]
        for p in pads { for t in p.tags { m[t, default: 0] += 1 } }
        return m.map { (tag: $0.key, count: $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
    }

    /// Existing tags starting with the typed prefix, excluding ones the sheet already has.
    public static func suggestions(prefix: String, pads: [Pad], excluding: [String] = []) -> [(tag: String, count: Int)] {
        let p = normalize(prefix)
        return counts(pads).filter { !excluding.contains($0.tag) && (p.isEmpty || $0.tag.hasPrefix(p)) }
    }
}

public enum PadJSON {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let d = ISODate.parse(s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date \(s)")
        }
        return d
    }()
}

/// ISO 8601 with or without fractional seconds (the Linux app writes milliseconds).
public enum ISODate {
    public static func parse(_ s: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: s) { return d }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return frac.date(from: s)
    }
    public static func string(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }
}

public enum DayKey {
    private static func formatter(_ tz: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = tz
        return f
    }
    /// Local-calendar day key, e.g. 2026-10-12. A sheet belongs to the day it was started in the user's timezone.
    public static func key(for date: Date, timeZone: TimeZone = .current) -> String {
        formatter(timeZone).string(from: date)
    }
    public static func date(from key: String, timeZone: TimeZone = .current) -> Date? {
        formatter(timeZone).date(from: key)
    }
}
