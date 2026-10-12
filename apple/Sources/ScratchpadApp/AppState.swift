import SwiftUI
import Combine
import ScratchpadCore

@MainActor
final class AppState: ObservableObject {
    @Published var pads: [Pad] = []
    @Published var current: Pad? { didSet { scheduleSave() } }
    @Published var selectedBlockID: String?
    @Published var showTodoSheet = false
    @Published var error: String?

    private(set) var store: PadStore
    @Published var searchText = ""
    @Published var usingICloud = false
    private var saveTask: Task<Void, Never>?
    static let todoRows = 18

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

    var filteredPads: [Pad] { pads.filter { $0.matches(searchText) } }

    func moveTodo(_ id: String, before: String?) { current?.moveTodo(id, before: before) }

    /// Drops a to-do onto the pad as a text block and removes the row.
    func todoToBlock(_ id: String, at point: CGPoint) {
        guard let todo = current?.todos.first(where: { $0.id == id }), !todo.text.isEmpty else { return }
        var b = Block(kind: .text, x: Int(point.x), y: Int(point.y), w: 408, text: todo.text)
        b.snap()
        current?.blocks.append(b)
        current?.todos.removeAll { $0.id == id }
        if let p = current { current = Self.padded(p) }
    }

    func reload() {
        do {
            pads = try store.list()
            if current == nil { openToday() }
        } catch { self.error = "\(error)" }
    }

    func openToday() {
        do {
            var pad = try store.today()
            pad = Self.padded(pad)
            current = pad
            pads = try store.list()
        } catch { self.error = "\(error)" }
    }

    func open(_ id: String) {
        guard current?.id != id else { return }
        flush()
        if let pad = try? store.load(id) { current = Self.padded(pad) }
    }

    func newPinnedPad(title: String) {
        let slug = title.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let id = slug.isEmpty ? "pad-\(UUID().uuidString.prefix(6).lowercased())" : slug
        let pad = Self.padded(Pad(id: id, date: nil, title: title, pinned: true))
        try? store.save(pad)
        reload()
        current = pad
    }

    /// Keeps the column at the paper's 18 rows: empty rows are display rows until typed in.
    static func padded(_ pad: Pad) -> Pad {
        var p = pad
        while p.todos.count < todoRows { p.todos.append(Todo()) }
        return p
    }

    // MARK: Todos

    func cycle(_ id: String) {
        guard let i = current?.todos.firstIndex(where: { $0.id == id }) else { return }
        current?.todos[i].status = current!.todos[i].status.next
    }

    func insertTodo(after id: String) {
        guard let i = current?.todos.firstIndex(where: { $0.id == id }) else { return }
        current?.todos.insert(Todo(), at: i + 1)
    }

    func removeTodoIfEmpty(_ id: String) {
        guard let pad = current, pad.todos.count > Self.todoRows,
              let i = pad.todos.firstIndex(where: { $0.id == id }), pad.todos[i].text.isEmpty else { return }
        current?.todos.remove(at: i)
    }

    func clearDone() {
        current?.todos.removeAll { $0.status == .done }
        if let p = current { current = Self.padded(p) }
    }

    // MARK: Blocks

    func move(_ id: String, to point: CGPoint) {
        guard let i = current?.blocks.firstIndex(where: { $0.id == id }) else { return }
        current?.blocks[i].x = max(0, Block.snapped(Int(point.x)))
        current?.blocks[i].y = max(0, Block.snapped(Int(point.y)))
    }

    func resize(_ id: String, width: CGFloat) {
        guard let i = current?.blocks.firstIndex(where: { $0.id == id }) else { return }
        current?.blocks[i].w = max(2 * gridSize, Block.snapped(Int(width)))
    }

    func update(_ block: Block) {
        guard let i = current?.blocks.firstIndex(where: { $0.id == block.id }) else { return }
        current?.blocks[i] = block
    }

    func deleteBlock(_ id: String) {
        current?.blocks.removeAll { $0.id == id }
        if selectedBlockID == id { selectedBlockID = nil }
    }

    func insert(_ kind: BlockKind, at point: CGPoint? = nil) {
        guard let pad = current else { return }
        let p = point.map { (x: Int($0.x), y: Int($0.y)) } ?? Placement.nextFreePoint(on: pad)
        var b: Block
        switch kind {
        case .table: b = Block(kind: .table, x: p.x, y: p.y, w: 360, rows: [["", ""], ["", ""]])
        case .divider: b = Block(kind: .divider, x: p.x, y: p.y, w: 408)
        case .code: b = Block(kind: .code, x: p.x, y: p.y, w: 408, text: "")
        case .link: b = Block(kind: .link, x: p.x, y: p.y, w: 300, text: "", url: "")
        default: b = Block(kind: .text, x: p.x, y: p.y, w: 408, text: "")
        }
        b.snap()
        current?.blocks.append(b)
        selectedBlockID = b.id
    }

    func paste(_ contents: ClipboardContents, at point: CGPoint? = nil) {
        guard let pad = current else { return }
        var at = point.map { (x: Int($0.x), y: Int($0.y)) } ?? Placement.nextFreePoint(on: pad)
        for result in PasteClassifier.classify(contents) {
            do {
                let b = try Placement.block(from: result, at: at, store: store)
                current?.blocks.append(b)
                selectedBlockID = b.id
                if case .link(let url, nil) = result { titleLater(blockID: b.id, url: url) }
                at.y += (b.h ?? 160) + gridSize
            } catch { self.error = "\(error)" }
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
        guard let pad = current else { return }
        do {
            try store.save(pad)
            if let i = pads.firstIndex(where: { $0.id == pad.id }) { pads[i] = pad } else { pads = (try? store.list()) ?? pads }
        } catch { self.error = "\(error)" }
    }
}
