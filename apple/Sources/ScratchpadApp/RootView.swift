import SwiftUI
import UniformTypeIdentifiers
import ScratchpadCore

struct RootView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    @Environment(\.motion) var motion
    @Environment(\.colorScheme) var scheme
    @AppStorage(SettingsKey.appearance) private var appearance: AppearanceMode = .system
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var sizeClass
    #endif
    /// Whether the rail is showing, remembered so a folded rail stays folded.
    @AppStorage(SettingsKey.sidebarColumns) private var storedColumns: SplitColumns = .all
    // What ⌘K can change, beside what's here already.
    @AppStorage(SettingsKey.sidebarMode) private var sidebarMode: SidebarMode = .byDay
    @AppStorage(SettingsKey.tagSort) private var tagSort: TagSort = .alphabetical
    @AppStorage(SettingsKey.todoSort) private var todoSort: TodoSortMode = .manual
    @AppStorage(SettingsKey.doneSinks) private var doneSinks = true
    @AppStorage(SettingsKey.todoColumnHidden) private var todoColumnHidden = false
    @AppStorage(SettingsKey.whimsy) private var whimsy: WhimsyLevel = .full
    @AppStorage(SettingsKey.defaultFont) private var defaultFont: BlockFont = .sans
    @Environment(\.openURL) private var openURL
    @State private var pinnedTitle = ""
    /// The iPhone stack's path: the open sheet is pushed onto it when the window turns compact
    /// (folding an iPhone Duo), so the fold keeps you on the sheet rather than the rail.
    @State private var phonePath: [String] = []

    private var compact: Bool {
        #if os(iOS)
        return sizeClass == .compact
        #else
        return false
        #endif
    }

    var body: some View {
        Group {
            if compact { phone } else { desktop }
        }
        #if os(iOS)
        .onAppear {
            MonitorModel.shared.attach(state)
            ScratchpadCommandMenu.host.perform = runCommand
            ScratchpadCommandMenu.watch(state)
        }
        .onChange(of: compact, initial: true) { _, c in ScratchpadCommandMenu.compact = c }
        .background { MonitorEscape(stepBack: stepBack, deleteBlock: deleteSelectedBlock) }
        .onChange(of: compact && phonePath.isEmpty, initial: true) { _, home in MonitorModel.shared.atHome = home }
        .onChange(of: scheme, initial: true) { _, s in MonitorModel.shared.colorScheme = s }
        .onChange(of: sizeClass) { _, newValue in
            state.flush()
            phonePath = newValue == .compact ? (state.current.map { [$0.id] } ?? []) : []
        }
        .onChange(of: state.createdSheetID) { _, id in
            // A sheet made from the iPhone's rail opens straight away, title focused for typing.
            guard let id else { return }
            state.createdSheetID = nil
            if compact { phonePath = [id] }
        }
        #endif
        .alert(deleteTitle, isPresented: Binding(get: { state.confirmingDelete != nil }, set: { if !$0 { state.confirmingDelete = nil } }),
               presenting: state.confirmingDelete) { pad in
            Button("Delete", role: .destructive) {
                if phonePath.contains(pad.id) { phonePath = [] }
                animate(motion.delete) { state.deleteSheet(pad.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { pad in
            Text(deleteMessage(pad))
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let notice = state.storeNotice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.bar)
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
            Button("OK") { state.error = nil }
        } message: { Text(state.error ?? "") }
        .alert("New pinned sheet", isPresented: $state.askingPinned) {
            TextField("Title", text: $pinnedTitle)
            Button("Create") { state.newPinnedSheet(title: pinnedTitle); pinnedTitle = "" }
            // Esc can land here, so the title stays for next time.
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $state.askingNewOnDate) {
            Themed {
                NewSheetOnDate { day in
                    state.entryDrafts[Caret.newSheetDate] = nil
                    state.askingNewOnDate = false
                    animate(motion.peel) { state.newSheet(on: day) }
                }
                .environmentObject(state)
            }
        }
        .sheet(isPresented: $state.showExport) {
            Themed { ExportView().environmentObject(state) }
        }
        #if os(iOS)
        .sheet(isPresented: $state.showSettings) {
            Themed { NavigationStack { SettingsView(showsDone: true) }.environmentObject(state) }
        }
        #endif
        .fileImporter(isPresented: $state.showImport, allowedContentTypes: [ExportTypes.archive, .json]) { result in
            if case .success(let url) = result { state.importArchive(from: url) }
        }
        .overlay(alignment: .bottom) {
            // Something ⌘K took away: a tag, a to-do, a table's row or column.
            if let undo = state.sheetUndo, undo.before.id == state.current?.id, state.notice == nil {
                HStack(spacing: 10) {
                    Text(undo.done).font(Fonts.ui(13)).foregroundStyle(p.paper)
                        .lineLimit(1)
                    Text("·").foregroundStyle(p.paper.opacity(0.6))
                    Button { animate(motion.fall) { state.undoSheetChange() } } label: {
                        Text("Undo").font(Fonts.ui(13, .semibold)).foregroundStyle(p.paper).underline()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(p.ink, in: Capsule())
                .padding(.bottom, 24)
                .transition(.opacity)
                .id(undo.token)
            }
            if let notice = state.notice {
                Text(notice).font(Fonts.ui(13, .medium)).foregroundStyle(p.paper)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(p.ink, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: notice) {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        animate(motion.toast) { state.notice = nil }
                    }
            }
        }
    }

    private var deleteTitle: String {
        guard let pad = state.confirmingDelete else { return "" }
        return pad.title.trimmingCharacters(in: .whitespaces).isEmpty ? "Delete this sheet?" : "Delete \u{201C}\(pad.displayTitle)\u{201D}?"
    }

    private func deleteMessage(_ pad: Pad) -> String {
        let what = [pad.blocks.count == 1 ? "1 block" : "\(pad.blocks.count) blocks",
                    pad.filledCount == 1 ? "1 to-do" : "\(pad.filledCount) to-dos"].joined(separator: " and ")
        let when = pad.date.map { " from \(DayLabel.longDate($0))" } ?? ""
        return "The sheet\(when) and its \(what) go for good. This can\u{2019}t be undone."
    }

    #if os(iOS)
    /// What each ⌘K row does. Deleting a sheet raises the same alert the menus do; everything else that takes
    /// something away has Undo.
    private func runCommand(_ command: ScratchpadCommand) {
        ScratchpadCommandMenu.ran()
        switch command {
        // Getting around
        case .sheets: showList()
        case .today:
            // Opens today's sheet; makes one only when "New sheet each day" is on (dac1bef).
            guard state.goToToday() else { break }
            if compact, let id = state.current?.id { phonePath = [id] }
        case .settings: state.showSettings = true
        case .open(let id):
            state.open(id)
            if compact { phonePath = [id] }
        case .search(let words):
            state.searchText = words
            showList()
        case .clearSearch: state.searchText = ""
        case .railMode(let m):
            if let mode = SidebarMode(rawValue: m) { sidebarMode = mode }
            showList()
        case .tagSort(let t):
            if let sort = TagSort(rawValue: t) { tagSort = sort }
            sidebarMode = .byTag
            showList()
        case .sidebar(let show): storedColumns = show ? .all : .detailOnly

        // The sheet
        case .newSheet: animate(motion.peel) { state.newSheetToday() }
        case .newOnDate(let day): animate(motion.peel) { state.newSheet(on: day) }
        case .chooseNewDate: state.askingNewOnDate = true
        case .newPinned(let title): animate(motion.peel) { state.newPinnedSheet(title: title) }
        case .duplicate: animate(motion.peel) { state.duplicateCurrent() }
        case .askDelete(let id):
            state.confirmingDelete = state.current?.id == id ? state.current : state.pads.first { $0.id == id }
        case .rename(let title): state.current?.title = title
        case .moveSheet(let day): state.moveCurrent(to: day)
        case .chooseSheetDate: state.openHeaderPopover(.date)
        case .addTag(let tag): state.addTag(tag)
        case .removeTag(let tag): state.removeTagUndoably(tag)
        case .export:
            state.flush()
            state.showExport = true
        case .importArchive: state.showImport = true
        case .copyImage:
            guard let pad = state.current,
                  let png = SheetImage.render(pad, store: state.store, scheme: scheme) else { state.error = "The sheet couldn't be drawn."; return }
            Clipboard.copyImage(png)
            state.notice = "Copied the sheet as an image"
        case .copyTodos:
            guard let pad = state.current else { return }
            Clipboard.copyText(ExportMarkdown.todos([pad]))
            state.notice = "Copied the to-dos as Markdown"
        case .copyEverything:
            state.flush()
            Clipboard.copyText(ExportMarkdown.everything(state.pads))
            state.notice = "Copied \(state.pads.count) sheet\(state.pads.count == 1 ? "" : "s") as Markdown"

        // Blocks
        case .insert(let kind): if let k = BlockKind(rawValue: kind) { insertBlock(k) }
        case .paste:
            let contents = PasteBridge.read()
            animate(motion.fall) { state.paste(contents, font: defaultFont) }
        case .selectBlock(let id): state.selectBlock(id)
        case .deselect: state.selectedBlockID = nil
        case .deleteBlock(let id): animate(motion.delete) { state.deleteBlock(id) }
        case .duplicateBlock(let id): animate(motion.fall) { state.duplicateBlock(id) }
        case .rotate(let id): animate(motion.lift) { state.mutate(id) { $0.rotateStep() } }
        case .unrotate(let id): animate(motion.lift) { state.mutate(id) { $0.rotation = 0 } }
        case .font(let id, let f): if let font = BlockFont(rawValue: f) { state.mutate(id) { $0.font = font } }
        case .fontSize(let id, let n): state.mutate(id) { $0.fontSize = min(Block.fontSizeRange.upperBound, max(Block.fontSizeRange.lowerBound, n)) }
        case .bold(let id, let on): state.mutate(id) { $0.bold = on }
        case .italic(let id, let on): state.mutate(id) { $0.italic = on }
        case .addRow(let id): state.addTableRow(id)
        case .addColumn(let id): state.addTableColumn(id)
        case .removeRow(let id): state.removeTableRow(id)
        case .removeColumn(let id): state.removeTableColumn(id)
        case .openLink(let id):
            if let raw = state.block(id)?.url, let url = URL(string: raw.contains("://") ? raw : "https://" + raw) { openURL(url) }
        case .nudge(let id, let dx, let dy): state.nudgeBlock(id, dx: dx, dy: dy)
        case .widen(let id, let by): state.widenBlock(id, by: by)

        // To-dos
        case .todos(let show):
            switch state.todoLayout {
            case .column where !compact:
                animate(motion.isOff ? nil : .easeInOut(duration: 0.25)) { todoColumnHidden = !show }
            case .slideOver where !compact:
                animate(motion.isOff ? nil : .easeInOut(duration: 0.25)) { state.showTodoSheet = show }
            default:
                if compact, phonePath.isEmpty, let id = state.current?.id { phonePath = [id] }
                state.showTodoSheet = show
            }
        case .addTodo(let text): state.addTodo(text)
        case .status(let id, let s): if let status = TodoStatus(rawValue: s) { state.setTodoStatus(id, status) }
        case .reorderTodo(let id, let move): reorderTodo(id, move)
        case .todoToSheet(let id, let sheetID):
            let name = state.pads.first { $0.id == sheetID }?.displayTitle ?? "the sheet"
            if state.moveTodo(id, toSheet: sheetID) { state.notice = "Moved to \(name)" }
            else if state.error == nil { state.notice = "Couldn’t move it to \(name)" }
        case .deleteTodo(let id): state.deleteTodo(id)
        case .todoSort(let m): if let mode = TodoSortMode(rawValue: m) { todoSort = mode }
        case .doneSinks(let on): doneSinks = on

        // Settings
        case .appearance(let a): if let mode = AppearanceMode(rawValue: a) { appearance = mode }
        case .defaultFont(let f): if let font = BlockFont(rawValue: f) { defaultFont = font }
        case .animation(let w): if let level = WhimsyLevel(rawValue: w) { whimsy = level }
        case .newSheetEachDay(let on):
            UserDefaults.standard.set(on, forKey: SettingsKey.newSheetEachDay)
            state.notice = on ? "A new sheet each day" : "New sheets only when you choose New"
        case .undo:
            if state.sheetUndo != nil { state.undoSheetChange() } else { animate(motion.fall) { state.undoDelete() } }
        }
    }

    /// The sheet list: the phone's first screen, or the iPad's sidebar.
    private func showList() {
        phonePath = []
        if !compact { storedColumns = .all }
    }

    /// Up, down, top or bottom of the list as it's shown. Under a sort other than Manual, the order shown is written
    /// into the sheet first and the sort turns to Manual, as dragging a row does.
    private func reorderTodo(_ id: String, _ move: ScratchpadCommand.TodoMove) {
        guard let pad = state.current else { return }
        let shown = TodoSort.sorted(pad.todos, mode: todoSort, doneSinks: doneSinks)
        if todoSort != .manual || doneSinks {
            state.commitTodoOrder(shown)
            todoSort = .manual
        }
        let ids = shown.map(\.id)
        guard let i = ids.firstIndex(of: id) else { return }
        let before: String?
        switch move {
        case .up: before = i > 0 ? ids[i - 1] : ids.first
        case .down: before = i + 2 < ids.count ? ids[i + 2] : nil
        case .top: before = ids.first
        case .bottom: before = nil
        }
        animate(motion.reorder) { state.moveTodo(id, before: before) }
    }

    /// Esc on a keyboard: one step towards the sheet list. The order is `StepBack`'s.
    private func stepBack() {
        let context = StepBackContext(
            hasFrontmost: state.hasFrontmost, isTyping: MonitorEscape.isTyping,
            hasSelectedBlock: state.selectedBlockID != nil, isCompact: compact,
            isSheetOpen: !phonePath.isEmpty, isSearching: !state.searchText.isEmpty,
            isRailShowing: storedColumns == .all)
        switch StepBack.next(context) {
        case .closeFrontmost: state.closeFrontmost()
        case .endTyping:
            MonitorEscape.endTyping()
            state.caret = nil
        case .letGoOfBlock: state.selectedBlockID = nil
        case .closeSheet: phonePath = []
        case .clearSearch: state.searchText = ""
        case .showRail: storedColumns = .all
        case .none: break
        }
    }

    /// The Delete key with a block selected and nothing being typed in.
    private func deleteSelectedBlock() {
        guard !state.hasFrontmost, let id = state.selectedBlockID else { return }
        animate(motion.delete) { state.deleteBlock(id) }
    }
    #endif

    // MARK: Layouts

    private var columns: Binding<NavigationSplitViewVisibility> {
        Binding(get: { storedColumns.visibility }, set: { storedColumns = SplitColumns($0) })
    }

    private var desktop: some View {
        NavigationSplitView(columnVisibility: columns) {
            RailView()
                #if os(iOS)
                .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 200)
                #else
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
                #endif
        } detail: {
            SheetStage(compact: false)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                PasteButton()
                insertMenu
                Button { state.flush(); state.showExport = true } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .help("Export sheet, to-dos or everything")
                ThemeToggle(appearance: $appearance)
                #if os(iOS)
                Button { state.showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                // ⌘K, for an iPad without a keyboard.
                Button { CommandRoute.presentMenu() } label: { Label("Commands", systemImage: "command") }
                #endif
                NewSheetMenu()
            }
            .plainBackground()
        }
        .tint(p.ink)
        .background(p.desk)
    }

    private var phone: some View {
        NavigationStack(path: $phonePath) {
            RailView()
                .navigationDestination(for: String.self) { id in
                    SheetStage(compact: true)
                        .onAppear { state.open(id) }
                        .toolbar {
                            ToolbarItemGroup(placement: .primaryAction) {
                                Button { state.showTodoSheet = true } label: { Label("To-do", systemImage: "checklist") }
                                // Two menus: what goes on the sheet, and what happens to it.
                                Menu {
                                    PasteButton()
                                    Divider()
                                    insertMenuItems
                                } label: { Label("Insert", systemImage: "plus") }
                                Menu {
                                    // The kit's ⌘K menu is iOS-only; the Mac has ⌘K in the menu bar.
                                    #if os(iOS)
                                    CommandMenuItem()
                                    Divider()
                                    #endif
                                    ForEach(SheetMenus.more, id: \.self) { action in
                                        if action == .delete { Divider() }
                                        sheetAction(action)
                                    }
                                } label: { Label("More", systemImage: "ellipsis") }
                            }
                            .plainBackground()
                        }
                        .tint(p.ink)
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .sheet(isPresented: $state.showTodoSheet) {
                            Themed { TodoColumnView(compact: true).environmentObject(state) }
                                .presentationDetents([.fraction(0.32), .large])
                                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.32)))
                                .presentationDragIndicator(.visible)
                        }
                }
        }
    }

    private var insertMenu: some View {
        Menu { insertMenuItems } label: { Label("Insert", systemImage: "plus.square") }
    }

    @ViewBuilder private var insertMenuItems: some View {
        ForEach(SheetMenus.insert, id: \.self) { k in
            Button { insertBlock(k) } label: { Label(k.label, systemImage: SheetMenus.symbol(k)) }
        }
    }

    @ViewBuilder private func sheetAction(_ action: SheetAction) -> some View {
        switch action {
        case .duplicate:
            Button { animate(motion.peel) { state.duplicateCurrent() } } label: { Label("Duplicate this sheet", systemImage: "plus.square.on.square") }
        case .export:
            Button { state.flush(); state.showExport = true } label: { Label("Export…", systemImage: "square.and.arrow.up") }
        case .delete:
            Button(role: .destructive) { state.confirmingDelete = state.current } label: { Label("Delete this sheet…", systemImage: "trash") }
        }
    }

    private func insertBlock(_ kind: BlockKind) {
        let font = BlockFont(rawValue: UserDefaults.standard.string(forKey: SettingsKey.defaultFont) ?? "") ?? .sans
        animate(motion.fall) { state.insert(kind, font: font) }
    }
}

extension ToolbarContent {
    /// Drops the glass capsule iOS 26 draws behind toolbar buttons, so they sit on the paper as
    /// plain ink icons, like the rest of the app's chrome.
    @ToolbarContentBuilder func plainBackground() -> some ToolbarContent {
        if #available(iOS 26, macOS 26, *) { sharedBackgroundVisibility(.hidden) } else { self }
    }
}

/// `NavigationSplitViewVisibility` as a string `@AppStorage` can hold.
enum SplitColumns: String {
    case automatic, all, doubleColumn, detailOnly

    init(_ visibility: NavigationSplitViewVisibility) {
        if visibility == .all { self = .all }
        else if visibility == .doubleColumn { self = .doubleColumn }
        else if visibility == .detailOnly { self = .detailOnly }
        else { self = .automatic }
    }

    var visibility: NavigationSplitViewVisibility {
        switch self {
        case .automatic: return .automatic
        case .all: return .all
        case .doubleColumn: return .doubleColumn
        case .detailOnly: return .detailOnly
        }
    }
}

/// The detail column: the open sheet, swapped with the peel transition when a new sheet arrives.
struct SheetStage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    @Environment(\.motion) var motion
    let compact: Bool

    var body: some View {
        ZStack {
            p.desk.ignoresSafeArea()
            if let id = state.current?.id {
                PadView(compact: compact)
                    .id(id)
                    .transition(motion.sheetTransition)
            } else {
                Text("No sheet").foregroundStyle(p.muted)
            }
        }
    }
}

/// Split button: click makes a sheet dated today; the menu has the other three actions.
struct NewSheetMenu: View {
    @EnvironmentObject var state: AppState
    @Environment(\.motion) var motion
    /// Duplicate and Delete act on the open sheet, so they are left off the iPhone's rail, where none shows.
    var showsSheetActions = true

    var body: some View {
        Menu {
            Button { newToday() } label: { Label("New sheet today", systemImage: "doc.badge.plus") }
            Button { state.askingNewOnDate = true } label: { Label("New sheet on a date…", systemImage: "calendar.badge.plus") }
            Button { state.askingPinned = true } label: { Label("New pinned sheet", systemImage: "pin") }
            if showsSheetActions {
                Button { animate(motion.peel) { state.duplicateCurrent() } } label: { Label("Duplicate this sheet", systemImage: "plus.square.on.square") }
                    .disabled(state.current == nil)
                Divider()
                Button(role: .destructive) { state.confirmingDelete = state.current } label: { Label("Delete this sheet…", systemImage: "trash") }
                    .disabled(state.current == nil)
            }
        } label: {
            Label("New sheet", systemImage: "plus")
        } primaryAction: {
            newToday()
        }
        .help("New sheet (⌘N)")
    }

    private func newToday() { animate(motion.peel) { state.newSheetToday() } }
}

/// Sun / moon toggle: sun rotates 90 degrees and shrinks out, moon rotates in.
struct ThemeToggle: View {
    @Environment(\.colorScheme) var scheme
    @Environment(\.motion) var motion
    @Binding var appearance: AppearanceMode

    var body: some View {
        Button {
            animate(motion.isOff ? nil : .easeInOut(duration: 0.36)) {
                appearance = scheme == .dark ? .light : .dark
            }
        } label: {
            ZStack {
                Image(systemName: "sun.max")
                    .rotationEffect(.degrees(scheme == .dark ? 90 : 0))
                    .scaleEffect(scheme == .dark ? 0.2 : 1)
                    .opacity(scheme == .dark ? 0 : 1)
                Image(systemName: "moon")
                    .rotationEffect(.degrees(scheme == .dark ? 0 : -90))
                    .scaleEffect(scheme == .dark ? 1 : 0.2)
                    .opacity(scheme == .dark ? 1 : 0)
            }
            .animation(motion.isFull ? .easeInOut(duration: 0.36) : nil, value: scheme)
        }
        .help("Switch light and dark")
        .accessibilityLabel(scheme == .dark ? "Switch to light" : "Switch to dark")
    }
}

/// Reads the system pasteboard into ClipboardContents and drops the result on the current sheet.
struct PasteButton: View {
    @EnvironmentObject var state: AppState
    @Environment(\.motion) var motion
    var body: some View {
        Button {
            let font = BlockFont(rawValue: UserDefaults.standard.string(forKey: SettingsKey.defaultFont) ?? "") ?? .sans
            let contents = PasteBridge.read()
            animate(motion.fall) { state.paste(contents, font: font) }
        } label: { Label("Paste", systemImage: "doc.on.clipboard") }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .help("Paste as a block")
    }
}

/// "New sheet on a date…": the same month grid as the DATE box.
struct NewSheetOnDate: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("New sheet on a date").font(Fonts.ui(15, .semibold))
                Spacer()
                Button("Cancel") { state.entryDrafts[Caret.newSheetDate] = nil; dismiss() }
            }
            DateGridPicker(selected: state.todayKey, marked: state.datesWithSheets, today: state.todayKey, onPick: onPick)
        }
        .padding(20)
        .frame(minWidth: 320)
        .popIn()
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}
