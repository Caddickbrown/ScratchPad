import Foundation

/// Shared JSON model. Mirrors shared/schema/pad.schema.json and linux/src/model.ts exactly.
public let gridSize = 24

public enum BlockKind: String, Codable, CaseIterable, Sendable {
    case text, table, image, file, link, code, divider
}

public struct Block: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: BlockKind
    public var x: Int
    public var y: Int
    public var w: Int
    public var h: Int?
    public var text: String?
    public var rows: [[String]]?
    public var asset: String?
    public var name: String?
    public var size: Int?
    public var url: String?
    public var caption: String?
    public var language: String?

    public init(id: String = UUID().uuidString, kind: BlockKind, x: Int, y: Int, w: Int, h: Int? = nil,
                text: String? = nil, rows: [[String]]? = nil, asset: String? = nil, name: String? = nil,
                size: Int? = nil, url: String? = nil, caption: String? = nil, language: String? = nil) {
        self.id = id; self.kind = kind; self.x = x; self.y = y; self.w = w; self.h = h
        self.text = text; self.rows = rows; self.asset = asset; self.name = name
        self.size = size; self.url = url; self.caption = caption; self.language = language
    }

    /// Snaps the origin to the dot grid.
    public mutating func snap() {
        x = Block.snapped(x); y = Block.snapped(y); w = max(2 * gridSize, Block.snapped(w))
    }

    public static func snapped(_ v: Int) -> Int {
        Int((Double(v) / Double(gridSize)).rounded()) * gridSize
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

    /// Open for three or more days counts as overdue (components board, row 5).
    public func isOverdue(now: Date = Date()) -> Bool {
        status == .open && !text.isEmpty && now.timeIntervalSince(createdAt) >= 3 * 86_400
    }
}

public struct Pad: Codable, Identifiable, Equatable, Sendable {
    public var v: Int = 1
    public var id: String
    public var date: String?
    public var title: String
    public var tag: String
    public var pinned: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var blocks: [Block]
    public var todos: [Todo]

    public init(id: String, date: String?, title: String = "", tag: String = "", pinned: Bool = false,
                createdAt: Date = Date(), updatedAt: Date = Date(), blocks: [Block] = [], todos: [Todo] = []) {
        self.id = id; self.date = date; self.title = title; self.tag = tag; self.pinned = pinned
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.blocks = blocks; self.todos = todos
    }

    public static func daily(_ day: String, now: Date = Date()) -> Pad {
        Pad(id: day, date: day, createdAt: now, updatedAt: now)
    }

    public var doneCount: Int { todos.filter { $0.status == .done && !$0.text.isEmpty }.count }
    public var openCount: Int { todos.filter { $0.status == .open && !$0.text.isEmpty }.count }
    public var filledCount: Int { todos.filter { !$0.text.isEmpty }.count }
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
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

public enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    /// Local-calendar day key, e.g. 2026-10-12. A pad belongs to the day it was started in the user's timezone.
    public static func key(for date: Date, timeZone: TimeZone = .current) -> String {
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
    public static func date(from key: String, timeZone: TimeZone = .current) -> Date? {
        formatter.timeZone = timeZone
        return formatter.date(from: key)
    }
}
