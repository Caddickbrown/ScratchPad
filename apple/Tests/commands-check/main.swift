import Foundation

// Run with apple/Tests/commands-check/run.sh. The list is built from a `ScratchpadCommandState`, as
// CommandMenu.swift builds it from what's on screen.

var failures = 0, checks = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL line \(line): \(what)") }
}

typealias State = ScratchpadCommandState
typealias List = ScratchpadCommandList

// "fri" and "+3" as the core reads them, for the date questions.
List.readDate = { text in
    switch text.lowercased() {
    case "fri": return ("2026-11-20", "Friday 20 November")
    case "+3": return ("2026-11-20", "Friday 20 November")
    case "today": return ("2026-11-17", "Tuesday 17 November")
    default: return nil
    }
}

let sheets = [State.Sheet(id: "s1", title: "Planning", typed: "Planning", detail: "Tue 17 Nov", tags: ["work"]),
              State.Sheet(id: "s2", title: "Shopping", typed: "Shopping", detail: "Pinned"),
              State.Sheet(id: "s3", title: "Untitled sheet", detail: "Mon 16 Nov")]
let todos = [State.Todo(id: "t1", text: "Buy milk"), State.Todo(id: "t2", text: "Call Sam", status: "deferred"),
             State.Todo(id: "t3", text: "Post card", status: "done")]
let table = State.Block(id: "b1", kind: "table", name: "Table “Costs”", rows: 3, cols: 2,
                        cells: [["Item", "Cost"], ["Tea", "3"], ["Total", "=SUM(B2:B2)"]], widths: [120, 120])
let text = State.Block(id: "b2", kind: "text", name: "Text “Ideas”", font: "sans", fontSize: 14, text: "Ideas")
let link = State.Block(id: "b3", kind: "link", name: "Link “Kit”", url: "https://example.com", text: "Kit")

/// A sheet open on an iPad, wide enough for the to-do column.
func onSheet(_ change: (inout State) -> Void = { _ in }) -> List {
    var s = State(sheets: sheets, current: sheets[0], todos: todos, blocks: [table, text, link], tags: ["work", "home"])
    s.wide = true
    s.todoLayout = .column
    s.todosShowing = true
    change(&s)
    return List(state: s)
}
/// The phone on its sheet list: nothing open on screen.
let home = List(state: State(sheets: sheets))

func ids(_ l: List, typing: Bool = false) -> [String] { l.rows(stage: nil, typing: typing).map(\.id) }
func row(_ id: String, _ l: List) -> CommandRow<ScratchpadCommand>? { l.rows(stage: nil, typing: true).first { $0.id == id } }
func first(_ typed: String, _ l: List) -> ScratchpadCommand? {
    var p = CommandPalette(l)
    p.type(typed)
    guard case .run(let c) = p.press(.enter) else { return nil }
    return c
}
/// Opens a row's step, types into it, and takes the first answer.
func answer(_ id: String, _ typed: String, _ l: List, clear: Bool = false) -> ScratchpadCommand? {
    var p = CommandPalette(l)
    guard p.choose(id) == .stay else { return nil }
    if clear { while !p.query.isEmpty { p.backspace() } }
    p.type(typed)
    guard case .run(let c) = p.press(.enter) else { return nil }
    return c
}
/// Everything on the list, and under it.
func everything(_ l: List) -> [CommandRow<ScratchpadCommand>] {
    l.rows(stage: nil, typing: true).flatMap { [$0] + $0.underneath }
}

// MARK: Safety, on every list the app can build

let lists: [(String, List)] = [
    ("home", home), ("sheet", onSheet()),
    ("block", onSheet { $0.block = table }), ("text", onSheet { $0.block = text }), ("link", onSheet { $0.block = link }),
    ("todo", onSheet { $0.todo = todos[0] }), ("undo", onSheet { $0.undo = "The table comes back" }),
    ("phone", onSheet { $0.wide = false; $0.todoLayout = .sheet; $0.todosShowing = false }),
    ("search", List(state: State(sheets: sheets, searchText: "milk"))),
]
for (name, l) in lists {
    let rows = l.rows(stage: nil, typing: true)
    check(CommandSafety.unguarded(rows).isEmpty, "\(name): nothing destroys without asking or Undo: \(CommandSafety.unguarded(rows).map(\.title))")
    check(CommandSafety.unmarked(rows).isEmpty, "\(name): everything that sounds destructive is red: \(CommandSafety.unmarked(rows).map(\.title))")
    check(Set(rows.map(\.id)).count == rows.count, "\(name): no row twice")
    check(l.rows(stage: nil, typing: false) == rows, "\(name): nothing hides until you type; the list scrolls")
    for r in everything(l) where r.destructive { check(r.confirms || r.undoable, "\(name): \(r.title) asks or undoes") }
}

// MARK: Getting around

check(first("today", home) == .today, "Today")
check(first("sheet list", onSheet()) == .sheets, "back to the sheet list")
check(first("settings", home) == .settings, "Settings")
check(first("shopping", home) == .open("s2"), "a sheet by name, typed at the top")
check(answer("open", "plan", home) == .open("s1"), "Open a sheet… then its name")
check(first("#work", home) == .open("s1"), "or by its tag")
check(answer("search", "milk", home) == .search("milk"), "Search… takes the words")
check(row("search.clear", home) == nil, "nothing to stop searching")
check(first("clear search", List(state: State(sheets: sheets, searchText: "milk"))) == .clearSearch, "stop searching")
check(answer("rail", "month", home) == .railMode("byMonth"), "group the sheet list by month")
check(answer("tagsort", "most", home) == .tagSort("mostSheets"), "sort the tags")
check(row("sidebar", home) == nil, "the phone has no sidebar to hide")
check(row("sidebar", onSheet())?.title == "Hide the sheet list", "the iPad's says which way it goes")
check(row("sidebar", onSheet { $0.sidebarShowing = false })?.step == .run(.sidebar(true)), "and shows it again")

// MARK: New sheets

check(first("new sheet", home) == .newSheet, "new sheet")
check(answer("onDate", "fri", home) == .newOnDate("2026-11-20"), "a new sheet on a typed day")
check(answer("onDate", "calendar", home) == .chooseNewDate, "or the month grid")
check(answer("onDate", "someday", home) == nil, "nothing for a day it can't read")
check(answer("pinned", "Recipes", home) == .newPinned("Recipes"), "a pinned sheet, titled in the menu")
check(first("import", home) == .importArchive, "import")
check(first("copy every", home) == .copyEverything, "every sheet as Markdown")

// MARK: The phone's list: nothing for a sheet it isn't showing

for id in ["insert", "duplicate", "delete", "todos", "todo.add", "sheet.rename", "copy.image"] {
    check(!ids(home).contains(id), "home: no \(id)")
}
check(ids(home).contains("delete.other"), "home: another sheet can still be deleted, asking first")

// MARK: The open sheet

let s = onSheet()
check(answer("sheet.rename", "Plans for Friday", s, clear: true) == .rename("Plans for Friday"), "rename")
check(answer("sheet.rename", "", s, clear: true) == nil, "not to nothing")
check(answer("sheet.date", "+3", s) == .moveSheet("2026-11-20"), "change the date by phrase")
check(answer("sheet.date", "calendar", s) == .chooseSheetDate, "or on the grid")
check(answer("sheet.tag", "#Home Stuff", s) == .addTag("homestuff"), "a new tag, as the core keeps it")
check(answer("sheet.tag", "home", s) == .addTag("home"), "an old one")
check(answer("sheet.tag", "work", s) == nil, "not one it has")
check(answer("sheet.untag", "work", s) == .removeTag("work"), "remove a tag")
check(row("sheet.untag", s)?.destructive == true && row("sheet.untag", s)?.undoable == true, "red, with Undo")
check(row("sheet.untag", onSheet { $0.current?.tags = [] }) == nil, "no tags, nothing to remove")
check(first("copy image", s) == .copyImage, "copy the sheet as an image")
check(first("copy to-dos", s) == .copyTodos, "copy the to-dos as Markdown")
check(first("dup", s) == .duplicate, "duplicate")
check(answer("delete", "", s) == .deleteSheet("s1"), "delete asks in the menu, where the monitor shows it, then deletes")
check(row("delete", s).map { $0.destructive && $0.confirms } == true, "red, and asks")
var del = CommandPalette(s)
_ = del.choose("delete.other"); del.type("shop")
check(del.press(.enter) == .stay && del.isConfirming, "delete another sheet: it asks first")
check(del.rows.first?.title == "Delete “Shopping”" && del.rows.first?.destructive == true, "red, by name: \(del.rows.map(\.title))")
check(del.press(.enter) == .run(.deleteSheet("s2")), "and Return deletes it")
var keep = CommandPalette(s)
_ = keep.choose("delete")
_ = keep.press(.esc)
check(!keep.isConfirming && keep.depth == 0, "Esc keeps the sheet")
check(first("export", s) == .export, "the export dialog")

// MARK: To-dos

check(row("todos", s)?.title == "Hide the to-dos", "a wide iPad's column can be hidden")
check(row("todos", s)?.step == .run(.todos(false)), "and that's what it does")
check(row("todos", onSheet { $0.todosShowing = false })?.title == "Show the to-dos", "then shown")
check(row("todos", onSheet { $0.todoLayout = .slideOver; $0.todosShowing = false })?.step == .run(.todos(true)), "a narrow iPad slides it over")
let phone = onSheet { $0.wide = false; $0.todoLayout = .sheet; $0.todosShowing = false }
check(row("todos", phone)?.step == .run(.todos(true)), "the phone opens its to-do sheet")
check(answer("todo.add", "Ring the vet", s) == .addTodo("Ring the vet"), "add a to-do")
check(answer("todo.tick", "milk", s) == .status("t1", "done"), "tick one")
check(first("tick milk", s) == .status("t1", "done"), "or straight from the top")
check(!(everything(s).contains { $0.id == "tick.t3" }), "a done one isn't offered to tick")
var pal = CommandPalette(s)
_ = pal.choose("todo.pick"); pal.type("sam"); _ = pal.press(.enter)
check(pal.rows.map(\.id).contains("todo.reopen") && pal.rows.map(\.id).contains("todo.done"), "a deferred one can be ticked or reopened")
pal.type("defer")
check(pal.rows.isEmpty || pal.rows.first?.id != "todo.defer", "and isn't offered deferring again")
check(row("todo.sinks", s)?.title == "Keep done to-dos in place" && row("todo.sinks", s)?.step == .run(.doneSinks(false)), "done sinks says which way it goes")
check(answer("todosort", "overdue", s) == .todoSort("overdueFirst"), "sort the to-dos")
check(row("setting.daily", s)?.title == "Setting: A new sheet each day — turn on" && row("setting.daily", s)?.step == .run(.newSheetEachDay(true)),
      "a new sheet each day is off unless chosen, and the row says it turns it on")
check(row("setting.daily", onSheet { $0.newSheetEachDay = true })?.step == .run(.newSheetEachDay(false)), "and turns it off again")
check(first("new", s) == .newSheet, "New makes a sheet")

// The one being typed in comes first, under its name.
let typing = onSheet { $0.todo = todos[0] }
var blank = CommandPalette(typing)
check(blank.sections.first?.title == "“Buy milk”", "the to-do's name heads the list: \(blank.sections.map(\.title))")
check(blank.sections.first?.rows.first?.step == .run(.status("t1", "done")), "Mark done first")
check(first("move down", typing) == .reorderTodo("t1", .down), "reorder it")
check(!ids(typing).contains("todo.up"), "the top one can't go up")
check(answer("todo.move", "shop", typing) == .todoToSheet("t1", "s2"), "move it to another sheet")
check(first("delete this to-do", typing) == .deleteTodo("t1"), "delete it")
check(row("todo.delete", typing).map { $0.destructive && $0.undoable } == true, "red, with Undo")
blank.type("x")
_ = blank.press(.esc)

// MARK: The selected block

let tableOn = onSheet { $0.block = table }
check(CommandPalette(tableOn).sections.first?.title == "Table “Costs”", "the block's name heads the list")
check(first("add a row", tableOn) == .addRow("b1"), "a table row")
check(first("add a column", tableOn) == .addColumn("b1"), "a column")
check(first("remove the last row", tableOn) == .removeRow("b1"), "remove a row")
check(row("table.unrow", tableOn)?.undoable == true, "with Undo")
check(row("table.uncol", onSheet { var t = table; t.cols = 1; $0.block = t }) == nil, "not the only column")
check(first("delete the block", tableOn) == .deleteBlock("b1"), "delete it")
check(row("block.delete", tableOn).map { $0.destructive && $0.undoable } == true, "red, with Undo")
check(first("duplicate the block", tableOn) == .duplicateBlock("b1"), "duplicate it")
check(first("rotate", tableOn) == .rotate("b1"), "rotate it")
check(row("block.unrotate", tableOn) == nil, "nothing to straighten")
check(first("reset rotation", onSheet { var t = table; t.rotation = 15; $0.block = t }) == .unrotate("b1"), "straighten it")
check(first("nudge left", tableOn) == .nudge("b1", dx: -24, dy: 0), "nudge it a grid square")
check(first("wider", tableOn) == .widen("b1", 48), "widen it")
check(row("block.link", tableOn) == nil, "a table has no link")
check(first("open the link", onSheet { $0.block = link }) == .openLink("b3"), "a link block's link opens")

let textOn = onSheet { $0.block = text }
check(first("bold", textOn) == .bold("b2", true), "bold")
check(row("block.bold", onSheet { var t = text; t.bold = true; $0.block = t })?.title == "Not bold", "a bold one says it'll stop")
check(first("italic", textOn) == .italic("b2", true), "italic")
check(first("larger", textOn) == .fontSize("b2", 16), "larger text")
check(answer("block.size", "24", textOn) == .fontSize("b2", 24), "a size")
// Arrowing through fonts shows each on the block; Esc puts back the one it had.
var fonts = CommandPalette(textOn)
_ = fonts.choose("block.font")
_ = fonts.takeEffects()
check(fonts.lit?.id == "font.sans", "the font it has is lit first")
_ = fonts.press(.down)
check(fonts.takeEffects() == [.preview(.font("b2", "serif"))], "Serif shows on the block")
_ = fonts.press(.esc)
check(fonts.takeEffects() == [.revert(.font("b2", "sans"))], "Esc puts Sans back")
check(answer("block.font", "hand", textOn) == .font("b2", "hand"), "and a font can be chosen")
check(answer("block.select", "ideas", s) == .selectBlock("b2"), "select a block by name")
check(first("insert table", s) == .insert("table"), "insert a table")
check(answer("insert", "div", s) == .insert("divider"), "Insert a block… then the kind")
check(first("paste", s) == .paste, "paste as a block")

// MARK: Settings

var look = CommandPalette(s)
_ = look.choose("setting.look")
_ = look.takeEffects()
_ = look.press(.down)
check(look.takeEffects() == [.preview(.appearance("light"))], "Light shows at once")
_ = look.press(.down)
check(look.takeEffects() == [.preview(.appearance("dark"))], "then Dark")
_ = look.press(.esc)
check(look.takeEffects() == [.revert(.appearance("system"))], "Esc puts the system's back")
check(first("switch to dark", s) == .appearance("dark"), "switch to dark")
var dk = CommandPalette(s); dk.type("dark mode")
check(dk.rows.prefix(2).map(\.id) == ["setting.look", "look.dark"], "dark mode finds Appearance and the switch")
check(row("look.dark", onSheet { $0.dark = true })?.title == "Switch to light", "and back")
check(answer("setting.newfont", "serif", s) == .defaultFont("serif"), "the font for new blocks")
check(answer("setting.motion", "subtle", s) == .animation("subtle"), "animation")
check(row("setting.motion", onSheet { $0.reduceMotion = true })?.detail?.contains("Reduce Motion") == true, "says when the system has it off")

// MARK: Monitor Mode: every phone action from the keyboard (audit 18 Nov)

let mon = { (change: (inout State) -> Void) in onSheet { $0.monitorShows = true; change(&$0) } }
// Typing in a block: the caret goes into it.
check(first("edit the block", textOn) == .editBlock("b2"), "Edit the block puts the caret in it")
check(CommandPalette(textOn).sections.first?.rows.first?.id == "block.edit", "and is the selected block's first row")
check(row("block.edit", textOn)?.detail?.contains("↩") == true, "it says ↩ does it")
check(answer("block.words", "Better ideas", textOn, clear: true) == .setText("b2", "Better ideas"), "or its words typed in the menu")
check(answer("block.words", "", textOn) == nil, "unchanged words do nothing")
check(first("edit the link", onSheet { $0.block = link }) == .editBlock("b3"), "a link block can be typed in")
check(answer("link.title", "Kit docs", onSheet { $0.block = link }, clear: true) == .linkTitle("b3", "Kit docs"), "a link's title")
check(answer("link.url", "app-kit.dev", onSheet { $0.block = link }, clear: true) == .linkURL("b3", "app-kit.dev"), "and its address")
check(first("copy the link", onSheet { $0.block = link }) == .copyLink("b3"), "copy the link")
check(row("block.link", onSheet { $0.block = link })?.onPhone != nil, "Open the link says it opens on the phone")
let file = State.Block(id: "b4", kind: "file", name: "File “a.pdf”")
check(first("open the file", onSheet { $0.block = file }) == .openFile("b4"), "a file block opens")
check(row("block.file", onSheet { $0.block = file })?.onPhone != nil, "on the phone, and says so")
// Tables
check(first("edit the table", tableOn) == .editCell("b1", row: 0, col: 0), "Edit the table: the caret in A1")
check(answer("table.cell", "b3", tableOn) == nil, "a cell is picked first")
var cell = CommandPalette(tableOn)
_ = cell.choose("table.cell"); cell.type("b2")
check(cell.press(.enter) == .stay && cell.query == "3", "B2 opens with what's in it: \(cell.query)")
_ = cell.press(.clear); cell.type("=B2*2")
check(cell.press(.enter) == .run(.setCell("b1", row: 1, col: 1, "=B2*2")), "and a formula can be typed over it")
check(everything(tableOn).contains { $0.id == "table.cell" }, "Change a cell… is listed")
var col = CommandPalette(tableOn)
_ = col.choose("table.colWider"); col.type("column b")
check(col.press(.enter) == .run(.widenColumn("b1", col: 1, by: 48)), "widen column B")
check(first("make it taller", tableOn) == .heighten("b1", 48), "taller")
check(row("block.shorter", tableOn) == nil, "nothing to shorten while it fits its contents")
check(first("make it shorter", onSheet { var t = text; t.height = 200; $0.block = t }) == .heighten("b2", -48), "shorter")
check(first("fit its height", onSheet { var t = text; t.height = 200; $0.block = t }) == .fitHeight("b2"), "back to fitting")
check(List.columnName(0) == "A" && List.columnName(25) == "Z" && List.columnName(26) == "AA", "column letters")
// To-dos
check(answer("todo.words", "Buy oat milk", typing, clear: true) == .renameTodo("t1", "Buy oat milk"), "change a to-do's words")
check(answer("todo.words", "Buy milk", typing, clear: true) == nil, "not to the same words")
var words = CommandPalette(typing)
_ = words.choose("todo.words")
check(words.query == "Buy milk", "the words it has are in the box")
check(first("put it on the sheet", typing) == .todoToBlock("t1"), "a to-do onto the sheet as a block")
var inner = CommandPalette(s)
_ = inner.choose("todo.pick"); inner.type("milk"); _ = inner.press(.enter)
check(inner.rows.map(\.id).contains("todo.words") && inner.rows.map(\.id).contains("todo.toBlock"),
      "both under A to-do… too: \(inner.rows.map(\.id))")
// Dates: the month grid is a phone sheet, so the monitor gets the next two weeks.
check(answer("onDate", "calendar", mon { _ in }) == nil, "no month grid on the monitor")
var day = CommandPalette(mon { _ in })
_ = day.choose("onDate")
check(day.rows.first?.title == "Tuesday 17 November" && day.rows.count >= 2, "the coming days instead: \(day.rows.map(\.title))")
check(day.press(.enter) == .run(.newOnDate("2026-11-17")), "and one can be chosen")
var move = CommandPalette(mon { _ in })
_ = move.choose("sheet.date")
check(move.rows.first?.step == .run(.moveSheet("2026-11-17")), "the sheet's date too")
// What needs the phone says so on the monitor.
check(row("export", s)?.onPhone != nil, "Export… finishes on the phone, and says so")
check(row("import", home)?.onPhone != nil, "so does Import")
check(row("settings", home)?.onPhone != nil, "and Settings")
check(row("settings", List(state: State(sheets: sheets, storePlace: "iCloud Drive")))?.detail == "Sheets are kept in: iCloud Drive",
      "which says where the sheets are")
// Nothing is left off the list on the monitor.
for (name, l) in lists {
    var st = l.state; st.monitorShows = true
    let onMon = Set(everything(List(state: st)).map(\.id)), off = Set(everything(l).map(\.id))
    let gone = off.subtracting(onMon).filter { !$0.hasSuffix(".grid") }
    check(gone.isEmpty, "\(name): nothing hidden on the monitor but the month grid: \(gone.sorted())")
}

// MARK: Undo

check(row("undo", s) == nil, "nothing to undo")
check(first("undo", onSheet { $0.undo = "The table comes back" }) == .undo, "undo while it can")

print("\(checks - failures) of \(checks) checks passed")
exit(failures == 0 ? 0 : 1)
