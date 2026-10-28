import SwiftUI
import ScratchpadCore

/// Sidebar: By day / By tag, tag sort, pinned section at the bottom. A to-do dropped on a row moves to that sheet.
struct RailView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    @AppStorage(SettingsKey.sidebarMode) private var mode: SidebarMode = .byDay
    @AppStorage(SettingsKey.tagSort) private var tagSort: TagSort = .alphabetical
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var visible: [Pad] { state.filteredPads }
    private var groups: [SheetGroup] {
        mode == .byDay ? Sidebar.byDay(visible, today: state.todayKey) : Sidebar.byTag(visible, sort: tagSort)
    }
    private var pinned: [Pad] { Sidebar.pinned(visible) }
    /// Rows on screen, tracked without redrawing, for the rail's scroll (see `rowAppeared`).
    @State private var onScreen = RowsOnScreen()
    @State private var restored = false

    /// Every row's id, top to bottom.
    private var rowIDs: [String] {
        groups.flatMap { g in g.sheets.map { Self.rowID($0, groupID: g.id) } } + pinned.map { Self.rowID($0, groupID: "pinned") }
    }

    private static func rowID(_ pad: Pad, groupID: String) -> String { "\(groupID)/\(pad.id)" }

    var body: some View {
        ScrollViewReader { proxy in
            list
                .onAppear {
                    // A fold rebuilds the rail at the top; scroll it back to the row that was at the top.
                    guard !restored else { return }
                    let top = state.railTopRow
                    Task { @MainActor in
                        if let top {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            proxy.scrollTo(top, anchor: .top)
                        }
                        restored = true
                    }
                }
        }
    }

    /// The rail's scroll is kept as the top visible row in `AppState.railTopRow` (List has no
    /// `scrollPosition(id:)`). Only appearances update it: a fold tearing the rail down makes every
    /// row disappear, and that must not move the kept row.
    private func rowAppeared(_ id: String) {
        onScreen.ids.insert(id)
        guard restored, let top = rowIDs.first(where: onScreen.ids.contains) else { return }
        state.railTopRow = top
    }

    /// The open sheet as the list's selection, for the sidebar beside it. On a phone the rail is
    /// the root of a navigation stack: a selectable list there takes a tap as selecting the row
    /// and never follows its link, so no sheet would open.
    private var selection: Binding<String?>? {
        #if os(iOS)
        if sizeClass == .compact { return nil }
        #endif
        return Binding(get: { state.current?.id }, set: { if let id = $0 { state.open(id) } })
    }

    private var list: some View {
        List(selection: selection) {
            ForEach(groups) { group in
                Section {
                    ForEach(group.sheets) { pad in row(pad, groupID: group.id) }
                } header: {
                    HStack {
                        Text(group.label)
                        Spacer()
                        Text(group.detail).font(Fonts.mono(10)).foregroundStyle(p.muted)
                    }
                }
            }
            Section("Pinned") {
                ForEach(pinned) { pad in row(pad, groupID: "pinned") }
                Button { state.askingPinned = true } label: { Label("New pinned sheet", systemImage: "pin") }
                    .buttonStyle(.plain)
                    .foregroundStyle(p.accent)
            }
            Section {
                HStack { Text("Carried over"); Spacer(); Text("\(state.current?.todos.filter { $0.carriedFrom != nil && $0.status != .done && $0.isFilled }.count ?? 0)").font(Fonts.mono(11)) }
                    .font(Fonts.ui(12)).foregroundStyle(p.muted)
                HStack { Text("Store"); Spacer(); Text(state.usingICloud ? "iCloud" : "local").font(Fonts.mono(11)) }
                    .font(Fonts.ui(12)).foregroundStyle(p.muted)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { controls }
        .navigationTitle("Scratchpad")
        .searchable(text: $state.searchText, prompt: "Search sheets, blocks and to-dos")
        .scrollContentBackground(.hidden)
        .background(p.chrome)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Picker("Group", selection: $mode) {
                ForEach(SidebarMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if mode == .byTag {
                Menu {
                    Picker("Sort tags", selection: $tagSort) {
                        ForEach(TagSort.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .fixedSize()
                .accessibilityLabel("Sort tags")
                .help("Sort tags: \(tagSort.label)")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(p.chrome)
    }

    @ViewBuilder
    private func row(_ pad: Pad, groupID: String) -> some View {
        #if os(iOS)
        NavigationLink(value: pad.id) { SheetRow(pad: pad) }.tag(pad.id)
            .id(Self.rowID(pad, groupID: groupID))
            .onAppear { rowAppeared(Self.rowID(pad, groupID: groupID)) }
            .onDisappear { onScreen.ids.remove(Self.rowID(pad, groupID: groupID)) }
        #else
        SheetRow(pad: pad).tag(pad.id)
            .id(Self.rowID(pad, groupID: groupID))
            .onAppear { rowAppeared(Self.rowID(pad, groupID: groupID)) }
            .onDisappear { onScreen.ids.remove(Self.rowID(pad, groupID: groupID)) }
        #endif
    }
}

/// A plain box, so recording which rows are on screen does not redraw the rail.
final class RowsOnScreen {
    var ids: Set<String> = []
}

struct SheetRow: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    let pad: Pad
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 6) {
            Text(pad.displayTitle)
                .font(Fonts.ui(13, .medium))
                .foregroundStyle(pad.title.isEmpty ? p.muted : p.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let tag = pad.tags.first {
                Text("#\(tag)").font(Fonts.mono(10)).foregroundStyle(p.muted).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .overlay { if targeted { RoundedRectangle(cornerRadius: 4).stroke(p.accent, lineWidth: 1.5).padding(-3) } }
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.compactMap(TodoDrag.id).first else { return false }
            state.moveTodo(id, toSheet: pad.id)
            return true
        } isTargeted: { targeted = $0 }
        .contextMenu {
            Button("Open") { state.open(pad.id) }
        }
    }
}
