import SwiftUI
import Combine
import ScratchpadCore

/// A deleted block kept for the 8 s undo toast.
struct DeletedBlock: Equatable {
    var block: Block
    var index: Int
    var sheetID: String
    var token = UUID()
}

@MainActor
final class AppState: ObservableObject {
    @Published var pads: [Pad] = []
    /// The open sheet. Edits save after a short debounce; switching sheets does not touch updatedAt.
    @Published var current: Pad? {
        didSet {
            if let o = oldValue, let n = current, o.id == n.id, o != n { dirty = true; scheduleSave() }
        }
    }
    @Published var selectedBlockID: String?
    @Published var showTodoSheet = false
    @Published var error: String?
    @Published var searchText = ""
    @Published var usingICloud = false

    // Sheets
    @Published var askingNewOnDate = false
    @Published var askingPinned = false
    @Published var showExport = false
    @Published var showImport = false
    @Published var showSettings = false
    @Published var notice: String?
    /// Set when a new sheet should focus its title; the header clears it.
    @Published var focusTitlePending = false

    // Blocks and to-dos
    @Published var deleted: DeletedBlock?
    @Published var justInserted: Set<String> = []
    @Published var blankTodoID = UUID().uuidString
    /// Sheet whose carried rows should hop in once.
    @Published var hopSheetID: String?

    private(set) var store: PadStore
    private var saveTask: Task<Void, Never>?
    private var dirty = false

    init(store: PadStore) {
        self.store = store
        reload()
    }

    /// Starts on the local store, then moves to the iCloud container when one is available.
    static func live() -> AppState {
        let state: AppState
        do { state = AppState(store: try PadStore(root: try PadStore.defaultRoot())) }
        catch { fatalError("Cannot open store: \(error)") }
        Task.detached(priority: .utility) {
            guard let root = PadStore.iCloudRoot(), let cloud = try? PadStore(root: root) else { return }
            await state.switchStore(to: cloud)
        }
        return state
    }

    func switchStore(to newStore: PadStore) {
        flush()
        store = newStore
        usingICloud = true
        current = nil
        reload()
    }

    var todayKey: String { DayKey.key(for: Date()) }
    var filteredPads: [Pad] { pads.filter { $0.matches(searchText) } }
    var datesWithSheets: Set<String> { Sidebar.datesWithSheets(pads) }

    func reload() {
        do {
            pads = try store.list()
            if current == nil { openToday() }
        } catch { self.error = error.localizedDescription }
    }

    private func refreshList() { pads = (try? store.list()) ?? pads }

    // MARK: Sheets

    /// Today on launch: the most recently updated sheet dated today, or a new one with carry-over.
    func openToday() {
        do {
            let hadToday = pads.contains { $0.date == todayKey }
            let pad = try store.today()
            current = pad
            if !hadToday && pad.todos.contains(where: { $0.carriedFrom != nil }) { markHop(pad.id) }
            refreshList()
        } catch { self.error = error.localizedDescription }
    }

    func open(_ id: String) {
        guard current?.id != id else { return }
        flush()
        selectedBlockID = nil
        if let pad = try? store.load(id) { current = pad }
    }

    /// New sheet: dated today, inheriting the current sheet's tags, title focused.
    func newSheetToday() { newSheet(on: todayKey) }

    func newSheet(on day: String) {
        flush()
        do {
            let hadDay = pads.contains { $0.date == day }
            let pad = try store.create(date: day, tags: current?.tags ?? [])
            refreshList()
            selectedBlockID = nil
            current = pad
            if !hadDay && pad.todos.contains(where: { $0.carriedFrom != nil }) { markHop(pad.id) }
            focusTitlePending = true
        } catch { self.error = error.localizedDescription }
    }

    func newPinnedSheet(title: String) {
        flush()
        do {
            let pad = try store.createPinned(title: title, tags: current?.tags ?? [])
            refreshList()
            selectedBlockID = nil
            current = pad
        } catch { self.error = error.localizedDescription }
    }

    func duplicateCurrent() {
        guard let pad = current else { return }
        flush()
        do {
            let copy = try store.duplicate(pad)
            refreshList()
            selectedBlockID = nil
            current = copy
            focusTitlePending = true
        } catch { self.error = error.localizedDescription }
    }

    /// Choosing a date moves the sheet; a pinned sheet given a date is unpinned.
    func moveCurrent(to day: String) {
        guard let pad = current, pad.date != day else { return }
        saveTask?.cancel()
        do {
            let moved = try store.move(pad, to: day)
            dirty = false
            refreshList()
            current = moved
        } catch { self.error = error.localizedDescription }
    }

    private func markHop(_ id: String) {
        hopSheetID = id
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self?.hopSheetID == id { self?.hopSheetID = nil }
        }
    }

    // MARK: Tags

    func addTag(_ raw: String) {
        let t = Tags.normalize(raw)
        guard !t.isEmpty, current?.tags.contains(t) == false else { return }
        current?.tags.append(t)
    }

    func removeTag(_ t: String) { current?.tags.removeAll { $0 == t } }

    func tagSuggestions(_ prefix: String) -> [(tag: String, count: Int)] {
        Tags.suggestions(prefix: prefix, pads: pads, excluding: current?.tags ?? [])
    }

    // MARK: To-dos

    /// Text for a row; the blank row (not yet in the sheet) becomes a real row on the first keystroke.
    func setTodoText(_ id: String, _ text: String) {
        if let i = current?.todos.firstIndex(where: { $0.id == id }) {
            current?.todos[i].text = text
        } else if id == blankTodoID, !text.isEmpty {
            current?.todos.append(Todo(id: id, text: text))
            blankTodoID = UUID().uuidString
        }
    }

    func cycle(_ id: String) {
        guard let i = current?.todos.firstIndex(where: { $0.id == id }) else { return }
        current?.todos[i].status = current!.todos[i].status.next
    }

    /// Empty rows go when they lose focus, so the column keeps exactly one blank row.
    func dropTodoIfEmpty(_ id: String) {
        guard let i = current?.todos.firstIndex(where: { $0.id == id }), current?.todos[i].text.isEmpty == true else { return }
        current?.todos.remove(at: i)
    }

    func moveTodo(_ id: String, before: String?) {
        current?.moveTodo(id, before: before == blankTodoID ? nil : before)
    }

    /// Writes the current view order into the file (used before a drag under a non-manual sort).
    func commitTodoOrder(_ ordered: [Todo]) {
        guard var pad = current else { return }
        let ids = ordered.map(\.id)
        let rest = pad.todos.filter { !ids.contains($0.id) }
        pad.todos = ordered.filter { t in pad.todos.contains { $0.id == t.id } } + rest
        current = pad
    }

    /// Drops a to-do onto the canvas as a text block and removes the row.
    func todoToBlock(_ id: String, at point: CGPoint, font: BlockFont = .sans) {
        guard let todo = current?.todos.first(where: { $0.id == id }), todo.isFilled else { return }
        var b = Block(kind: .text, x: Int(point.x), y: Int(point.y), w: 408, text: todo.text, font: font)
        b.snap()
        current?.blocks.append(b)
        current?.todos.removeAll { $0.id == id }
        noteInserted(b.id)
    }

    /// Drop on a sheet row in the sidebar: the to-do moves to that sheet.
    func moveTodo(_ id: String, toSheet sheetID: String) {
        guard var pad = current, sheetID != pad.id, let todo = pad.todos.first(where: { $0.id == id }),
              var target = try? store.load(sheetID) else { return }
        target.todos.append(todo)
        pad.todos.removeAll { $0.id == id }
        do {
            try store.save(target)
            current = pad
            flush()
            refreshList()
        } catch { self.error = error.localizedDescription }
    }

    // MARK: Blocks

    func block(_ id: String) -> Block? { current?.blocks.first { $0.id == id } }

    func update(_ block: Block) {
        guard let i = current?.blocks.firstIndex(where: { $0.id == block.id }) else { return }
        current?.blocks[i] = block
    }

    func mutate(_ id: String, _ change: (inout Block) -> Void) {
        guard let i = current?.blocks.firstIndex(where: { $0.id == id }) else { return }
        change(&current!.blocks[i])
    }

    /// Move on release: snaps to the 24 px grid unless `snap` is false (Alt held).
    func moveBlock(_ id: String, x: CGFloat, y: CGFloat, snap: Bool) {
        mutate(id) { b in
            b.x = max(0, snap ? Block.snapped(Int(x)) : Int(x.rounded()))
            b.y = max(0, snap ? Block.snapped(Int(y)) : Int(y.rounded()))
        }
    }

    func deleteBlock(_ id: String) {
        guard let pad = current, let i = pad.blocks.firstIndex(where: { $0.id == id }) else { return }
        deleted = DeletedBlock(block: pad.blocks[i], index: i, sheetID: pad.id)
        current?.blocks.remove(at: i)
        if selectedBlockID == id { selectedBlockID = nil }
        let token = deleted?.token
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if self?.deleted?.token == token { self?.deleted = nil }
        }
    }

    /// Undo restores the block at the same index.
    func undoDelete() {
        guard let d = deleted, current?.id == d.sheetID else { deleted = nil; return }
        let i = min(d.index, current?.blocks.count ?? 0)
        current?.blocks.insert(d.block, at: i)
        selectedBlockID = d.block.id
        deleted = nil
    }

    func duplicateBlock(_ id: String) {
        guard let b = block(id), let i = current?.blocks.firstIndex(where: { $0.id == id }) else { return }
        let copy = b.duplicated()
        current?.blocks.insert(copy, at: i + 1)
        selectedBlockID = copy.id
        noteInserted(copy.id)
    }

    func insert(_ kind: BlockKind, at point: CGPoint? = nil, font: BlockFont = .sans) {
        guard let pad = current else { return }
        let p = point.map { (x: Int($0.x), y: Int($0.y)) } ?? Placement.nextFreePoint(on: pad)
        var b: Block
        switch kind {
        case .table: b = Block(kind: .table, x: p.x, y: p.y, w: 240, rows: [["", ""], ["", ""]], colWidths: [120, 120])
        case .divider: b = Block(kind: .divider, x: p.x, y: p.y, w: 408)
        case .code: b = Block(kind: .code, x: p.x, y: p.y, w: 408, text: "", font: .mono)
        case .link: b = Block(kind: .link, x: p.x, y: p.y, w: 300, text: "", url: "")
        default: b = Block(kind: .text, x: p.x, y: p.y, w: 408, text: "", font: font)
        }
        b.snap()
        current?.blocks.append(b)
        selectedBlockID = b.id
        noteInserted(b.id)
    }

    func paste(_ contents: ClipboardContents, at point: CGPoint? = nil, font: BlockFont = .sans) {
        guard let pad = current else { return }
        var at = point.map { (x: Int($0.x), y: Int($0.y)) } ?? Placement.nextFreePoint(on: pad)
        for result in PasteClassifier.classify(contents) {
            do {
                var b = try Placement.block(from: result, at: at, store: store)
                if b.kind == .text { b.font = font }
                if b.kind == .table, let cols = b.rows?.first?.count, cols > 0 {
                    b.colWidths = Array(repeating: max(TableLayout.minColumn, b.w / cols), count: cols)
                }
                current?.blocks.append(b)
                selectedBlockID = b.id
                noteInserted(b.id)
                if case .link(let url, nil) = result { titleLater(blockID: b.id, url: url) }
                at.y += (b.h ?? 160) + gridSize
            } catch { self.error = error.localizedDescription }
        }
    }

    private func noteInserted(_ id: String) {
        justInserted.insert(id)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            self?.justInserted.remove(id)
        }
    }

    /// Fills a link card's title once the page answers, unless the user has already retyped it.
    private func titleLater(blockID: String, url: String) {
        Task {
            guard let title = await LinkTitle.fetch(url),
                  let i = current?.blocks.firstIndex(where: { $0.id == blockID }), current?.blocks[i].text == url else { return }
            current?.blocks[i].text = title
        }
    }

    // MARK: Import

    func importArchive(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            flush()
            let archive = try ScratchpadArchive.decode(Data(contentsOf: url))
            let result = try archive.importInto(store)
            refreshList()
            if let id = current?.id, let fresh = try store.load(id) { current = fresh }
            notice = "Imported \(result.sheets) sheet\(result.sheets == 1 ? "" : "s")" + (result.assetsWritten > 0 ? " and \(result.assetsWritten) file\(result.assetsWritten == 1 ? "" : "s")" : "")
        } catch { self.error = error.localizedDescription }
    }

    // MARK: Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        saveTask?.cancel()
        guard dirty, let pad = current else { return }
        dirty = false
        do {
            let saved = try store.save(pad)
            if let i = pads.firstIndex(where: { $0.id == saved.id }) { pads[i] = saved } else { refreshList() }
        } catch { self.error = error.localizedDescription }
    }
}
