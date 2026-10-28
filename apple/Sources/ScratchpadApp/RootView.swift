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
    @State private var pinnedTitle = ""

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
        .alert("Something went wrong", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
            Button("OK") { state.error = nil }
        } message: { Text(state.error ?? "") }
        .alert("New pinned sheet", isPresented: $state.askingPinned) {
            TextField("Title", text: $pinnedTitle)
            Button("Create") { state.newPinnedSheet(title: pinnedTitle); pinnedTitle = "" }
            Button("Cancel", role: .cancel) { pinnedTitle = "" }
        }
        .sheet(isPresented: $state.askingNewOnDate) {
            Themed {
                NewSheetOnDate { day in
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
                #endif
                NewSheetMenu()
            }
        }
        .background(p.desk)
    }

    private var phone: some View {
        NavigationStack {
            RailView()
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { state.showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                        NewSheetMenu()
                    }
                }
                .navigationDestination(for: String.self) { id in
                    SheetStage(compact: true)
                        .onAppear { state.open(id) }
                        .toolbar {
                            ToolbarItemGroup(placement: .primaryAction) {
                                PasteButton()
                                Button { state.showTodoSheet = true } label: { Label("To-do", systemImage: "checklist") }
                                Menu {
                                    insertMenuItems
                                    Divider()
                                    Button { state.flush(); state.showExport = true } label: { Label("Export…", systemImage: "square.and.arrow.up") }
                                    Button { state.showImport = true } label: { Label("Import archive…", systemImage: "square.and.arrow.down") }
                                } label: { Label("More", systemImage: "ellipsis.circle") }
                            }
                        }
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
        ForEach([BlockKind.text, .table, .code, .link, .divider], id: \.self) { k in
            Button(k.label) { insertBlock(k) }
        }
    }

    private func insertBlock(_ kind: BlockKind) {
        let font = BlockFont(rawValue: UserDefaults.standard.string(forKey: SettingsKey.defaultFont) ?? "") ?? .sans
        animate(motion.fall) { state.insert(kind, font: font) }
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

    var body: some View {
        Menu {
            Button { newToday() } label: { Label("New sheet today", systemImage: "doc.badge.plus") }
            Button { state.askingNewOnDate = true } label: { Label("New sheet on a date…", systemImage: "calendar.badge.plus") }
            Button { state.askingPinned = true } label: { Label("New pinned sheet", systemImage: "pin") }
            Button { animate(motion.peel) { state.duplicateCurrent() } } label: { Label("Duplicate this sheet", systemImage: "plus.square.on.square") }
                .disabled(state.current == nil)
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
                Button("Cancel") { dismiss() }
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
