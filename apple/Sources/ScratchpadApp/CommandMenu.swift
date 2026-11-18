//
//  CommandMenu.swift
//
//  ⌘K. What it lists is `ScratchpadCommands.swift`, and what the keys mean is the kit's. This is the glue and the
//  drawing: what's on screen as a `ScratchpadCommandState`, and the panel on paper, over the phone, or on the monitor
//  when there is one (`MonitorBoard`). `RootView.runCommand` says what each row does, since it owns the sheet list.
//
//  Three ways in: ⌘K with a keyboard, "Commands" in the sheet's ⋯ menu, and the command button on the phone's sheet
//  list and the iPad's toolbar.
//
//  iOS only: the Mac has its menu bar.
//

#if os(iOS)
import Combine
import SwiftUI
import UIKit
import ScratchpadCore

@MainActor
enum ScratchpadCommandMenu {
    static let host: CommandHost<ScratchpadCommandList> = {
        let host = CommandHost<ScratchpadCommandList>()
        host.list = {
            guard let state = MonitorModel.shared.state else { return nil }
            // The to-do being typed in is the menu's while it's open: the field lets go of the keyboard as it opens.
            if host.menu == nil { typingTodo = typingTodoID(state) }
            return ScratchpadCommandList(state: commandState(state))
        }
        host.monitorShows = { MonitorModel.shared.isConnected }
        // The file picker has the screen and its own way out.
        host.blocked = { MonitorModel.shared.state?.showImport ?? false }
        // The way esc goes.
        host.leaveSheet = { MonitorModel.shared.state?.closeFrontmost() }
        host.recents = CommandRecents(key: "scratchpad.commands.recents")
        // A preview and its revert: just the change, with the menu still open.
        host.preview = { preview($0) }
        host.onCancel = { typingTodo = nil }
        host.overlay = { AnyView(Themed { ScratchpadCommandOverlay() }) }
        return host
    }()

    /// The phone's window is compact: the sheet list is a screen of its own. Set by `RootView`.
    static var compact = false
    private static var typingTodo: String?
    private static var watching: [AnyCancellable] = []

    /// Once, at launch.
    static func install() {
        CommandResponders.install()
        _ = host
        ScratchpadCommandList.readDate = { text in
            let today = DayKey.key(for: Date())
            return DatePhrase.parse(text, today: today).map { ($0, DayLabel.longDate($0)) }
        }
    }

    /// Once there's a state to watch: whatever changes while the menu is open (a preview, a tick), the list follows.
    static func watch(_ state: AppState) {
        guard watching.isEmpty else { return }
        let changed = Publishers.Merge(state.objectWillChange, MonitorModel.shared.objectWillChange)
        watching = [changed.debounce(for: .milliseconds(30), scheduler: DispatchQueue.main).sink { _ in host.refresh() }]
    }

    /// What a chosen command does, with the typed-in to-do let go.
    static func ran() { typingTodo = nil }

    private static func typingTodoID(_ state: AppState) -> String? {
        guard let field = state.caret?.field, field.hasPrefix("todo#") else { return nil }
        let id = String(field.dropFirst("todo#".count))
        return state.current?.todos.contains { $0.id == id && $0.isFilled } == true ? id : nil
    }

    // MARK: What's on screen

    static func commandState(_ state: AppState) -> ScratchpadCommandState {
        let d = UserDefaults.standard
        let model = MonitorModel.shared
        let sort = TodoSortMode(rawValue: d.string(forKey: SettingsKey.todoSort) ?? "") ?? .manual
        let sinks = d.object(forKey: SettingsKey.doneSinks) as? Bool ?? true
        // On the phone's sheet list, the open sheet isn't on screen, so nothing acts on it.
        let showing = (compact && model.atHome) ? nil : state.current
        let todos = showing.map { TodoSort.sorted($0.todos, mode: sort, doneSinks: sinks).filter(\.isFilled) } ?? []

        var out = ScratchpadCommandState()
        out.sheets = state.pads.map { pad in
            let live = pad.id == state.current?.id ? (state.current ?? pad) : pad
            return sheet(live)
        }
        out.current = showing.map(sheet)
        out.todos = todos.map(todo)
        out.todo = typingTodo.flatMap { id in todos.first { $0.id == id } }.map(todo)
        out.blocks = showing?.blocks.filter { $0.kind != .divider }.map(block) ?? []
        out.block = showing.flatMap { pad in state.selectedBlockID.flatMap { id in pad.blocks.first { $0.id == id } } }.map(block)
        if let undo = state.sheetUndo, undo.before.id == showing?.id {
            out.undo = undo.said
        } else if let d = state.deleted, d.sheetID == showing?.id {
            out.undo = "The \(d.block.kind.label.lowercased()) block comes back"
        }
        out.searchText = state.searchText
        out.monitorShows = model.isConnected
        out.storePlace = StoreWords.place(usingICloud: state.usingICloud)
        out.railMode = d.string(forKey: SettingsKey.sidebarMode) ?? SidebarMode.byDay.rawValue
        out.tagSort = d.string(forKey: SettingsKey.tagSort) ?? TagSort.alphabetical.rawValue
        out.wide = !compact
        out.sidebarShowing = (d.string(forKey: SettingsKey.sidebarColumns) ?? SplitColumns.all.rawValue) == SplitColumns.all.rawValue
        out.todoLayout = compact ? .sheet : state.todoLayout
        switch out.todoLayout {
        case .sheet, .slideOver: out.todosShowing = state.showTodoSheet
        case .column: out.todosShowing = !d.bool(forKey: SettingsKey.todoColumnHidden)
        }
        out.todoSort = sort.rawValue
        out.doneSinks = sinks
        out.appearance = d.string(forKey: SettingsKey.appearance) ?? AppearanceMode.system.rawValue
        out.dark = model.colorScheme == .dark
        out.defaultFont = d.string(forKey: SettingsKey.defaultFont) ?? BlockFont.sans.rawValue
        out.animation = d.string(forKey: SettingsKey.whimsy) ?? WhimsyLevel.full.rawValue
        out.newSheetEachDay = d.bool(forKey: SettingsKey.newSheetEachDay)
        out.reduceMotion = UIAccessibility.isReduceMotionEnabled
        out.tags = Tags.counts(state.pads).map(\.tag)
        return out
    }

    private static func sheet(_ pad: Pad) -> ScratchpadCommandState.Sheet {
        let untitled = pad.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return .init(id: pad.id, title: untitled ? (pad.preview ?? pad.displayTitle) : pad.displayTitle, typed: pad.title,
                     detail: pad.date.map(DayLabel.shortDate) ?? "Pinned", tags: pad.tags,
                     contents: [pad.blocks.count == 1 ? "1 block" : "\(pad.blocks.count) blocks",
                                pad.filledCount == 1 ? "1 to-do" : "\(pad.filledCount) to-dos"].joined(separator: " and "))
    }

    private static func todo(_ t: Todo) -> ScratchpadCommandState.Todo {
        .init(id: t.id, text: t.text, status: t.status.rawValue)
    }

    private static func block(_ b: Block) -> ScratchpadCommandState.Block {
        let rows = b.rows ?? []
        return .init(id: b.id, kind: b.kind.rawValue, name: name(b), font: b.font.rawValue, fontSize: b.fontSize,
                     bold: b.bold, italic: b.italic, rotation: b.rotation, rows: rows.count,
                     cols: rows.map(\.count).max() ?? 0, url: b.url, text: b.text, cells: rows, height: b.h,
                     widths: b.kind == .table ? TableLayout.widths(for: b) : [])
    }

    /// "Text “Call Sam”": the kind, and the first words it shows.
    private static func name(_ b: Block) -> String {
        var words: String?
        switch b.kind {
        case .table: words = (b.caption?.isEmpty == false ? b.caption : nil) ?? b.rows?.first?.first { !$0.isEmpty }
        case .link: words = (b.text?.isEmpty == false ? b.text : nil) ?? b.url
        case .file, .image: words = b.name
        default: words = b.text
        }
        let line = words?.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !line.isEmpty else { return "\(b.kind.label) block" }
        return "\(b.kind.label) “\(line.count > 28 ? line.prefix(27) + "…" : line)”"
    }

    // MARK: Previews

    /// Shows a lit choice at once and puts the old one back, without the rest of what choosing does.
    private static func preview(_ command: ScratchpadCommand) {
        let d = UserDefaults.standard
        switch command {
        case .appearance(let a): d.set(a, forKey: SettingsKey.appearance)
        case .font(let id, let f):
            if let font = BlockFont(rawValue: f) { MonitorModel.shared.state?.mutate(id) { $0.font = font } }
        case .fontSize(let id, let n): MonitorModel.shared.state?.mutate(id) { $0.fontSize = n }
        default: host.perform(command)
        }
    }
}

/// The menu's own window: the panel over the dimmed page, unless the monitor has it. Tapping outside closes it.
private struct ScratchpadCommandOverlay: View {
    @Environment(\.palette) private var p
    @ObservedObject private var host = ScratchpadCommandMenu.host

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(host.onMonitor ? 0.001 : 0.18).ignoresSafeArea()
                .onTapGesture { host.close() }
                .accessibilityLabel("Close the menu")
                .accessibilityAddTraits(.isButton)
            if let menu = host.menu {
                if host.onMonitor {
                    if host.byTouch {
                        VStack {
                            Spacer()
                            Text("The menu is on the monitor. Type, or tap here to close it.")
                                .font(Fonts.ui(13)).foregroundStyle(p.muted)
                                .padding(12).background(p.paper, in: RoundedRectangle(cornerRadius: 8))
                                .padding(16)
                        }
                        .allowsHitTesting(false)
                    }
                } else {
                    ScratchpadCommandPanel(menu: menu, touch: host.byTouch, showsKeys: !host.byTouch)
                        .padding(.horizontal, 16).padding(.top, host.byTouch ? 12 : 24)
                }
            }
        }
    }
}

/// The menu itself, the same on the phone and the monitor: `z` scales it, as everything on the monitor.
struct ScratchpadCommandPanel: View {
    @Environment(\.palette) private var p
    let menu: CommandPalette<ScratchpadCommandList>
    var z: CGFloat = 1
    /// Opened by touch: rows take taps, with a way back and a way out.
    var touch = false
    /// The monitor has its hint bar for this.
    var showsKeys = false

    private var rowHeight: CGFloat { 52 * z }
    private var host: CommandHost<ScratchpadCommandList> { ScratchpadCommandMenu.host }

    var body: some View {
        VStack(spacing: 0) {
            field
            hairline
            if menu.rows.isEmpty {
                Text(menu.nothing).font(Fonts.ui(16 * z)).foregroundStyle(p.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18 * z).padding(.vertical, 16 * z)
            } else {
                list
            }
            if showsKeys {
                hairline
                keys
            }
        }
        .frame(maxWidth: 600 * z)
        .background(p.paper, in: RoundedRectangle(cornerRadius: 10 * z, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10 * z, style: .continuous).strokeBorder(p.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 18 * z, y: 6 * z)
    }

    private var hairline: some View { Rectangle().fill(p.hairline).frame(height: 1) }

    private var field: some View {
        HStack(spacing: 10 * z) {
            if touch && menu.depth > 0 {
                Button { host.back() } label: {
                    Image(systemName: "chevron.left").font(Fonts.ui(17 * z, .medium)).foregroundStyle(p.accent)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            } else {
                Image(systemName: menu.isAsking ? "character.cursor.ibeam" : "magnifyingglass")
                    .font(Fonts.ui(15 * z)).foregroundStyle(p.muted)
            }
            if let opener = menu.opener {
                Text(opener.title).font(Fonts.ui(18 * z, .medium)).foregroundStyle(p.accent).lineLimit(1).fixedSize()
            }
            HStack(spacing: 1 * z) {
                if !menu.query.isEmpty {
                    Text(menu.query).font(Fonts.ui(20 * z)).foregroundStyle(p.ink)
                        .lineLimit(1).truncationMode(.head)
                }
                Text("|").font(Fonts.ui(20 * z)).foregroundStyle(p.accent)
                if menu.query.isEmpty {
                    Text(menu.prompt).font(Fonts.ui(20 * z)).foregroundStyle(p.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if touch {
                Button { host.close() } label: {
                    Image(systemName: "xmark").font(Fonts.ui(15 * z, .medium)).foregroundStyle(p.muted)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
        }
        .padding(.horizontal, 18 * z).frame(minHeight: 52 * z)
        .accessibilityElement(children: .contain)
    }

    /// No cap on the rows: ten show, then it scrolls, keeping the lit one in view.
    private var list: some View {
        let headings = menu.sections.filter { $0.title != nil }.count
        let shown = CGFloat(min(menu.rows.count, CommandPaletteLimit.rows)) * rowHeight + CGFloat(headings) * 28 * z
        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(menu.sections) { section in
                        if let title = section.title {
                            Text(title).font(Fonts.ui(12 * z, .semibold)).foregroundStyle(p.muted).lineLimit(1)
                                .padding(.horizontal, 18 * z).padding(.top, 10 * z).padding(.bottom, 4 * z)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(section.rows) { row in
                            Button { host.choose(row.id) } label: {
                                ScratchpadCommandRow(row: row, lit: row.id == menu.selected, z: z).frame(height: rowHeight)
                            }
                            .buttonStyle(.plain)
                            .onHover { inside in if inside { host.highlight(row.id) } }
                            .id(row.id)
                        }
                    }
                }
            }
            .frame(maxHeight: shown)
            .onAppear { if let id = menu.selected { proxy.scrollTo(id) } }
            .onChange(of: menu.selected) { _, id in if let id { proxy.scrollTo(id) } }
        }
    }

    private var keys: some View {
        HStack(spacing: 14 * z) {
            ForEach(menu.hints) { hint in
                HStack(spacing: 4 * z) {
                    Text(hint.key).font(Fonts.mono(11 * z, .medium)).foregroundStyle(p.ink)
                    Text(hint.label).font(Fonts.ui(11 * z)).foregroundStyle(p.muted)
                }
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18 * z).padding(.vertical, 8 * z)
    }
}

private struct ScratchpadCommandRow: View {
    @Environment(\.palette) private var p
    let row: CommandRow<ScratchpadCommand>
    let lit: Bool
    var z: CGFloat = 1

    /// Delete and the like are red, as everywhere.
    private var ink: Color { row.destructive ? p.danger : p.ink }

    var body: some View {
        HStack(spacing: 12 * z) {
            Image(systemName: row.symbol).font(Fonts.ui(16 * z))
                .foregroundStyle(row.destructive ? p.danger : lit ? p.accent : p.muted).frame(width: 22 * z)
            VStack(alignment: .leading, spacing: 1 * z) {
                Text(row.title).font(Fonts.ui(17 * z, .medium)).foregroundStyle(ink).lineLimit(1)
                if let detail = row.detail {
                    Text(detail).font(Fonts.ui(12 * z)).foregroundStyle(p.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 8 * z)
            if let state = row.state {
                Text(state).font(Fonts.ui(13 * z)).foregroundStyle(row.isOn == true ? p.accent : p.muted)
            }
            if row.isCurrent {
                Image(systemName: "checkmark").font(Fonts.ui(14 * z, .semibold)).foregroundStyle(p.accent)
                    .accessibilityLabel("Current")
            }
            if row.leads {
                Image(systemName: "chevron.right").font(Fonts.ui(12 * z)).foregroundStyle(p.muted)
            }
        }
        .padding(.horizontal, 18 * z)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(lit ? p.accent.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(row.state ?? "")
        .accessibilityAddTraits(lit ? .isSelected : [])
    }
}

#endif
