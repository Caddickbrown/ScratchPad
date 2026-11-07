import Foundation
import ScratchpadFFI

// MARK: - The rules, from the core
//
// Formulas, date phrases, paste, to-do order, the sidebar and exports come from scratchpad-core,
// behind the Swift names the views already use. The Swift copies stay as `swift…` until a release
// has proved the core; they're also what `core-check record` asks for, to write the vectors.

enum CoreRules {
    /// SCRATCHPAD_RULES=swift puts the Swift copies back.
    nonisolated(unsafe) static var enabled = ProcessInfo.processInfo.environment["SCRATCHPAD_RULES"] != "swift"

    static func evaluate(_ rows: [[String]]) -> [[CellValue]] {
        evaluateTable(rows: rows).map { row in
            row.map { cell in
                switch cell {
                case .empty: return .empty
                case .number(let value): return .number(value)
                case .text(let value): return .text(value)
                case .error(let code): return .error(FormulaError(rawValue: code) ?? .err)
                }
            }
        }
    }

    static func classify(plain: String?, html: String?) -> [PasteResult] {
        classifyPaste(plain: plain, html: html).map { paste in
            switch paste {
            case .text(let text): return .text(text)
            case .code(let body, let language): return .code(body, language: language)
            case .link(let url, let title): return .link(url: url, title: title)
            case .table(let rows): return .table(rows)
            }
        }
    }

    static func groups(_ pads: [Pad], mode: String, tagSort: TagSort = .alphabetical, today: String = "") -> [SheetGroup] {
        let rows = pads.map {
            SheetRow(id: $0.id, date: $0.date, title: $0.title, tags: $0.tags, pinned: $0.pinned, updatedAtMs: $0.updatedAt.coreMillis)
        }
        return sidebarGroups(rows: rows, mode: mode, tagSort: tagSort.rawValue, today: today).map { g in
            SheetGroup(id: g.id, label: g.label, detail: g.detail, sheets: g.sheets.map { pads[Int($0)] })
        }
    }

    static func setEnabledForTools(_ on: Bool) { enabled = on }
}

/// For the check tool: the Swift copies, or the core.
public enum CoreCheck {
    public static func useCore(_ on: Bool) { CoreRules.setEnabledForTools(on) }
}

extension Formula {
    /// Numbers in cells: whitespace trimmed, `,` thousands separators removed, `£ $ € %` prefix/suffix ignored.
    public static func parseNumber(_ raw: String) -> Double? {
        CoreRules.enabled ? ScratchpadFFI.parseNumber(raw: raw) : swiftParseNumber(raw)
    }

    /// Up to 4 decimals, trailing zeros trimmed, thousands separators for |x| >= 1000.
    public static func format(_ value: Double) -> String {
        CoreRules.enabled ? formatNumber(value: value) : swiftFormat(value)
    }
}

extension DatePhrase {
    /// Returns a `YYYY-MM-DD` key for the phrase, relative to `today` (a day key), or nil.
    /// Accepts: today, tomorrow, yesterday, weekday names or 3+ letter prefixes (next occurrence, today counts),
    /// `15 oct`, `oct 15`, `15/10` (day/month), `2026-10-15`, `+3`, `-2`. A year may follow the day-month forms.
    public static func parse(_ input: String, today: String) -> String? {
        CoreRules.enabled ? parseDayPhrase(input: input, today: today) : swiftParse(input, today: today)
    }
}

extension LinkTitle {
    /// `<title>` text, entities decoded and whitespace collapsed.
    public static func parse(_ html: String) -> String? {
        CoreRules.enabled ? htmlTitle(html: html) : swiftParse(html)
    }
}

extension TodoSort {
    /// Stable sort. `doneSinks` pushes done rows to the bottom in every mode, Manual included.
    /// Empty rows always stay last.
    public static func sorted(_ todos: [Todo], mode: TodoSortMode, doneSinks: Bool, now: Date = Date()) -> [Todo] {
        guard CoreRules.enabled else { return swiftSorted(todos, mode: mode, doneSinks: doneSinks, now: now) }
        return sortTodos(todos: todos.map(\.record), mode: mode.rawValue, doneSinks: doneSinks, nowMs: now.coreMillis).map { todos[Int($0)] }
    }
}

extension Sidebar {
    /// Dated sheets grouped by day, newest first. Pinned sheets have their own section.
    public static func byDay(_ pads: [Pad], today: String) -> [SheetGroup] {
        CoreRules.enabled ? CoreRules.groups(pads, mode: "byDay", today: today) : swiftByDay(pads, today: today)
    }

    /// Dated sheets grouped by month (`October 2026`), newest first; the detail is the sheet count.
    public static func byMonth(_ pads: [Pad]) -> [SheetGroup] {
        CoreRules.enabled ? CoreRules.groups(pads, mode: "byMonth") : swiftByMonth(pads)
    }

    /// Every dated sheet in one group, most recently edited first, whatever its date.
    public static func recent(_ pads: [Pad]) -> [SheetGroup] {
        CoreRules.enabled ? CoreRules.groups(pads, mode: "recent") : swiftRecent(pads)
    }

    /// One group per tag (a sheet appears under each of its tags), Untagged last.
    public static func byTag(_ pads: [Pad], sort: TagSort) -> [SheetGroup] {
        CoreRules.enabled ? CoreRules.groups(pads, mode: "byTag", tagSort: sort) : swiftByTag(pads, sort: sort)
    }
}

extension ExportMarkdown {
    /// One section per sheet, newest first, blank line between sections:
    /// `## <title or "Untitled sheet">, <ddd d MMM yyyy | Pinned>` then the checkbox list.
    /// `openOnly` (Every open to-do) keeps open rows (and deferred when ticked) and omits empty sections;
    /// empty sections are also dropped when several sheets are exported.
    public static func todos(_ sheets: [Pad], includeDone: Bool = false, includeDeferred: Bool = true, openOnly: Bool = false) -> String {
        guard CoreRules.enabled else { return swiftTodos(sheets, includeDone: includeDone, includeDeferred: includeDeferred, openOnly: openOnly) }
        return exportTodos(sheets: sheets.map(\.record), includeDone: includeDone, includeDeferred: includeDeferred, openOnly: openOnly)
    }

    /// GFM table with computed values; the first row is the header.
    public static func table(_ rows: [[String]]) -> String {
        CoreRules.enabled ? exportTable(rows: rows) : swiftTable(rows)
    }

    public static func sheet(_ p: Pad) -> String {
        CoreRules.enabled ? exportSheet(pad: p.record) : swiftSheet(p)
    }

    /// Everything, one Markdown file: sheets newest first, separated by a rule.
    public static func everything(_ sheets: [Pad]) -> String {
        CoreRules.enabled ? exportEverything(sheets: sheets.map(\.record)) : swiftEverything(sheets)
    }
}

extension ExportJSON {
    /// Everything as JSON: an array of v2 sheets, newest first.
    public static func sheets(_ sheets: [Pad]) throws -> Data {
        CoreRules.enabled ? exportJson(sheets: sheets.map(\.record)) : try swiftSheets(sheets)
    }
}

// MARK: - Crossing the boundary

extension Date {
    /// Rounded down: a file keeps whole seconds, and this must land in the same one.
    var coreMillis: Int64 { Int64((timeIntervalSince1970 * 1000).rounded(.down)) }
    init(coreMillis: Int64) { self.init(timeIntervalSince1970: Double(coreMillis) / 1000) }
}

extension Block {
    var record: BlockRecord {
        BlockRecord(id: id, kind: kind.rawValue, x: Int64(x), y: Int64(y), w: Int64(w), h: h.map(Int64.init), text: text, rows: rows,
                    asset: asset, name: name, size: size.map(Int64.init), url: url, caption: caption, language: language,
                    rotation: rotation, font: font.rawValue, fontSize: Int64(fontSize), bold: bold, italic: italic,
                    colWidths: colWidths?.map(Int64.init), extras: extras)
    }

    init(record b: BlockRecord) {
        self.init(id: b.id, kind: BlockKind(rawValue: b.kind) ?? .text, x: Int(b.x), y: Int(b.y), w: Int(b.w), h: b.h.map(Int.init),
                  text: b.text, rows: b.rows, asset: b.asset, name: b.name, size: b.size.map(Int.init), url: b.url, caption: b.caption,
                  language: b.language, rotation: b.rotation, font: BlockFont(rawValue: b.font) ?? .sans, fontSize: Int(b.fontSize),
                  bold: b.bold, italic: b.italic, colWidths: b.colWidths?.map(Int.init))
        extras = b.extras
    }
}

extension Todo {
    var record: TodoRecord {
        TodoRecord(id: id, text: text, status: status.rawValue, createdAtMs: createdAt.coreMillis, carriedFrom: carriedFrom, extras: extras)
    }

    init(record t: TodoRecord) {
        self.init(id: t.id, text: t.text, status: TodoStatus(rawValue: t.status) ?? .open,
                  createdAt: Date(coreMillis: t.createdAtMs), carriedFrom: t.carriedFrom)
        extras = t.extras
    }
}

extension Pad {
    var record: PadRecord {
        PadRecord(id: id, date: date, title: title, tags: tags, pinned: pinned, createdAtMs: createdAt.coreMillis,
                  updatedAtMs: updatedAt.coreMillis, blocks: blocks.map(\.record), todos: todos.map(\.record), extras: extras)
    }

    init(record p: PadRecord) {
        self.init(id: p.id, date: p.date, title: p.title, tags: p.tags, pinned: p.pinned, createdAt: Date(coreMillis: p.createdAtMs),
                  updatedAt: Date(coreMillis: p.updatedAtMs), blocks: p.blocks.map(Block.init(record:)), todos: p.todos.map(Todo.init(record:)))
        extras = p.extras
    }
}
