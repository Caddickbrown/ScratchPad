//
//  ScratchpadCommands.swift
//
//  ⌘K, from a hardware keyboard. The rules and keys are the kit's (kit/swift/CommandPalette.swift);
//  this is what's on Scratchpad's menu, with no UIKit or SwiftUI in sight, so
//  apple/Tests/commands-check/run.sh can check it. `CommandMenu.swift` is the glue and the drawing.
//
//  Deleting a sheet is an `askDelete`: it raises the same alert the menus do. A block has no row,
//  as its key has no question to go through, only the undo toast after it.
//

import Foundation

enum ScratchpadCommand: Equatable {
    enum Insert: Equatable { case text, table, code, link, divider }

    case sheets, today, settings
    case newSheet, newOnDate, newPinned, duplicate, askDelete
    case insert(Insert), todos, export, importArchive, undoDelete
}

struct ScratchpadCommandList: CommandList {
    /// A sheet is open.
    var hasSheet = false
    /// A deleted block can still come back.
    var canUndo = false

    func rows(stage: String?, typing: Bool) -> [CommandRow<ScratchpadCommand>] {
        typealias Row = CommandRow<ScratchpadCommand>
        if stage == "insert" { return inserts }

        var out = [Row("sheets", "Sheets", detail: "The list", symbol: "list.bullet", step: .run(.sheets)),
                   Row("today", "Today", detail: "Today's sheet", symbol: "sun.max", step: .run(.today)),
                   Row("settings", "Settings", symbol: "gearshape", step: .run(.settings)),
                   Row("new", "New sheet", symbol: "plus", step: .run(.newSheet))]
        if hasSheet {
            out += [Row("insert", "Insert a block", symbol: "text.badge.plus", step: .open("insert")),
                    Row("todos", "To-dos", symbol: "checklist", step: .run(.todos), search: "To-dos todo"),
                    Row("duplicate", "Duplicate this sheet", symbol: "plus.square.on.square", step: .run(.duplicate)),
                    Row("export", "Export", symbol: "square.and.arrow.up", step: .run(.export)),
                    Row("delete", "Delete this sheet", detail: "Asks first", symbol: "trash", step: .run(.askDelete), confirms: true)]
        } else {
            out.append(Row("export", "Export", symbol: "square.and.arrow.up", step: .run(.export)))
        }
        // A few letters away, which leaves the whole list showing before anything's typed.
        guard typing else { return out }
        out += [Row("onDate", "New sheet on a date", symbol: "calendar", step: .run(.newOnDate)),
                Row("pinned", "New pinned sheet", symbol: "pin", step: .run(.newPinned)),
                Row("import", "Import an archive", detail: "From a file", symbol: "square.and.arrow.down", step: .run(.importArchive))]
        if hasSheet { out += inserts }
        if canUndo { out.append(Row("undo", "Undo", detail: "The block comes back", symbol: "arrow.uturn.backward", step: .run(.undoDelete))) }
        return out
    }

    private var inserts: [CommandRow<ScratchpadCommand>] {
        typealias Row = CommandRow<ScratchpadCommand>
        return [Row("insert:text", "Text", symbol: "text.alignleft", step: .run(.insert(.text))),
                Row("insert:table", "Table", symbol: "tablecells", step: .run(.insert(.table))),
                Row("insert:code", "Code", symbol: "chevron.left.forwardslash.chevron.right", step: .run(.insert(.code))),
                Row("insert:link", "Link", symbol: "link", step: .run(.insert(.link))),
                Row("insert:divider", "Divider", symbol: "minus", step: .run(.insert(.divider)))]
    }

    func prompt(stage: String?) -> String { stage == "insert" ? "Insert what?" : "Where to?" }
}
