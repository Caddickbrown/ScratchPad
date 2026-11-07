import Foundation
import ScratchpadCore

// Records what the Swift code answers into shared/vectors/expected.json, or checks the core against it.
//   swift run core-check record [vectors dir]   the Swift copies write the answers
//   swift run core-check check  [vectors dir]   the same questions through UniFFI, as the app asks them
//   swift run -c release core-check speed [sheets]   Swift against the core, on a generated library

let arguments = CommandLine.arguments
let mode = arguments.count > 1 ? arguments[1] : "check"
if mode == "speed" { runSpeed(sheets: arguments.count > 2 ? Int(arguments[2]) ?? 1000 : 1000); exit(0) }
let folder = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "../shared/vectors")
let inputs = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("inputs.json"))) as! [String: Any]
CoreCheck.useCore(mode != "record")

func strings(_ key: String) -> [String] { inputs[key] as! [String] }
func opt<T>(_ v: T?) -> Any { v.map { $0 as Any } ?? NSNull() }
let today = inputs["today"] as! String
let now = ISODate.parse(inputs["now"] as! String)!
func group(_ g: SheetGroup) -> [String: Any] { ["id": g.id, "label": g.label, "detail": g.detail, "sheets": g.sheets.map(\.id)] }

var out: [String: Any] = [:]
out["phrases"] = strings("phrases").map { opt(DatePhrase.parse($0, today: today)) }
out["numbers"] = strings("numbers").map { opt(Formula.parseNumber($0).map { "\($0)" }) }
out["formats"] = (inputs["formats"] as! [Double]).map(Formula.format)
out["titles"] = strings("titles").map { opt(LinkTitle.parse($0)) }
out["pastes"] = (inputs["pastes"] as! [[String: String]]).map { p -> [[String: Any]] in
    PasteClassifier.classify(ClipboardContents(plain: p["plain"], html: p["html"])).map { r in
        switch r {
        case .text(let s): return ["kind": "text", "text": s]
        case .code(let s, let l): return ["kind": "code", "text": s, "language": opt(l)]
        case .link(let u, let t): return ["kind": "link", "url": u, "title": opt(t)]
        case .table(let rows): return ["kind": "table", "rows": rows]
        default: return ["kind": "other"]
        }
    }
}

var pads: [Pad] = []
var decoded: [Any] = []
for text in strings("sheets") {
    if let pad = try? PadJSON.decoder.decode(Pad.self, from: Data(text.utf8)), let bytes = try? PadJSON.encoder.encode(pad) {
        pads.append(pad)
        decoded.append(String(decoding: bytes, as: UTF8.self))
    } else { decoded.append(NSNull()) }
}
if mode == "record" { out["decoded"] = decoded }

let tables = pads.flatMap { $0.blocks.compactMap(\.rows) }
out["tables"] = tables.map { rows -> [[String]] in
    let e = TableEvaluator(rows: rows)
    return rows.indices.map { r in rows[r].indices.map { c in e.display(row: r, col: c) } }
}
out["markdownTables"] = tables.map(ExportMarkdown.table)
out["fit"] = tables.map { rows in (0..<(rows.map(\.count).max() ?? 0)).map { TableLayout.fitWidth(column: $0, rows: rows) } }
let lists = inputs["todoLists"] as! [[[String: Any]]]
let decoder = PadJSON.decoder
out["sorts"] = lists.map { list -> [[String]] in
    let todos = list.map { try! decoder.decode(Todo.self, from: JSONSerialization.data(withJSONObject: $0)) }
    return TodoSortMode.allCases.flatMap { mode in [false, true].map { sinks in TodoSort.sorted(todos, mode: mode, doneSinks: sinks, now: now).map(\.id) } }
}
out["sidebar"] = [
    "byDay": Sidebar.byDay(pads, today: today).map(group), "byMonth": Sidebar.byMonth(pads).map(group), "recent": Sidebar.recent(pads).map(group),
    "tagAlpha": Sidebar.byTag(pads, sort: .alphabetical).map(group), "tagMost": Sidebar.byTag(pads, sort: .mostSheets).map(group),
    "tagRecent": Sidebar.byTag(pads, sort: .recentlyUsed).map(group),
] as [String: Any]
out["markdown"] = pads.map(ExportMarkdown.sheet)
out["everything"] = ExportMarkdown.everything(pads)
out["todosDefault"] = ExportMarkdown.todos(pads)
out["todosOpen"] = ExportMarkdown.todos(pads, includeDeferred: false, openOnly: true)
out["todosAll"] = ExportMarkdown.todos(pads, includeDone: true)
out["todosOne"] = ExportMarkdown.todos(Array(pads.prefix(1)))
out["exportJSON"] = String(decoding: try ExportJSON.sheets(pads), as: UTF8.self)

if mode == "record" {
    // Rules the app doesn't reach through the core yet. These are checked in `cargo test`.
    out["isos"] = strings("isos").map { opt(ISODate.parse($0).map { Int64(($0.timeIntervalSince1970 * 1000).rounded(.down)) }) }
    out["rotations"] = (inputs["rotations"] as! [Double]).map { "\(Block.normalizedRotation($0))" }
    out["snaps"] = (inputs["snaps"] as! [Int]).map(Block.snapped)
    out["tags"] = strings("tags").map(Tags.normalize)
    out["slugs"] = (inputs["slugs"] as! [[String: Any]]).map { SheetID.slug($0["title"] as! String, existing: Set($0["existing"] as! [String])) }
    out["pinned"] = Sidebar.pinned(pads).map(\.id)
    out["datesWithSheets"] = Sidebar.datesWithSheets(pads).sorted()
    out["tagCounts"] = Tags.counts(pads).map { [$0.tag, "\($0.count)"] }
    out["tagSuggestions"] = Tags.suggestions(prefix: "w", pads: pads, excluding: ["work"]).map(\.tag)
    let queries = strings("queries")
    out["derived"] = pads.map { p -> [String: Any] in
        ["displayTitle": p.displayTitle, "preview": opt(p.preview), "countLabel": p.countLabel, "footerLabel": p.footerLabel,
         "matches": queries.map { p.matches($0) }, "compacted": p.compacted.todos.count]
    }
    out["keyLabels"] = strings("keys").map { k -> [String: Any] in
        ["short": DayLabel.shortDate(k), "long": DayLabel.longDate(k), "medium": DayLabel.mediumDate(k), "group": DayLabel.group(k, today: today),
         "plus": opt(DayMath.add(days: 30, to: k)), "distance": opt(DayMath.distance(from: k, to: today)), "weekday": opt(DayMath.weekdayMondayFirst(k))]
    }
    out["months"] = (inputs["months"] as! [[Int]]).map { m -> [String: Any] in
        let s = MonthGrid.shift(year: m[0], month: m[1], by: -13)
        return ["title": DayLabel.monthTitle(year: m[0], month: m[1]), "weeks": MonthGrid.weeks(year: m[0], month: m[1]).map { $0.map { opt($0) } }, "shift": [s.year, s.month]]
    }
    let widths = inputs["widths"] as! [Any]
    out["points"] = pads.map { p in widths.map { w -> [Int] in let n = Placement.nextFreePoint(on: p, within: w as? Int); return [n.x, n.y] } }
    out["sources"] = strings("keys").map { Rollover.sources(for: $0, among: pads).map(\.id) }
    out["carried"] = Rollover.carried(from: Rollover.sources(for: today, among: pads), into: Pad(id: "new", date: today, createdAt: now, updatedAt: now)).todos.map { [$0.text, $0.carriedFrom ?? ""] }
    out["widths"] = pads.flatMap(\.blocks).filter { $0.kind == .table }.map(TableLayout.widths)
    let corners: [String: Block.Corner] = ["topLeft": .topLeft, "topRight": .topRight, "bottomLeft": .bottomLeft, "bottomRight": .bottomRight]
    let sample = Block(id: "r", kind: .text, x: 240, y: 120, w: 300, h: 200)
    out["resized"] = (inputs["resizes"] as! [[String: Any]]).map { r -> [Int] in
        let b = sample.resized(corner: corners[r["corner"] as! String]!, dx: r["dx"] as! Double, dy: r["dy"] as! Double, startHeight: r["start"] as! Double, keepAspect: r["aspect"] as! Bool)
        return [b.x, b.y, b.w, b.h ?? -1]
    }
    let data = try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
    try data.write(to: folder.appendingPathComponent("expected.json"))
    print("recorded \(out.count) groups from \(pads.count) sheets")
} else {
    let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("expected.json"))) as! [String: Any]
    func same(_ a: Any, _ b: Any) -> Bool {
        let wrap = { (x: Any) in try! JSONSerialization.data(withJSONObject: ["v": x], options: [.sortedKeys]) }
        return wrap(a) == wrap(b)
    }
    var cases = 0, failures = 0
    for key in out.keys.sorted() {
        let got = out[key]!, want = expected[key]!
        if let g = got as? [Any], let w = want as? [Any], g.count == w.count {
            var bad = 0
            for (i, (x, y)) in zip(g, w).enumerated() where !same(x, y) {
                bad += 1
                if bad <= 3 { print("DIFF \(key)[\(i)]\n  core  \(x)\n  swift \(y)") }
            }
            cases += g.count; failures += bad
            print("\(key): \(g.count - bad) of \(g.count)")
        } else {
            let ok = same(got, want)
            cases += 1; failures += ok ? 0 : 1
            print("\(key): \(ok ? "same" : "DIFFERENT")")
        }
    }
    print("\(cases - failures) of \(cases) cases agree")
    exit(failures == 0 ? 0 : 1)
}
