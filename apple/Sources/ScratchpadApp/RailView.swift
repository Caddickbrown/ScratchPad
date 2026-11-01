import SwiftUI
import ScratchpadCore

/// Sidebar: By day / By month / Recent / By tag, tag sort, pinned section at the bottom. A to-do dropped
/// on a row moves to that sheet. On an iPhone it is the whole first screen, with its own header in
/// place of the navigation bar.
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
        switch mode {
        case .byDay: return Sidebar.byDay(visible, today: state.todayKey)
        case .byMonth: return Sidebar.byMonth(visible)
        case .recent: return Sidebar.recent(visible)
        case .byTag: return Sidebar.byTag(visible, sort: tagSort)
        }
    }
    /// Rows carry their own date where the group header does not give it.
    private var rowsShowDate: Bool { mode != .byDay }

    private var compact: Bool {
        #if os(iOS)
        return sizeClass == .compact
        #else
        return false
        #endif
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
            Section {
                ForEach(pinned) { pad in row(pad, groupID: "pinned") }
                Button { state.askingPinned = true } label: { Label("New pinned sheet", systemImage: "pin") }
                    .buttonStyle(.plain)
                    .foregroundStyle(p.accent)
            } header: {
                Text("Pinned")
            }
            Section {
                HStack { Text("Carried over"); Spacer(); Text("\(state.current?.todos.filter { $0.carriedFrom != nil && $0.status != .done && $0.isFilled }.count ?? 0)").font(Fonts.mono(11)) }
                    .font(Fonts.ui(12)).foregroundStyle(p.muted)
                HStack { Text("Store"); Spacer(); Text(state.usingICloud ? "iCloud" : "local").font(Fonts.mono(11)) }
                    .font(Fonts.ui(12)).foregroundStyle(p.muted)
            }
        }
        .navigationTitle("Scratchpad")
        .modifier(RailChrome(compact: compact, search: $state.searchText) { compact ? AnyView(phoneHeader) : AnyView(controls) })
        .scrollContentBackground(.hidden)
        .background(p.chrome)
    }

    /// The iPhone's header: title and buttons, search, grouping. Drawn here rather than by the
    /// navigation bar, so it sits at the top of the screen without the bar's empty large-title band.
    private var phoneHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                Text("Scratchpad").font(Fonts.ui(26, .bold)).foregroundStyle(p.ink)
                Spacer()
                Button { state.showSettings = true } label: {
                    Image(systemName: "gearshape").font(.system(size: 19, weight: .regular))
                }
                .accessibilityLabel("Settings")
                NewSheetMenu(showsSheetActions: false)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 21, weight: .regular))
                    .menuStyle(.button)
            }
            .buttonStyle(.plain)
            .foregroundStyle(p.ink)
            SearchField(text: $state.searchText)
            controlsRow.padding(.bottom, 8)
        }
        .padding(.horizontal, 16).padding(.top, 8)
        .background(p.chrome)
    }

    private var controls: some View {
        controlsRow
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(p.chrome)
    }

    private var controlsRow: some View {
        HStack(spacing: 8) {
            ModePicker(mode: $mode)
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
    }

    @ViewBuilder
    private func row(_ pad: Pad, groupID: String) -> some View {
        #if os(iOS)
        NavigationLink(value: pad.id) { SheetRow(pad: pad, showsDate: rowsShowDate) }.tag(pad.id)
            .swipeActions(edge: .trailing) {
                Button { state.confirmingDelete = pad } label: { Label("Delete", systemImage: "trash") }
                    .tint(p.overdue)
            }
            .id(Self.rowID(pad, groupID: groupID))
            .onAppear { rowAppeared(Self.rowID(pad, groupID: groupID)) }
            .onDisappear { onScreen.ids.remove(Self.rowID(pad, groupID: groupID)) }
        #else
        SheetRow(pad: pad, showsDate: rowsShowDate).tag(pad.id)
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
    var showsDate = false
    @State private var targeted = false

    private var untitled: Bool { pad.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: 6) {
            // An untitled sheet shows its first line of text instead of "Untitled sheet".
            Text(untitled ? (pad.preview ?? pad.displayTitle) : pad.displayTitle)
                .font(Fonts.ui(13, untitled ? .regular : .medium))
                .foregroundStyle(untitled ? p.muted : p.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let tag = pad.tags.first {
                Text("#\(tag)").font(Fonts.mono(10)).foregroundStyle(p.muted).lineLimit(1)
            }
            if showsDate, let date = pad.date {
                Text(DayLabel.shortDate(date)).font(Fonts.mono(10)).foregroundStyle(p.muted).lineLimit(1)
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
            Divider()
            Button(role: .destructive) { state.confirmingDelete = pad } label: { Label("Delete sheet…", systemImage: "trash") }
        }
    }
}

/// The phone's header replaces the navigation bar and brings its own search field; the sidebar
/// beside a sheet keeps the system search and the grouping above its list.
private struct RailChrome<Header: View>: ViewModifier {
    let compact: Bool
    @Binding var search: String
    @ViewBuilder let header: () -> Header

    func body(content: Content) -> some View {
        if compact {
            content
                .safeAreaInset(edge: .top, spacing: 0) { header() }
                #if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
                #endif
        } else {
            content
                .safeAreaInset(edge: .top, spacing: 0) { header() }
                .searchable(text: $search, prompt: "Search sheets, blocks and to-dos")
        }
    }
}

/// Grouping as a row of paper tabs, in place of the system's segmented control.
struct ModePicker: View {
    @Environment(\.palette) var p
    @Binding var mode: SidebarMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SidebarMode.allCases) { m in
                Button { mode = m } label: {
                    Text(m.label)
                        .font(Fonts.ui(12, m == mode ? .semibold : .regular))
                        .foregroundStyle(m == mode ? p.ink : p.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            if m == mode {
                                RoundedRectangle(cornerRadius: 6).fill(p.paper)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(p.hairline, lineWidth: 1))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(m == mode ? .isSelected : [])
            }
        }
        .padding(2)
        .background(p.desk, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A plain search box drawn in the app's own paper and rule.
struct SearchField: View {
    @Environment(\.palette) var p
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium)).foregroundStyle(p.muted)
            TextField("Search sheets, blocks and to-dos", text: $text)
                .textFieldStyle(.plain)
                .font(Fonts.ui(14))
                .foregroundStyle(p.ink)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(p.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(p.paper, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.hairline, lineWidth: 1))
    }
}
