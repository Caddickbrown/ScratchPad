import SwiftUI
import ScratchpadCore

/// The column at the pad's side: a clear-done square, the title box with a count, then rows of circle + box.
struct TodoColumnView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    let compact: Bool
    @FocusState private var focused: String?

    private var pad: Pad { state.current ?? Pad.daily("") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { state.clearDone() } label: {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(p.muted)
                        .frame(width: 34, height: 34).background(p.chrome).overlay(Rectangle().stroke(p.rule, lineWidth: 1))
                }.buttonStyle(.plain).accessibilityLabel("Clear completed").help("Clear completed")
                HStack {
                    Text("To-do").font(Fonts.ui(14, .medium)).foregroundStyle(p.ink)
                    Spacer()
                    Text("\(pad.doneCount) / \(pad.filledCount)").font(Fonts.mono(12)).foregroundStyle(p.muted)
                }.padding(.horizontal, 12).frame(height: 34).overlay(Rectangle().stroke(p.rule, lineWidth: 1))
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(pad.todos) { todo in
                        TodoRow(todo: todo, compact: compact, focused: $focused)
                    }
                }
            }
            Button {
                state.current?.todos.insert(Todo(), at: 0)
                focused = state.current?.todos.first?.id
            } label: { Label("Add to-do", systemImage: "plus").font(Fonts.ui(13, .medium)) }
                .buttonStyle(.plain).foregroundStyle(p.accent).frame(height: 36)
                .keyboardShortcut("t", modifiers: [.command, .shift])
        }
        .padding(compact ? 16 : 20)
        .background(p.paper)
    }
}

struct TodoRow: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    let todo: Todo
    let compact: Bool
    var focused: FocusState<String?>.Binding

    private var text: Binding<String> {
        Binding(get: { state.current?.todos.first { $0.id == todo.id }?.text ?? "" },
                set: { v in if let i = state.current?.todos.firstIndex(where: { $0.id == todo.id }) { state.current?.todos[i].text = v } })
    }
    private var inkColor: Color {
        if todo.status != .open { return p.rule }
        return todo.isOverdue() ? p.overdue : p.ink
    }

    var body: some View {
        HStack(spacing: 4) {
            Button { state.cycle(todo.id) } label: {
                ZStack {
                    Circle().stroke(todo.status == .done ? p.accent : p.rule, lineWidth: 1.5)
                    if todo.status == .done {
                        Circle().fill(p.accent)
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(p.accentInk)
                    } else if todo.status == .deferred {
                        Path { $0.move(to: CGPoint(x: 16, y: 6)); $0.addLine(to: CGPoint(x: 6, y: 16)) }.stroke(p.rule, lineWidth: 1.5)
                    }
                }
                .frame(width: 22, height: 22)
                .frame(width: compact ? 44 : 36, height: compact ? 44 : 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("To-do status: \(todo.status.rawValue)")
            Rectangle().fill(p.rule).frame(width: 8, height: 1)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(Fonts.ui(compact ? 15 : 13)).foregroundStyle(inkColor)
                .strikethrough(todo.status == .done, color: p.rule)
                .padding(.horizontal, 8)
                .frame(height: compact ? 32 : 28)
                .background(p.cell)
                .overlay(Rectangle().stroke(focused.wrappedValue == todo.id ? p.accent : (todo.text.isEmpty ? p.hairline : p.rule), lineWidth: focused.wrappedValue == todo.id ? 1.5 : 1))
                .focused(focused, equals: todo.id)
                .onSubmit {
                    state.insertTodo(after: todo.id)
                    if let i = state.current?.todos.firstIndex(where: { $0.id == todo.id }) { focused.wrappedValue = state.current?.todos[i + 1].id }
                }
                .onChange(of: text.wrappedValue) { _, v in if v.isEmpty { state.removeTodoIfEmpty(todo.id) } }
        }
        .frame(height: compact ? 44 : 36)
    }
}
