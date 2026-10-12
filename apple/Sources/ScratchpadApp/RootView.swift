import SwiftUI
import ScratchpadCore

struct RootView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var sizeClass
    #endif
    @State private var showRail = true

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
    }

    private var desktop: some View {
        NavigationSplitView(columnVisibility: .constant(showRail ? .all : .detailOnly)) {
            RailView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            if state.current != nil {
                PadView(compact: false)
            } else {
                Text("No pad").foregroundStyle(p.muted)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { showRail.toggle() } label: { Label("Sidebar", systemImage: "sidebar.left") }
                PasteButton()
                Menu { ForEach([BlockKind.text, .table, .code, .link, .divider], id: \.self) { k in Button(k.rawValue.capitalized) { state.insert(k) } } }
                    label: { Label("Insert", systemImage: "plus.square") }
                Button { state.openToday() } label: { Label("New pad", systemImage: "plus") }
            }
        }
        .background(p.desk)
    }

    private var phone: some View {
        NavigationStack {
            RailView()
                .navigationDestination(for: String.self) { id in
                    PadView(compact: true)
                        .onAppear { state.open(id) }
                        .toolbar {
                            ToolbarItemGroup(placement: .topBarTrailing) {
                                PasteButton()
                                Button { state.showTodoSheet = true } label: { Label("To-do", systemImage: "checklist") }
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
}

/// Reads the system pasteboard into ClipboardContents and drops the result on the current pad.
struct PasteButton: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Button { state.paste(PasteBridge.read()) } label: { Label("Paste", systemImage: "doc.on.clipboard") }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .help("Paste as a block")
    }
}
