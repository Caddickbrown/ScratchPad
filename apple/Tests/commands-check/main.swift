import Foundation

// Run with apple/Tests/commands-check/run.sh.

var failures = 0, checks = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL line \(line): \(what)") }
}

func ids(_ l: ScratchpadCommandList, typing: Bool = false) -> [String] { l.rows(stage: nil, typing: typing).map(\.id) }
func first(_ typed: String, _ l: ScratchpadCommandList) -> ScratchpadCommand? {
    var p = CommandPalette(l)
    p.type(typed)
    guard case .run(let c) = p.press(.enter) else { return nil }
    return c
}

let open = ScratchpadCommandList(hasSheet: true)
let none = ScratchpadCommandList()

check(Array(ids(open).prefix(3)) == ["sheets", "today", "settings"], "where to go comes first: \(ids(open))")
for id in ["new", "insert", "todos", "export", "duplicate"] { check(ids(open).contains(id), "\(id) with a sheet open") }
check(first("set", open) == .settings, "set finds Settings")
check(first("tod", open) == .today, "tod finds Today")
check(first("new sheet", open) == .newSheet, "new sheet")
check(first("date", open) == .newOnDate, "a new sheet on a date")
check(first("pinned", open) == .newPinned, "a pinned one")
check(first("to-do", open) == .todos, "the to-dos")
check(first("export", open) == .export, "export")
check(first("import", open) == .importArchive, "import goes to the file picker")
check(first("dup", open) == .duplicate, "duplicate")

// Inserting.
var p = CommandPalette(open)
p.type("insert")
check(p.press(.enter) == .stay && p.stage == "insert", "Insert a block opens a shorter list")
check(p.rows.map(\.title) == ["Text", "Table", "Code", "Link", "Divider"], "of the kinds, in the Mac menu's order")
p.type("tab")
check(p.press(.enter) == .run(.insert(.table)), "and inserts one")
check(first("divider", open) == .insert(.divider), "or straight from the top")

// With no sheet: only what still means something.
for id in ["insert", "duplicate", "delete", "todos"] { check(!ids(none, typing: true).contains(id), "no sheet: no \(id)") }
check(ids(none).contains("new") && ids(none).contains("settings"), "a new sheet and Settings remain")

check(!ids(open, typing: true).contains("undo"), "nothing to undo")
check(first("undo", ScratchpadCommandList(hasSheet: true, canUndo: true)) == .undoDelete, "undo while it can")

// Deleting goes through the app's question, and nothing else may delete.
let all = ScratchpadCommandList(hasSheet: true, canUndo: true).rows(stage: nil, typing: true)
check(open.rows(stage: nil, typing: false).count <= CommandPaletteLimit.rows, "the list before typing all shows")
check(Set(all.map(\.id)).count == all.count, "no row twice")
check(CommandSafety.unguarded(all).isEmpty, "nothing on the list destroys anything without asking")
check(all.filter(\.confirms).map(\.id) == ["delete"], "the one that asks")
check(first("delete", open) == .askDelete, "as a question rather than the thing itself")
check(!all.contains { $0.title == "Delete this block" }, "a block has no row: its key has no question to go through")

print("\(checks - failures) of \(checks) checks passed")
exit(failures == 0 ? 0 : 1)
