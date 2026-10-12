import SwiftUI
import ScratchpadCore

@main
struct ScratchpadApp: App {
    @StateObject private var state = AppState.live()
    @AppStorage("appearance") private var appearance: AppearanceMode = .system

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
                Button("New pad") { state.openToday() }.keyboardShortcut("n")
            }
            CommandMenu("Insert") {
                ForEach([BlockKind.text, .table, .code, .link, .divider], id: \.self) { kind in
                    Button(kind.rawValue.capitalized) { state.insert(kind) }
                }
            }
            CommandGroup(after: .toolbar) {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }
            }
        }
        Settings {
            Form {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                LabeledContent("Store") { Text(state.store.root.path).font(Fonts.mono(11)).textSelection(.enabled) }
            }.padding().frame(width: 420)
        }
        #endif
    }
}
