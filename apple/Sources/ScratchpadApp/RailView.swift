import SwiftUI
import ScratchpadCore

/// Sidebar: By day / By tag, tag sort, pinned section at the bottom. A to-do dropped on a row moves to that sheet.
struct RailView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    @AppStorage(SettingsKey.sidebarMode) private var mode: SidebarMode = .byDay
    @AppStorage(SettingsKey.tagSort) private var tagSort: TagSort = .alphabetical

    private var visible: [Pad] { state.filteredPads }
    private var groups: [SheetGroup] {
        mode == .byDay ? Sidebar.byDay(visible, today: state.todayKey) : Sidebar.byTag(visible, sort: tagSort)
    }
    private var pinned: [Pad] { Sidebar.pinned(visible) }

    var body: some View {
        List(selection: Binding(get: { state.current?.id }, set: { if let id = $0 { state.open(id) } })) {
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
        #else
        SheetRow(pad: pad).tag(pad.id)
        #endif
    }
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
