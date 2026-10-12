import SwiftUI
import ScratchpadCore

struct RailView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    @State private var newTitle = ""
    @State private var askingNew = false

    private var days: [Pad] { state.pads.filter { !$0.pinned } }
    private var pinned: [Pad] { state.pads.filter { $0.pinned } }

    var body: some View {
        List(selection: Binding(get: { state.current?.id }, set: { if let id = $0 { state.open(id) } })) {
            Section("Days") {
                ForEach(days) { pad in
                    row(pad, label: dayLabel(pad), trailing: shortDate(pad))
                }
            }
            Section("Pinned") {
                ForEach(pinned) { pad in row(pad, label: pad.title.isEmpty ? pad.id : pad.title, trailing: "") }
                Button { askingNew = true } label: { Label("New pinned pad", systemImage: "pin") }.foregroundStyle(p.accent)
            }
            Section {
                HStack { Text("Carried over"); Spacer(); Text("\(state.current?.todos.filter { $0.carriedFrom != nil && $0.status != .done }.count ?? 0)").font(Fonts.mono(11)) }
                    .font(Fonts.ui(12)).foregroundStyle(p.muted)
            }
        }
        .navigationTitle("Scratchpad")
        .scrollContentBackground(.hidden)
        .background(p.chrome)
        .alert("New pinned pad", isPresented: $askingNew) {
            TextField("Title", text: $newTitle)
            Button("Create") { state.newPinnedPad(title: newTitle); newTitle = "" }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func row(_ pad: Pad, label: String, trailing: String) -> some View {
        #if os(iOS)
        NavigationLink(value: pad.id) { rowBody(label: label, trailing: trailing) }.tag(pad.id)
        #else
        rowBody(label: label, trailing: trailing).tag(pad.id)
        #endif
    }

    private func rowBody(label: String, trailing: String) -> some View {
        HStack {
            Text(label).font(Fonts.ui(14, .medium)).foregroundStyle(p.ink)
            Spacer()
            Text(trailing).font(Fonts.mono(11)).foregroundStyle(p.muted)
        }
    }

    private func dayLabel(_ pad: Pad) -> String {
        guard let key = pad.date, let d = DayKey.date(from: key) else { return pad.id }
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide))
    }

    private func shortDate(_ pad: Pad) -> String {
        guard let key = pad.date, let d = DayKey.date(from: key) else { return "" }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }
}
