//
//  ScratchpadCommands.swift
//
//  Everything Scratchpad does, as ⌘K lists it (App Kit's docs/MONITOR.md: every action, in every app). The rules and
//  keys are the kit's (kit/swift/CommandPalette.swift). There's no UIKit, SwiftUI or core here, so
//  apple/Tests/commands-check/run.sh builds the list exactly as the app does: `CommandMenu.swift` turns what's on
//  screen into a `ScratchpadCommandState`, and the same `ScratchpadCommandList` comes out. What each command does is
//  `RootView.runCommand`.
//
//  The selected block and the to-do being typed in come first. Follow-up choices stay in the menu (Font…, Move to…,
//  Sort to-dos by…), settings preview while they're lit and Esc puts them back, toggles say which way they'll go, and
//  anything that removes something is red and has Undo, or asks first (a whole sheet).
//

import Foundation

enum ScratchpadCommand: Equatable {
    enum TodoMove: Equatable { case up, down, top, bottom }

    // Getting around
    case sheets, today, settings, open(String), search(String), clearSearch
    case railMode(String), tagSort(String), sidebar(Bool)
    // The sheet
    case newSheet, newOnDate(String), chooseNewDate, newPinned(String), duplicate, deleteSheet(String)
    case rename(String), moveSheet(String), chooseSheetDate, addTag(String), removeTag(String)
    case export, importArchive, copyImage, copyTodos, copyEverything
    // Blocks
    case insert(String), paste, selectBlock(String), deselect
    case deleteBlock(String), duplicateBlock(String), rotate(String), unrotate(String)
    case font(String, String), fontSize(String, Int), bold(String, Bool), italic(String, Bool)
    case addRow(String), addColumn(String), removeRow(String), removeColumn(String)
    case openLink(String), nudge(String, dx: Int, dy: Int), widen(String, Int)
    // Typing on a block from the keyboard: the caret into it (↩), or its words changed in the menu
    case editBlock(String), editCell(String, row: Int, col: Int), setText(String, String)
    case setCell(String, row: Int, col: Int, String), linkTitle(String, String), linkURL(String, String)
    case copyLink(String), openFile(String), heighten(String, Int), fitHeight(String), widenColumn(String, col: Int, by: Int)
    // To-dos
    case todos(Bool), addTodo(String), status(String, String), reorderTodo(String, TodoMove)
    case todoToSheet(String, String), deleteTodo(String), todoSort(String), doneSinks(Bool)
    case renameTodo(String, String), todoToBlock(String)
    // Settings
    case appearance(String), defaultFont(String), animation(String), newSheetEachDay(Bool)
    case undo
}

/// What the menu needs to know, as plain values.
struct ScratchpadCommandState: Equatable {
    struct Sheet: Equatable {
        var id: String
        /// As the list shows it: "Untitled sheet" when it has none.
        var title: String
        /// What's in the title box, which may be nothing.
        var typed = ""
        /// Its date, or "Pinned".
        var detail: String?
        var tags: [String] = []
        /// "3 blocks and 2 to-dos", for the question before it's deleted.
        var contents: String?
    }

    struct Todo: Equatable {
        var id: String
        var text: String
        /// open, done or deferred.
        var status = "open"
    }

    struct Block: Equatable {
        var id: String
        /// text, table, image, file, link, code or divider.
        var kind: String
        /// How the menu names it: "Text “Call Sam”".
        var name: String
        var font = "sans"
        var fontSize = 14
        var bold = false
        var italic = false
        var rotation = 0.0
        var rows = 0
        var cols = 0
        var url: String?
        /// A text or code block's words; a link's title.
        var text: String?
        /// A table's cells as typed (formulas as written), row by row.
        var cells: [[String]] = []
        /// Its height when one has been set; nil when it fits its contents.
        var height: Int?
        /// Its table's column widths.
        var widths: [Int] = []
    }

    /// Where the to-do list goes on this screen: a sheet over the phone, a column sliding over a narrow sheet, or a
    /// column beside a wide one.
    enum TodoLayout: Equatable { case sheet, slideOver, column }

    var sheets: [Sheet] = []
    /// The open sheet, when it's the one on screen. Nil on the phone's sheet list.
    var current: Sheet?
    /// The open sheet's to-dos, in the order they're shown.
    var todos: [Todo] = []
    /// The to-do being typed in.
    var todo: Todo?
    var blocks: [Block] = []
    var block: Block?
    /// What Undo would put back, if anything can come back.
    var undo: String?

    var searchText = ""
    /// The menu is drawn on the monitor: what only the phone can show is offered another way there.
    var monitorShows = false
    /// "iCloud Drive" or "This device", for Settings.
    var storePlace = ""
    var railMode = "byDay"
    var tagSort = "alphabetical"
    /// The sheet list sits beside the sheet (iPad), rather than being a screen of its own (phone).
    var wide = false
    var sidebarShowing = true
    var todoLayout: TodoLayout = .sheet
    var todosShowing = false
    var todoSort = "manual"
    var doneSinks = true

    var appearance = "system"
    var dark = false
    var defaultFont = "sans"
    var animation = "full"
    /// Today opens a fresh sheet each morning. Off by default: only New makes one.
    var newSheetEachDay = false
    var reduceMotion = false
    /// Every tag in use, most used first.
    var tags: [String] = []

    static let appearances = [("system", "Match the system"), ("light", "Light"), ("dark", "Dark")]
    static let fonts = [("sans", "Sans"), ("serif", "Serif"), ("mono", "Mono"), ("hand", "Hand")]
    static let animations = [("full", "Full", "Sheets peel, blocks fall, ticks pop"),
                             ("subtle", "Subtle", "Quick fades and small moves"),
                             ("off", "Off", "Everything changes at once")]
    static let todoSorts = [("manual", "Manual (drag)"), ("openFirst", "Open first"), ("overdueFirst", "Overdue first"),
                            ("alphabetical", "A to Z"), ("oldestFirst", "Oldest first")]
    static let railModes = [("byDay", "By day"), ("byMonth", "By month"), ("recent", "Recent"), ("byTag", "By tag")]
    static let tagSorts = [("alphabetical", "A to Z"), ("mostSheets", "Most sheets"), ("recentlyUsed", "Recently used")]
    static let inserts = [("text", "Text", "text.alignleft"), ("table", "Table", "tablecells"),
                          ("code", "Code", "chevron.left.forwardslash.chevron.right"), ("link", "Link", "link"),
                          ("divider", "Divider", "minus")]
    static let sizes = [10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 48]
    /// The canvas grid, which a nudge moves by.
    static let grid = 24
}

struct ScratchpadCommandList: CommandList {
    typealias Row = CommandRow<ScratchpadCommand>
    typealias State = ScratchpadCommandState
    var state: State

    /// Reads "fri", "+3", "15 oct" as a day: its key and how to say it. The app sets the core's; tests set their own.
    nonisolated(unsafe) static var readDate: (String) -> (key: String, label: String)? = { _ in nil }

    func prompt(stage: String?) -> String { "Do anything, or find a sheet" }

    func rows(stage: String?, typing: Bool) -> [Row] {
        var out: [Row] = []
        if let todo = state.todo { out += commands(for: todo, context: "“\(todo.text)”") }
        if let block = state.block { out += commands(for: block) }
        out += going
        if let sheet = state.current { out += sheetCommands(sheet) + todoCommands(sheet) + blockCommands }
        out += settings
        if let undo = state.undo {
            out.append(Row("undo", "Undo", detail: undo, symbol: "arrow.uturn.backward", step: .run(.undo),
                           synonyms: ["put back", "restore"]))
        }
        return out
    }

    // MARK: Getting around

    private var going: [Row] {
        var out = [
            Row("today", "Today", detail: "Today's sheet", symbol: "sun.max", step: .run(.today)),
            Row("sheets", "Go to the sheet list", symbol: "list.bullet", step: .run(.sheets),
                synonyms: ["sheets", "home", "rail", "sidebar", "list"]),
            openSheet,
            Row("new", "New sheet", detail: "Dated today", symbol: "plus", step: .run(.newSheet),
                synonyms: ["add", "create", "blank"]),
            newOnDate,
            Row("pinned", "New pinned sheet…", symbol: "pin",
                step: .ask(CommandAsk(prompt: "Its title", title: { "New pinned sheet, “\($0)”" },
                                      make: { t in let s = Self.trim(t); return s.isEmpty ? nil : .newPinned(s) })),
                synonyms: ["undated", "keep"]),
            Row("search", "Search…", detail: state.searchText.isEmpty ? "Sheets, blocks and to-dos" : "Now “\(state.searchText)”",
                symbol: "magnifyingglass",
                step: .ask(CommandAsk(prompt: "Search sheets, blocks and to-dos", initial: state.searchText,
                                      title: { "Search for “\($0)”" },
                                      make: { t in let s = Self.trim(t); return s.isEmpty ? nil : .search(s) })),
                synonyms: ["find", "filter"]),
        ]
        if !state.searchText.isEmpty {
            out.append(Row("search.clear", "Stop searching", detail: "Now “\(state.searchText)”", symbol: "xmark.circle",
                           step: .run(.clearSearch), synonyms: ["clear search", "show every sheet"]))
        }
        out += [railModePick, tagSortPick]
        if state.wide {
            out.append(Row.toggle("sidebar", isOn: state.sidebarShowing, turnOn: "Show the sheet list",
                                  turnOff: "Hide the sheet list", states: ("Showing", "Hidden"),
                                  symbol: "sidebar.left", action: .sidebar(!state.sidebarShowing),
                                  synonyms: ["sidebar", "rail", "full screen"]))
        }
        out.append(Row("delete.other", "Delete a sheet…", symbol: "trash",
                       step: .pick(CommandPick(prompt: "Which sheet? It asks first.",
                                               choices: state.sheets.map {
                                                   Row("delete." + $0.id, $0.title, detail: $0.detail, symbol: "trash",
                                                       step: .confirm(deleteConfirm($0)), confirms: true, destructive: true)
                                               },
                                               nothing: "No sheet by that name.", searchable: false)),
                       confirms: true, synonyms: ["remove", "bin"], destructive: true))
        out += [
            Row("export", "Export…", detail: "Image, to-dos or everything, to a file", symbol: "square.and.arrow.up",
                step: .run(.export), synonyms: ["save", "share", "png", "markdown", "archive", "backup"],
                onPhone: "Choose what to export and where to save it on the phone. The Copy commands work from here."),
            Row("copy.everything", "Copy every sheet as Markdown", symbol: "doc.on.doc", step: .run(.copyEverything),
                synonyms: ["export", "clipboard", "all"]),
            Row("import", "Import an archive…", detail: "From a file", symbol: "square.and.arrow.down",
                step: .run(.importArchive), synonyms: ["restore", "backup", "open file"],
                onPhone: "Choose the archive on the phone."),
        ]
        return out
    }

    private var openSheet: Row {
        let choices = state.sheets.map {
            Row("sheet." + $0.id, $0.title, detail: $0.detail, symbol: $0.detail == "Pinned" ? "pin" : "doc.text",
                step: .run(.open($0.id)), synonyms: $0.tags.map { "#" + $0 }, isCurrent: $0.id == state.current?.id)
        }
        return Row("open", "Open a sheet…", symbol: "doc.text.magnifyingglass",
                   step: .pick(CommandPick(prompt: "Which sheet?", choices: choices, nothing: "No sheet by that name.")),
                   synonyms: ["go to", "jump", "switch", "find sheet"])
    }

    private var newOnDate: Row {
        let calendar = Row("onDate.grid", "Choose on the calendar…", symbol: "calendar", step: .run(.chooseNewDate),
                           synonyms: ["grid", "month"])
        return Row("onDate", "New sheet on a date…", symbol: "calendar.badge.plus",
                   step: .ask(CommandAsk(prompt: "When? today, fri, 15 oct, +3",
                                         suggestions: state.monitorShows ? days("onDate.day", { .newOnDate($0) }) : [calendar],
                                         nothing: "Try today, tomorrow, fri, 15 oct, +3 or -2.",
                                         title: { Self.readDate($0).map { "New sheet on \($0.label)" } ?? "" },
                                         make: { Self.readDate($0).map { .newOnDate($0.key) } })),
                   synonyms: ["calendar", "day", "future"])
    }

    /// The month grid is a phone sheet, so on the monitor the next two weeks are offered instead.
    private func days(_ id: String, _ action: (String) -> ScratchpadCommand) -> [Row] {
        (0..<14).compactMap { n in
            Self.readDate(n == 0 ? "today" : "+\(n)").map { day in
                Row("\(id).\(n)", day.label, symbol: "calendar", step: .run(action(day.key)))
            }
        }
    }

    /// "Delete “Planning”?", asked in the menu, where the monitor shows it.
    private func deleteConfirm(_ sheet: State.Sheet) -> CommandConfirm<ScratchpadCommand> {
        CommandConfirm(prompt: "Delete “\(sheet.title)”?", title: "Delete “\(sheet.title)”",
                       detail: (sheet.contents.map { "\($0) go for good. " } ?? "") + "This can’t be undone.",
                       action: .deleteSheet(sheet.id))
    }

    private var railModePick: Row {
        let choices = State.railModes.map { id, title in
            Row("rail." + id, title, symbol: "rectangle.grid.1x2", step: .run(.railMode(id)), isCurrent: state.railMode == id)
        }
        return Row("rail", "Group sheets…", detail: Self.label(state.railMode, State.railModes), symbol: "rectangle.grid.1x2",
                   step: .pick(CommandPick(prompt: "Group the sheet list how?", choices: choices)),
                   synonyms: ["by day", "by month", "recent", "by tag", "sidebar", "sort sheets"])
    }

    private var tagSortPick: Row {
        let choices = State.tagSorts.map { id, title in
            Row("tagsort." + id, title, symbol: "number", step: .run(.tagSort(id)), isCurrent: state.tagSort == id)
        }
        return Row("tagsort", "Sort tags…", detail: (Self.label(state.tagSort, State.tagSorts) ?? "") + ", in By tag",
                   symbol: "number", step: .pick(CommandPick(prompt: "Sort the tags how?", choices: choices)),
                   synonyms: ["order", "by tag"])
    }

    // MARK: The open sheet

    private func sheetCommands(_ sheet: State.Sheet) -> [Row] {
        let named = sheet.title
        var out = [
            Row("sheet.rename", "Rename this sheet…", symbol: "character.cursor.ibeam",
                step: .ask(CommandAsk(prompt: "Its new title", initial: sheet.typed, title: { "Rename to “\($0)”" },
                                      make: { t in let s = Self.trim(t); return s.isEmpty || s == sheet.typed ? nil : .rename(s) })),
                synonyms: ["title", "retitle", "name"]),
            moveSheet(sheet),
            addTag(sheet),
        ]
        if !sheet.tags.isEmpty {
            let choices = sheet.tags.map {
                Row("untag." + $0, "#" + $0, symbol: "number", step: .run(.removeTag($0)), destructive: true, undoable: true)
            }
            out.append(Row("sheet.untag", "Remove a tag…", detail: sheet.tags.map { "#" + $0 }.joined(separator: " "),
                           symbol: "tag.slash", step: .pick(CommandPick(prompt: "Which tag?", choices: choices)),
                           synonyms: ["untag"], destructive: true, undoable: true))
        }
        out += [
            Row("copy.image", "Copy this sheet as an image", symbol: "photo.on.rectangle", step: .run(.copyImage),
                synonyms: ["png", "picture", "screenshot", "clipboard", "export"]),
            Row("copy.todos", "Copy the to-dos as Markdown", symbol: "list.bullet.clipboard", step: .run(.copyTodos),
                synonyms: ["checklist", "clipboard", "export", "text"]),
            Row("duplicate", "Duplicate this sheet", symbol: "plus.square.on.square", step: .run(.duplicate),
                synonyms: ["copy sheet", "clone"]),
            Row("delete", "Delete this sheet…", detail: "Asks first: “\(named)”", symbol: "trash",
                step: .confirm(deleteConfirm(sheet)), confirms: true, synonyms: ["remove", "bin"], destructive: true),
        ]
        return out
    }

    private func moveSheet(_ sheet: State.Sheet) -> Row {
        let calendar = Row("sheet.date.grid", "Choose on the calendar…", symbol: "calendar", step: .run(.chooseSheetDate),
                           synonyms: ["grid", "month"])
        return Row("sheet.date", "Change the date…", detail: sheet.detail, symbol: "calendar",
                   step: .ask(CommandAsk(prompt: "To when? today, fri, 15 oct, +3",
                                         suggestions: state.monitorShows ? days("sheet.date.day", { .moveSheet($0) }) : [calendar],
                                         nothing: "Try today, tomorrow, fri, 15 oct, +3 or -2.",
                                         title: { Self.readDate($0).map { "Move to \($0.label)" } ?? "" },
                                         make: { Self.readDate($0).map { .moveSheet($0.key) } })),
                   synonyms: ["move", "reschedule", "day", "date"])
    }

    private func addTag(_ sheet: State.Sheet) -> Row {
        let suggestions = state.tags.filter { !sheet.tags.contains($0) }.map {
            Row("tag." + $0, "#" + $0, symbol: "number", step: .run(.addTag($0)))
        }
        return Row("sheet.tag", "Add a tag…", detail: sheet.tags.isEmpty ? nil : sheet.tags.map { "#" + $0 }.joined(separator: " "),
                   symbol: "tag",
                   step: .ask(CommandAsk(prompt: "A tag, new or old", suggestions: suggestions,
                                         title: { "Tag it #\(Self.tagged($0))" },
                                         make: { t in
                                             let s = Self.tagged(t)
                                             return s.isEmpty || sheet.tags.contains(s) ? nil : .addTag(s)
                                         })),
                   synonyms: ["label", "hashtag"])
    }

    // MARK: To-dos

    private func todoCommands(_ sheet: State.Sheet) -> [Row] {
        var out: [Row] = []
        switch state.todoLayout {
        case .sheet:
            if !state.todosShowing {
                out.append(Row("todos", "Show the to-dos", symbol: "checklist", step: .run(.todos(true)),
                               synonyms: ["to-do list", "todo", "tasks"]))
            }
        case .slideOver, .column:
            out.append(Row.toggle("todos", isOn: state.todosShowing, turnOn: "Show the to-dos", turnOff: "Hide the to-dos",
                                  states: ("Showing", "Hidden"), symbol: "checklist", action: .todos(!state.todosShowing),
                                  synonyms: ["to-do list", "todo", "tasks", "column"]))
        }
        out.append(Row("todo.add", "Add a to-do…", detail: "⇧⌘T", symbol: "plus.circle",
                       step: .ask(CommandAsk(prompt: "The to-do", title: { "Add “\($0)”" },
                                             make: { t in let s = Self.trim(t); return s.isEmpty ? nil : .addTodo(s) })),
                       synonyms: ["new to-do", "todo", "task", "remember"]))
        let open = state.todos.filter { $0.status != "done" }
        if !open.isEmpty {
            out.append(Row("todo.tick", "Tick a to-do…", symbol: "checkmark.circle",
                           step: .pick(CommandPick(prompt: "Which one is done?", choices: open.map {
                               Row("tick." + $0.id, $0.text, detail: $0.status == "deferred" ? "Deferred" : nil,
                                   symbol: "circle", step: .run(.status($0.id, "done")))
                           }, nothing: "No open to-do by that name.")),
                           synonyms: ["done", "complete", "check", "finish", "todo"]))
        }
        if !state.todos.isEmpty {
            out.append(Row("todo.pick", "A to-do…", detail: "Tick, defer, move or delete one", symbol: "checklist.checked",
                           step: .pick(CommandPick(prompt: "Which to-do?", choices: state.todos.map {
                               Row("todo." + $0.id, $0.text, detail: Self.statusWord($0.status),
                                   symbol: Self.statusSymbol($0.status),
                                   step: .pick(CommandPick(prompt: "Do what with it?", choices: commands(for: $0, context: nil),
                                                           searchable: false)))
                           }, nothing: "No to-do by that name.", searchable: false)),
                           synonyms: ["todo", "task", "defer", "reopen", "move to-do", "delete to-do", "reorder"]))
        }
        out.append(todoSortPick)
        out.append(Row.toggle("todo.sinks", isOn: state.doneSinks, turnOn: "Sink done to-dos to the bottom",
                              turnOff: "Keep done to-dos in place", states: ("Done sinks", "Done stays"),
                              symbol: "arrow.down.to.line", action: .doneSinks(!state.doneSinks),
                              synonyms: ["done sinks", "sort to-dos"]))
        return out
    }

    /// What can be done to one to-do: at the top for the one being typed in (`context`), and inside "A to-do…".
    private func commands(for todo: State.Todo, context: String?) -> [Row] {
        var out: [Row] = []
        if todo.status != "done" {
            out.append(Row("todo.done", "Mark done", symbol: "checkmark.circle", step: .run(.status(todo.id, "done")),
                           synonyms: ["tick", "complete", "check", "finish"], context: context))
        }
        if todo.status != "deferred" {
            out.append(Row("todo.defer", "Defer", detail: "Not today", symbol: "arrow.uturn.forward.circle",
                           step: .run(.status(todo.id, "deferred")), synonyms: ["later", "postpone", "snooze"], context: context))
        }
        if todo.status != "open" {
            out.append(Row("todo.reopen", "Mark open", symbol: "circle", step: .run(.status(todo.id, "open")),
                           synonyms: ["untick", "undone", "reopen"], context: context))
        }
        out.append(Row("todo.words", "Change its words…", symbol: "character.cursor.ibeam",
                       step: .ask(CommandAsk(prompt: "The to-do", initial: todo.text, title: { "Change to “\($0)”" },
                                             make: { t in
                                                 let s = Self.trim(t)
                                                 return s.isEmpty || s == todo.text ? nil : .renameTodo(todo.id, s)
                                             })),
                       synonyms: ["rename", "edit", "reword", "retype", "text"], context: context))
        let i = state.todos.firstIndex { $0.id == todo.id }
        if let i, i > 0 {
            out += [Row("todo.up", "Move up", symbol: "arrow.up", step: .run(.reorderTodo(todo.id, .up)),
                        synonyms: ["reorder", "raise", "higher"], context: context),
                    Row("todo.top", "Move to the top", symbol: "arrow.up.to.line", step: .run(.reorderTodo(todo.id, .top)),
                        synonyms: ["reorder", "first"], context: context)]
        }
        if let i, i < state.todos.count - 1 {
            out += [Row("todo.down", "Move down", symbol: "arrow.down", step: .run(.reorderTodo(todo.id, .down)),
                        synonyms: ["reorder", "lower"], context: context),
                    Row("todo.bottom", "Move to the bottom", symbol: "arrow.down.to.line",
                        step: .run(.reorderTodo(todo.id, .bottom)), synonyms: ["reorder", "last"], context: context)]
        }
        let others = state.sheets.filter { $0.id != state.current?.id }
        if !others.isEmpty {
            out.append(Row("todo.move", "Move to another sheet…", symbol: "arrow.right.doc.on.clipboard",
                           step: .pick(CommandPick(prompt: "Which sheet?", choices: others.map {
                               Row("todo.to." + $0.id, $0.title, detail: $0.detail, symbol: "doc.text",
                                   step: .run(.todoToSheet(todo.id, $0.id)))
                           }, nothing: "No sheet by that name.", searchable: false)),
                           synonyms: ["send", "carry", "other sheet"], context: context))
        }
        if state.current != nil {
            out.append(Row("todo.toBlock", "Put it on the sheet", detail: "As a text block", symbol: "rectangle.and.pencil.and.ellipsis",
                           step: .run(.todoToBlock(todo.id)), synonyms: ["block", "canvas", "turn into block", "drag"],
                           context: context))
        }
        out.append(Row("todo.delete", "Delete this to-do", symbol: "trash", step: .run(.deleteTodo(todo.id)),
                       synonyms: ["remove", "bin"], destructive: true, undoable: true, context: context))
        return out
    }

    private var todoSortPick: Row {
        let choices = State.todoSorts.map { id, title in
            Row("todosort." + id, title, symbol: "arrow.up.arrow.down", step: .run(.todoSort(id)), isCurrent: state.todoSort == id)
        }
        return Row("todosort", "Sort the to-dos…", detail: Self.label(state.todoSort, State.todoSorts), symbol: "arrow.up.arrow.down",
                   step: .pick(CommandPick(prompt: "Sort the to-dos how?", choices: choices)),
                   synonyms: ["order", "todo", "overdue", "oldest"])
    }

    // MARK: Blocks

    private var blockCommands: [Row] {
        let kinds = State.inserts.map { id, title, symbol in
            Row("insert:" + id, title, symbol: symbol, step: .run(.insert(id)))
        }
        var out = [
            Row("insert", "Insert a block…", symbol: "text.badge.plus",
                step: .pick(CommandPick(prompt: "Insert what?", choices: kinds)), synonyms: ["add block", "new block"]),
            Row("paste", "Paste as a block", detail: "⇧⌘V", symbol: "doc.on.clipboard", step: .run(.paste),
                synonyms: ["clipboard"]),
        ]
        if !state.blocks.isEmpty {
            out.append(Row("block.select", "Select a block…", symbol: "cursorarrow.rays",
                           step: .pick(CommandPick(prompt: "Which block?", choices: state.blocks.map {
                               Row("select." + $0.id, $0.name, symbol: Self.kindSymbol($0.kind), step: .run(.selectBlock($0.id)),
                                   isCurrent: $0.id == state.block?.id)
                           }, nothing: "No block by that name.", searchable: false)),
                           synonyms: ["choose block", "pick block", "focus"]))
        }
        return out
    }

    private func commands(for b: State.Block) -> [Row] {
        let named = b.name
        var out: [Row] = []
        out += editCommands(b, named)
        if b.kind == "link", let url = b.url, !url.isEmpty {
            out.append(Row("block.link", "Open the link", detail: url, symbol: "arrow.up.right.square", step: .run(.openLink(b.id)),
                           synonyms: ["browser", "url", "visit"], context: named, onPhone: "The link opens on the phone."))
            out.append(Row("block.copyLink", "Copy the link", detail: url, symbol: "link", step: .run(.copyLink(b.id)),
                           synonyms: ["url", "clipboard", "address"], context: named))
        }
        if b.kind == "file" {
            out.append(Row("block.file", "Open the file", symbol: "doc", step: .run(.openFile(b.id)),
                           synonyms: ["show", "preview", "attachment"], context: named, onPhone: "The file opens on the phone."))
        }
        if b.kind == "table" {
            out += [Row("table.row", "Add a row", symbol: "plus.rectangle", step: .run(.addRow(b.id)), synonyms: ["table"], context: named),
                    Row("table.col", "Add a column", symbol: "plus.rectangle.portrait", step: .run(.addColumn(b.id)),
                        synonyms: ["table"], context: named)]
            if b.rows > 1 {
                out.append(Row("table.unrow", "Remove the last row", symbol: "minus.rectangle", step: .run(.removeRow(b.id)),
                               synonyms: ["table", "delete row"], destructive: true, undoable: true, context: named))
            }
            if b.cols > 1 {
                out.append(Row("table.uncol", "Remove the last column", symbol: "minus.rectangle.portrait",
                               step: .run(.removeColumn(b.id)), synonyms: ["table", "delete column"],
                               destructive: true, undoable: true, context: named))
            }
        }
        out += [
            Row("block.duplicate", "Duplicate the block", symbol: "plus.square.on.square", step: .run(.duplicateBlock(b.id)),
                synonyms: ["copy", "clone"], context: named),
            Row("block.rotate", "Rotate 15°", detail: b.rotation == 0 ? nil : "Now \(Int(b.rotation))°", symbol: "rotate.right",
                step: .run(.rotate(b.id)), synonyms: ["tilt", "turn", "angle"], context: named),
        ]
        if b.rotation != 0 {
            out.append(Row("block.unrotate", "Straighten", detail: "Back to 0°", symbol: "arrow.counterclockwise",
                           step: .run(.unrotate(b.id)), synonyms: ["reset rotation", "level", "untilt"], context: named))
        }
        if ["text", "code", "table", "link", "file"].contains(b.kind) {
            out += textCommands(b, named)
        }
        let g = State.grid
        out += [
            Row("block.left", "Nudge left", symbol: "arrow.left", step: .run(.nudge(b.id, dx: -g, dy: 0)),
                synonyms: ["move block"], context: named),
            Row("block.right", "Nudge right", symbol: "arrow.right", step: .run(.nudge(b.id, dx: g, dy: 0)),
                synonyms: ["move block"], context: named),
            Row("block.up", "Nudge up", symbol: "arrow.up", step: .run(.nudge(b.id, dx: 0, dy: -g)),
                synonyms: ["move block"], context: named),
            Row("block.down", "Nudge down", symbol: "arrow.down", step: .run(.nudge(b.id, dx: 0, dy: g)),
                synonyms: ["move block"], context: named),
            Row("block.wider", "Make it wider", symbol: "arrow.left.and.right", step: .run(.widen(b.id, g * 2)),
                synonyms: ["resize", "bigger", "stretch"], context: named),
            Row("block.narrower", "Make it narrower", symbol: "arrow.right.and.line.vertical.and.arrow.left",
                step: .run(.widen(b.id, -g * 2)), synonyms: ["resize", "smaller", "shrink"], context: named),
            Row("block.taller", "Make it taller", detail: b.height.map { "Now \($0) pt" }, symbol: "arrow.up.and.down",
                step: .run(.heighten(b.id, g * 2)), synonyms: ["resize", "height", "longer", "stretch"], context: named),
        ]
        if b.height != nil {
            out += [Row("block.shorter", "Make it shorter", symbol: "arrow.down.and.line.horizontal.and.arrow.up",
                        step: .run(.heighten(b.id, -g * 2)), synonyms: ["resize", "height", "squash"], context: named),
                    Row("block.fit", "Fit its height to what’s in it", symbol: "arrow.up.and.down.text.horizontal",
                        step: .run(.fitHeight(b.id)), synonyms: ["auto height", "resize", "reset height"], context: named)]
        }
        out += [
            Row("block.deselect", "Let go of the block", symbol: "cursorarrow.slash", step: .run(.deselect),
                synonyms: ["deselect", "unselect"], context: named),
            Row("block.delete", "Delete the block", detail: "⌫", symbol: "trash", step: .run(.deleteBlock(b.id)),
                synonyms: ["remove", "bin"], destructive: true, undoable: true, context: named),
        ]
        return out
    }

    /// Putting words on a block from the keyboard: the caret into it (↩, and Esc to stop), or the words typed in the menu.
    private func editCommands(_ b: State.Block, _ named: String) -> [Row] {
        var out: [Row] = []
        switch b.kind {
        case "text", "code":
            out.append(Row("block.edit", "Edit the block", detail: "↩, then Esc when done", symbol: "character.cursor.ibeam",
                           step: .run(.editBlock(b.id)), synonyms: ["type", "write", "caret", "focus", "edit text"], context: named))
            let words = b.text ?? ""
            out.append(Row("block.words", "Change its words…", symbol: "text.cursor",
                           step: .ask(CommandAsk(prompt: "Its words", initial: words, title: { "Change to “\($0)”" },
                                                 make: { $0 == words ? nil : .setText(b.id, $0) })),
                           synonyms: ["rename", "retype", "replace text", "edit"], context: named))
        case "link":
            out.append(Row("block.edit", "Edit the link", detail: "↩, then Esc when done", symbol: "character.cursor.ibeam",
                           step: .run(.editBlock(b.id)), synonyms: ["type", "write", "caret", "focus", "edit"], context: named))
            let title = b.text ?? "", url = b.url ?? ""
            out.append(Row("link.title", "Link title…", detail: title.isEmpty ? nil : title, symbol: "textformat",
                           step: .ask(CommandAsk(prompt: "The link’s title", initial: title, title: { "Title it “\($0)”" },
                                                 make: { t in let s = Self.trim(t); return s == title ? nil : .linkTitle(b.id, s) })),
                           synonyms: ["name", "rename", "label"], context: named))
            out.append(Row("link.url", "Link address…", detail: url.isEmpty ? nil : url, symbol: "link",
                           step: .ask(CommandAsk(prompt: "https://", initial: url, title: { "Link to \($0)" },
                                                 make: { t in let s = Self.trim(t); return s.isEmpty || s == url ? nil : .linkURL(b.id, s) })),
                           synonyms: ["url", "web address", "href"], context: named))
        case "table":
            out.append(Row("table.edit", "Edit the table", detail: "↩ · Tab next cell · ↩ down · Esc when done",
                           symbol: "character.cursor.ibeam", step: .run(.editCell(b.id, row: 0, col: 0)),
                           synonyms: ["type", "write", "cell", "caret", "focus"], context: named))
            out.append(cellPick(b, named))
            if b.cols > 0 {
                out.append(columnPick(b, named, wider: true))
                out.append(columnPick(b, named, wider: false))
            }
        default: break
        }
        return out
    }

    /// "Change a cell…" › "B2  Total" › its contents typed, formula and all.
    private func cellPick(_ b: State.Block, _ named: String) -> Row {
        var choices: [Row] = []
        for (r, row) in b.cells.enumerated() {
            for c in 0..<max(b.cols, row.count) {
                let raw = c < row.count ? row[c] : ""
                let at = Self.cellName(r, c)
                choices.append(Row("cell.\(r).\(c)", raw.isEmpty ? at : "\(at)  \(raw)", detail: raw.isEmpty ? "Empty" : nil,
                                   symbol: "tablecells",
                                   step: .ask(CommandAsk(prompt: "\(at): a value or =formula", initial: raw,
                                                         title: { $0.isEmpty ? "Empty \(at)" : "\(at) is “\($0)”" },
                                                         make: { $0 == raw ? nil : .setCell(b.id, row: r, col: c, $0) })),
                                   synonyms: [at.lowercased()]))
            }
        }
        return Row("table.cell", "Change a cell…", detail: "Its value or formula", symbol: "tablecells",
                   step: .pick(CommandPick(prompt: "Which cell? A1, B2…", choices: choices, nothing: "No cell by that name.",
                                           searchable: false)),
                   synonyms: ["cell", "formula", "value", "type in table"], context: named)
    }

    private func columnPick(_ b: State.Block, _ named: String, wider: Bool) -> Row {
        let by = wider ? State.grid * 2 : -State.grid * 2
        let choices = (0..<b.cols).map { c in
            Row("col.\(wider ? "w" : "n").\(c)", "Column \(Self.columnName(c))",
                detail: c < b.widths.count ? "Now \(b.widths[c]) pt" : nil, symbol: "rectangle.split.3x1",
                step: .run(.widenColumn(b.id, col: c, by: by)))
        }
        return Row(wider ? "table.colWider" : "table.colNarrower", wider ? "Widen a column…" : "Narrow a column…",
                   symbol: wider ? "arrow.left.and.right" : "arrow.right.and.line.vertical.and.arrow.left",
                   step: .pick(CommandPick(prompt: "Which column?", choices: choices, searchable: false)),
                   synonyms: ["column width", "resize column"], context: named)
    }

    /// A, B … Z, AA: as the table's letters.
    static func columnName(_ c: Int) -> String {
        var n = c, out = ""
        repeat {
            out = String(UnicodeScalar(UInt8(65 + n % 26))) + out
            n = n / 26 - 1
        } while n >= 0
        return out
    }

    static func cellName(_ r: Int, _ c: Int) -> String { "\(columnName(c))\(r + 1)" }

    /// Font, size, bold and italic, as the font panel has them. Arrowing through fonts and sizes shows each on the block.
    private func textCommands(_ b: State.Block, _ named: String) -> [Row] {
        let fonts = State.fonts.map { id, title in
            Row("font." + id, title, symbol: "textformat", step: .run(.font(b.id, id)), preview: .font(b.id, id),
                isCurrent: b.font == id)
        }
        let sizes = Set(State.sizes + [b.fontSize]).sorted().map { n in
            Row("size.\(n)", "\(n) pt", symbol: "textformat.size", step: .run(.fontSize(b.id, n)), preview: .fontSize(b.id, n),
                isCurrent: b.fontSize == n)
        }
        var out = [
            Row("block.font", "Font…", detail: Self.label(b.font, State.fonts), symbol: "textformat",
                step: .pick(CommandPick(prompt: "Which font?", choices: fonts, revert: .font(b.id, b.font))),
                synonyms: ["typeface", "serif", "sans", "mono", "hand"], context: named),
            Row("block.size", "Text size…", detail: "\(b.fontSize) pt", symbol: "textformat.size",
                step: .pick(CommandPick(prompt: "How big?", choices: sizes, revert: .fontSize(b.id, b.fontSize), searchable: false)),
                synonyms: ["font size", "points"], context: named),
        ]
        if b.fontSize < State.sizes.last! {
            out.append(Row("block.bigger", "Text larger", detail: "\(min(48, b.fontSize + 2)) pt", symbol: "textformat.size.larger",
                           step: .run(.fontSize(b.id, min(48, b.fontSize + 2))), synonyms: ["bigger", "increase"], context: named))
        }
        if b.fontSize > State.sizes.first! {
            out.append(Row("block.smaller", "Text smaller", detail: "\(max(10, b.fontSize - 2)) pt", symbol: "textformat.size.smaller",
                           step: .run(.fontSize(b.id, max(10, b.fontSize - 2))), synonyms: ["decrease"], context: named))
        }
        out += [
            Row.toggle("block.bold", isOn: b.bold, turnOn: "Bold", turnOff: "Not bold", symbol: "bold", action: .bold(b.id, !b.bold),
                       synonyms: ["heavy", "strong"], context: named),
            Row.toggle("block.italic", isOn: b.italic, turnOn: "Italic", turnOff: "Not italic", symbol: "italic",
                       action: .italic(b.id, !b.italic), synonyms: ["slanted", "emphasis"], context: named),
        ]
        return out
    }

    // MARK: Settings

    /// Every setting is a command of its own (the kit's `CommandSettings`), so none needs the phone's Settings screen.
    private var settings: [Row] {
        func options(_ list: [(String, String)], _ symbol: String) -> [CommandOption] {
            list.map { CommandOption($0.0, $0.1, symbol: symbol) }
        }
        var out = CommandSettings.rows([CommandSetting<ScratchpadCommand>]([
            .choice("look", "Appearance", symbol: "circle.lefthalf.filled",
                    options: options(State.appearances, "circle.lefthalf.filled"), current: state.appearance, previews: true,
                    synonyms: ["theme", "dark mode", "light mode", "night", "colours", "colors"], set: { .appearance($0) }),
            .choice("newfont", "Font for new blocks", symbol: "textformat", options: options(State.fonts, "textformat"),
                    current: state.defaultFont, synonyms: ["default font", "typeface"], set: { .defaultFont($0) }),
            .choice("motion", "Animation", symbol: "sparkles",
                    options: State.animations.map { CommandOption($0.0, $0.1, detail: $0.2, symbol: "sparkles") },
                    current: state.animation, synonyms: ["motion", "whimsy", "effects", "reduce motion"], set: { .animation($0) }),
            .toggle("daily", "A new sheet each day", symbol: "sun.max", isOn: state.newSheetEachDay,
                    synonyms: ["daily sheet", "new day", "today's sheet", "every day"], set: { .newSheetEachDay($0) }),
        ]))
        if state.reduceMotion, let i = out.firstIndex(where: { $0.id == "setting.motion" }) {
            out[i].detail = "Off: Reduce Motion is on in system settings"
        }
        out.insert(Row.toggle("look.dark", isOn: state.dark, turnOn: "Switch to dark", turnOff: "Switch to light",
                              states: ("Dark", "Light"), symbol: state.dark ? "sun.max" : "moon",
                              action: .appearance(state.dark ? "light" : "dark"),
                              synonyms: ["dark mode", "light mode", "night", "theme"]), at: 1)
        out.append(Row("settings", "Settings", detail: state.storePlace.isEmpty ? "Where your sheets are kept"
                                                                               : "Sheets are kept in: \(state.storePlace)",
                       symbol: "gearshape", step: .run(.settings), synonyms: ["preferences", "options", "icloud", "store"],
                       onPhone: "Settings are open on the phone. Each setting is in ⌘K too: type “setting”."))
        return out
    }

    // MARK: Words

    static func label(_ id: String, _ options: [(String, String)]) -> String? { options.first { $0.0 == id }?.1 }

    static func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A tag as the sheet keeps it: no #, lower case, words joined.
    /// As the core's `Tags.normalize`: lower case, no #, only a to z, digits, _ and -, starting with a letter or digit.
    static func tagged(_ s: String) -> String {
        var t = trim(s).lowercased()
        while t.hasPrefix("#") { t.removeFirst() }
        t = String(t.unicodeScalars.filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "-" }
            .map(Character.init))
        while let f = t.first, f == "_" || f == "-" { t.removeFirst() }
        return t
    }

    static func statusWord(_ s: String) -> String { s == "done" ? "Done" : s == "deferred" ? "Deferred" : "Open" }

    static func statusSymbol(_ s: String) -> String { s == "done" ? "checkmark.circle.fill" : s == "deferred" ? "circle.slash" : "circle" }

    static func kindSymbol(_ kind: String) -> String {
        switch kind {
        case "table": return "tablecells"
        case "code": return "chevron.left.forwardslash.chevron.right"
        case "link": return "link"
        case "divider": return "minus"
        case "image": return "photo"
        case "file": return "doc"
        default: return "text.alignleft"
        }
    }
}
