import Foundation
import ScratchpadCore

/// Swift against the core, through UniFFI, on a generated library in a throwaway folder.
func runSpeed(sheets: Int) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("scratchpad-speed-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let swiftStore = try! PadStore(root: root, engine: .swift)
    let coreStore = try! PadStore(root: root, engine: .rust)
    let base = ISODate.parse("2026-11-05T12:00:00Z")!
    var library: [Pad] = []
    for i in 0..<sheets {
        let day = DayMath.add(days: -i / 2, to: "2026-11-05")!
        var p = Pad(id: "\(day)-\(String(format: "%06d", i))", date: day, title: "Sheet \(i)", tags: i % 3 == 0 ? ["work"] : ["home"],
                    createdAt: base.addingTimeInterval(Double(-i) * 40_000), updatedAt: base.addingTimeInterval(Double(-i) * 40_000))
        for b in 0..<6 {
            p.blocks.append(Block(kind: .text, x: 24, y: 24 + b * 120, w: 408, text: String(repeating: "plan notes review café ", count: 12)))
        }
        p.blocks.append(Block(kind: .table, x: 24, y: 900, w: 408, rows: [["A", "B", "C"], ["1", "£2.50", "=A2+B2"], ["3", "4", "=SUM(A2:B3)"], ["5", "6", "=AVG(A2:A3)"]]))
        p.todos = (0..<6).map { Todo(text: "Do thing \($0) of \(i)", status: $0 % 3 == 0 ? .done : .open, createdAt: base) }
        _ = try! swiftStore.save(p, touch: false)
        library.append(p)
    }
    let big = (0..<200).map { r in (0..<12).map { c in r == 0 ? "Col \(c)" : (c == 11 ? "=SUM(A\(r + 1):K\(r + 1))" : "\(r * c)") } }
    let phrases = (0..<2000).map { ["today", "fri", "+3", "15 oct", "oct 15 2027", "15/10", "2026-10-15", "nonsense"][$0 % 8] }
    let pastes = (0..<750).map { i -> ClipboardContents in
        i % 3 == 0 ? ClipboardContents(plain: "a\tb\nc\td") : i % 3 == 1 ? ClipboardContents(plain: "https://example.test/\(i)")
            : ClipboardContents(plain: "x", html: "<table><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>")
    }
    let todos = (0..<300).map { Todo(text: "Item \(($0 * 7919) % 300)", status: $0 % 4 == 0 ? .done : .open, createdAt: base.addingTimeInterval(Double(-$0) * 3600)) }

    func median(_ runs: Int = 7, _ body: () -> Void) -> Double {
        var times: [Double] = []
        for _ in 0..<runs { let t = Date(); body(); times.append(Date().timeIntervalSince(t) * 1000) }
        return times.sorted()[times.count / 2]
    }
    func row(_ name: String, runs: Int = 7, _ swift: () -> Void, _ core: (() -> Void)? = nil) {
        CoreCheck.useCore(false); let a = median(runs, swift)
        CoreCheck.useCore(true); let b = core.map { median(runs, $0) } ?? median(runs, swift)
        let ratio = a >= b ? String(format: "%.1fx faster", a / b) : String(format: "%.1fx slower", b / a)
        print("| \(name) | \(String(format: "%.2f", a)) | \(String(format: "%.2f", b)) | \(ratio) |")
    }
    print("| \(sheets) sheets, median of 7 | Swift ms | Core ms | |\n|---|---|---|---|")
    row("list every sheet", runs: 5, { _ = try! swiftStore.list() }, { _ = try! coreStore.list() })
    let one = library[3]
    row("load one sheet", runs: 21, { _ = try! swiftStore.load(one.id) }, { _ = try! coreStore.load(one.id) })
    row("save one sheet", runs: 21, { _ = try! swiftStore.save(one, touch: false) }, { _ = try! coreStore.save(one, touch: false) })
    row("evaluate a 200 x 12 table", { _ = TableEvaluator(rows: big).evaluateAll() })
    row("2,000 date phrases", { for p in phrases { _ = DatePhrase.parse(p, today: "2026-11-05") } })
    row("750 pastes", { for p in pastes { _ = PasteClassifier.classify(p) } })
    row("sort 300 to-dos A to Z", { _ = TodoSort.sorted(todos, mode: .alphabetical, doneSinks: true, now: base) })
    row("sidebar by day", { _ = Sidebar.byDay(library, today: "2026-11-05") })
    row("sidebar by tag", { _ = Sidebar.byTag(library, sort: .mostSheets) })
    row("Markdown export, everything", runs: 5, { _ = ExportMarkdown.everything(library) })
    row("JSON export, everything", runs: 5, { _ = try! ExportJSON.sheets(library) })
}
