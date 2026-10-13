import SwiftUI
import ScratchpadCore

@main
struct ScratchpadApp: App {
    @StateObject private var state = AppState.live()
    @AppStorage(SettingsKey.appearance) private var appearance: AppearanceMode = .system
    @AppStorage(SettingsKey.defaultFont) private var defaultFont: BlockFont = .sans

    var body: some Scene {
        WindowGroup {
            Themed { RootView() }
                .environmentObject(state)
                .preferredColorScheme(appearance.colorScheme)
        }
        #if os(macOS)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New sheet") { state.newSheetToday() }.keyboardShortcut("n")
                Button("New sheet on a date…") { state.askingNewOnDate = true }.keyboardShortcut("n", modifiers: [.command, .option])
                Button("New pinned sheet") { state.askingPinned = true }
                Button("Duplicate this sheet") { state.duplicateCurrent() }.keyboardShortcut("d", modifiers: [.command, .shift])
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
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                Picker("Whimsy", selection: $whimsy) {
                    ForEach(WhimsyLevel.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                if reduceMotion {
                    Text("Reduce Motion is on in system settings, so animations are off.").font(Fonts.ui(11)).foregroundStyle(.secondary)
                }
                Picker("Default font", selection: $defaultFont) {
                    ForEach(BlockFont.allCases) { f in Text(f.label).font(Fonts.block(f, size: 13)).tag(f) }
                }
            }
            Section {
                LabeledContent("Store") {
                    Text(state.store.root.path).font(Fonts.mono(11)).textSelection(.enabled).lineLimit(2)
                }
                LabeledContent("Sync") { Text(state.usingICloud ? "iCloud Drive" : "This device") }
            }
        }
        .formStyle(.grouped)
        #if os(iOS)
        .navigationTitle("Settings")
        .toolbar { if showsDone { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }
        #endif
    }
}
