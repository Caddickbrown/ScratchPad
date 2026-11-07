import SwiftUI
import ScratchpadCore

@main
struct ScratchpadApp: App {
    @StateObject private var state = AppState.live()
    @AppStorage(SettingsKey.appearance) private var appearance: AppearanceMode = .system
    @AppStorage(SettingsKey.defaultFont) private var defaultFont: BlockFont = .sans
    @Environment(\.scenePhase) private var scenePhase

    #if os(iOS)
    init() {
        ScratchpadFieldEscape.install()
        ScratchpadCommandMenu.install()
    }
    #endif

    var body: some Scene {
        WindowGroup {
            Themed { RootView() }
                .environmentObject(state)
                .preferredColorScheme(appearance.colorScheme)
                #if os(macOS)
                // scenePhase doesn't change on a Mac when another app comes to the front.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    state.cameToForeground()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    state.flush()
                }
                #endif
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: state.cameToForeground()
            case .inactive, .background: state.flush()
            @unknown default: break
            }
        }
        #if os(macOS)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New sheet") { state.newSheetToday() }.keyboardShortcut("n")
                Button("New sheet on a date…") { state.askingNewOnDate = true }.keyboardShortcut("n", modifiers: [.command, .option])
                Button("New pinned sheet") { state.askingPinned = true }
                Button("Duplicate this sheet") { state.duplicateCurrent() }.keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Delete this sheet…") { state.confirmingDelete = state.current }
                Divider()
                Button("Import archive…") { state.showImport = true }.keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Export…") { state.flush(); state.showExport = true }.keyboardShortcut("e")
            }
            CommandMenu("Insert") {
                ForEach([BlockKind.text, .table, .code, .link, .divider], id: \.self) { kind in
                    Button(kind.label) { state.insert(kind, font: defaultFont) }
                }
            }
            CommandGroup(after: .toolbar) {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }
            }
        }
        #endif
        #if os(macOS)
        Settings {
            Themed { SettingsView(showsDone: false) }
                .environmentObject(state)
                .preferredColorScheme(appearance.colorScheme)
                .frame(width: 440)
        }
        #endif
    }
}

/// Appearance, Whimsy, Default font. macOS Settings scene; a sheet on iOS.
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.appearance) private var appearance: AppearanceMode = .system
    @AppStorage(SettingsKey.whimsy) private var whimsy: WhimsyLevel = .full
    @AppStorage(SettingsKey.defaultFont) private var defaultFont: BlockFont = .sans
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let showsDone: Bool

    var body: some View {
        Form {
            Section("Look") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                Picker("Font for new blocks", selection: $defaultFont) {
                    ForEach(BlockFont.allCases) { f in Text(f.label).font(Fonts.block(f, size: 13)).tag(f) }
                }
            }
            Section {
                Picker("Animation", selection: $whimsy) {
                    ForEach(WhimsyLevel.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
            } header: {
                Text("Motion")
            } footer: {
                Text(reduceMotion ? "Reduce Motion is on in system settings, so animations are off."
                                  : "How much sheets peel and blocks fall into place.")
            }
            Section {
                LabeledContent("Kept on") { Text(StoreWords.place(usingICloud: state.usingICloud)) }
                LabeledContent("Folder") { Text(StoreWords.folder(state.store.root.path)) }
            } header: {
                Text("Your sheets")
            } footer: {
                Text(StoreWords.meaning(usingICloud: state.usingICloud))
            }
            // The Mac has these in its menus. Here Settings is a sheet, and goes first.
            if showsDone {
                Section("Import and export") {
                    Button { leave(then: { state.flush(); state.showExport = true }) } label: {
                        Label("Export…", systemImage: "square.and.arrow.up")
                    }
                    Button { leave(then: { state.showImport = true }) } label: {
                        Label("Import an archive…", systemImage: "square.and.arrow.down")
                    }
                }
            }
        }
        .formStyle(.grouped)
        #if os(iOS)
        .navigationTitle("Settings")
        .toolbar { if showsDone { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }
        #endif
    }

    /// Closes Settings, then opens what's next once it's gone: one sheet can't open over another going away.
    private func leave(then next: @escaping () -> Void) {
        state.showSettings = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: next)
    }
}
