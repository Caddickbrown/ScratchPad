import SwiftUI
import ScratchpadCore

/// The paper: header strip, dot-grid canvas, and (when wide) the to-do column at its side.
/// When the sheet is too narrow for both (an open iPhone Duo, a half-screen iPad), the column
/// slides over the canvas from the trailing edge instead, toggled from the toolbar.
struct PadView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    @Environment(\.motion) var motion
    let compact: Bool
    /// The sheet's own width, so the decision follows the window, never the device.
    @State private var width: CGFloat = 0

    /// Below this the canvas would be squeezed under ~400 pt beside the 340 pt column.
    private static let sideBySideWidth: CGFloat = 760

    private var slidesTodos: Bool {
        #if os(iOS)
        return !compact && width > 0 && width < Self.sideBySideWidth
        #else
        return false
        #endif
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                PadHeader(compact: compact)
                CanvasView()
            }
            .padding(compact ? 12 : 20)
            if !compact && !slidesTodos {
                Rectangle().fill(p.hairline).frame(width: 1)
                TodoColumnView(compact: false).frame(width: 340)
            }
        }
        .overlay(alignment: .trailing) {
            // The same flag as the iPhone's to-do sheet, so the open column follows a fold.
            if slidesTodos && state.showTodoSheet {
                HStack(spacing: 0) {
                    Rectangle().fill(p.hairline).frame(width: 1)
                    TodoColumnView(compact: false).frame(width: max(240, min(340, width - 60)))
                }
                .shadow(color: .black.opacity(0.12), radius: 12, x: -2)
                .transition(.move(edge: .trailing))
            }
        }
        .background(p.paper)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 0 : 8))
        .overlay(RoundedRectangle(cornerRadius: compact ? 0 : 8).stroke(p.hairline, lineWidth: compact ? 0 : 1))
        .shadow(color: .black.opacity(compact ? 0 : 0.06), radius: 10, y: 2)
        .padding(compact ? 0 : 20)
        .background(p.desk)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { width = g.size.width }
                .onChange(of: g.size.width) { _, w in width = w }
        })
        .toolbar {
            if slidesTodos {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        animate(motion.isOff ? nil : .easeInOut(duration: 0.25)) { state.showTodoSheet.toggle() }
                    } label: { Label("To-do", systemImage: "checklist") }
                    .help("Show or hide the to-do column")
                }
            }
        }
        .navigationTitle(compact ? compactTitle : "")
    }

    private var compactTitle: String {
        guard let pad = state.current else { return "" }
        guard let key = pad.date else { return pad.displayTitle }
        return DayLabel.group(key, today: state.todayKey)
    }
}

/// DATE box (opens the month grid), title, and tag chips.
struct PadHeader: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    @Environment(\.motion) var motion
    let compact: Bool
    @State private var pickingDate = false
    @FocusState private var titleFocused: Bool
    @State private var sheetID: String?

    private var title: Binding<String> {
        Binding(get: { state.current?.title ?? "" }, set: { state.current?.title = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                dateBox
                Rectangle().fill(p.rule).frame(width: 1)
                TextField("Untitled sheet", text: title)
                    .textFieldStyle(.plain)
                    .font(Fonts.ui(compact ? 15 : 14, .medium)).foregroundStyle(p.ink)
                    .focused($titleFocused)
                    .padding(.horizontal, 12)
                if !compact {
                    Rectangle().fill(p.rule).frame(width: 1)
                    TagChips().padding(.horizontal, 8).frame(minWidth: 160, maxWidth: 320, alignment: .leading)
                }
            }
            .frame(height: compact ? 36 : 34)
            .overlay(Rectangle().stroke(p.rule, lineWidth: 1))
            if compact { TagChips() }
        }
        .onAppear {
            sheetID = state.current?.id
            if state.focusTitlePending { focusTitleSoon() }
        }
        .onChange(of: state.focusTitlePending) { _, pending in
            if pending && sheetID == state.current?.id { focusTitleSoon() }
        }
    }

    private func focusTitleSoon() {
        state.focusTitlePending = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: motion.isOff ? 50_000_000 : 600_000_000)
            titleFocused = true
        }
    }

    private var dateBox: some View {
        Button { pickingDate = true } label: {
            HStack(spacing: 10) {
                Text("DATE").font(Fonts.ui(10, .semibold)).tracking(1).foregroundStyle(p.muted)
                Text(dateText).font(Fonts.mono(13)).foregroundStyle(p.ink).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(p.muted)
            }
            .padding(.horizontal, 12)
            .frame(width: compact ? 150 : 220, alignment: .leading)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Date: \(dateText). Choose a date")
        .popover(isPresented: $pickingDate, arrowEdge: .bottom) {
            Themed {
                DateGridPicker(selected: state.current?.date, marked: state.datesWithSheets, today: state.todayKey) { day in
                    pickingDate = false
                    state.moveCurrent(to: day)
                }
                .padding(16)
                .frame(width: 300)
                .popIn()
                .presentationCompactAdaptation(.popover)
            }
        }
    }

    private var dateText: String {
        guard let key = state.current?.date else { return "Pinned" }
        return compact ? DayLabel.shortDate(key) : DayLabel.longDate(key)
    }
}

/// Month grid, Monday first, today ringed, a dot under days that already have sheets, plus typed input.
struct DateGridPicker: View {
    @Environment(\.palette) var p
    let selected: String?
    let marked: Set<String>
    let today: String
    let onPick: (String) -> Void
    @State private var year = 2026
    @State private var month = 1
    @State private var typed = ""
    @State private var typedInvalid = false

    private static let weekdayInitials = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Type a date: tomorrow, fri, 15 oct, +3", text: $typed)
                .textFieldStyle(.roundedBorder)
                .font(Fonts.ui(13))
                .onSubmit(submitTyped)
                .onChange(of: typed) { _, _ in typedInvalid = false }
            if typedInvalid {
                Text("Try today, tomorrow, fri, 15 oct, 15/10, 2026-10-15, +3 or -2.").font(Fonts.ui(11)).foregroundStyle(p.overdue)
            } else if let preview = DatePhrase.parse(typed, today: today) {
                Text(DayLabel.longDate(preview)).font(Fonts.mono(11)).foregroundStyle(p.muted)
            }
            HStack {
                Text(DayLabel.monthTitle(year: year, month: month)).font(Fonts.ui(14, .semibold)).foregroundStyle(p.ink)
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).accessibilityLabel("Previous month")
                Button { jumpToToday() } label: { Text("Today").font(Fonts.ui(12)) }.buttonStyle(.plain).foregroundStyle(p.accent)
                Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain).accessibilityLabel("Next month")
            }
            .foregroundStyle(p.ink)
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    ForEach(0..<7, id: \.self) { i in
                        Text(Self.weekdayInitials[i]).font(Fonts.ui(11, .semibold)).foregroundStyle(p.muted).frame(width: 36, height: 20)
                    }
                }
                ForEach(Array(MonthGrid.weeks(year: year, month: month).enumerated()), id: \.offset) { _, week in
                    GridRow {
                        ForEach(0..<7, id: \.self) { i in dayCell(week[i]) }
                    }
                }
            }
        }
        .onAppear(perform: jumpToSelection)
    }

    @ViewBuilder
    private func dayCell(_ key: String?) -> some View {
        if let key, let parts = DayMath.parts(key) {
            Button { onPick(key) } label: {
                VStack(spacing: 2) {
                    Text("\(parts.day)").font(Fonts.ui(13, key == selected ? .semibold : .regular))
                        .foregroundStyle(key == selected ? p.accentInk : p.ink)
                        .frame(width: 30, height: 26)
                        .background { if key == selected { RoundedRectangle(cornerRadius: 6).fill(p.accent) } }
                        .overlay { if key == today && key != selected { RoundedRectangle(cornerRadius: 6).stroke(p.accent, lineWidth: 1.5) } }
                    Circle().fill(marked.contains(key) ? p.muted : Color.clear).frame(width: 4, height: 4)
                }
                .frame(width: 36, height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(DayLabel.longDate(key) + (marked.contains(key) ? ", has sheets" : ""))
        } else {
            Color.clear.frame(width: 36, height: 34)
        }
    }

    private func submitTyped() {
        if let key = DatePhrase.parse(typed, today: today) { onPick(key) } else { typedInvalid = true }
    }

    private func shift(_ delta: Int) {
        let next = MonthGrid.shift(year: year, month: month, by: delta)
        year = next.year; month = next.month
    }

    private func jumpToSelection() {
        let key = selected ?? today
        if let parts = DayMath.parts(key) { year = parts.year; month = parts.month }
    }

    private func jumpToToday() {
        if let parts = DayMath.parts(today) { year = parts.year; month = parts.month }
    }
}

/// Tag chips: `×` removes, `+ tag` opens an input with suggestions and "Create #x".
/// Enter adds; Backspace in the empty input removes the last chip.
struct TagChips: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    @State private var adding = false

    private var tags: [String] { state.current?.tags ?? [] }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text("#\(tag)").font(Fonts.mono(12)).foregroundStyle(p.ink)
                        Button { state.removeTag(tag) } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(p.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove tag \(tag)")
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(p.chrome, in: Capsule())
                    .overlay(Capsule().stroke(p.hairline, lineWidth: 1))
                }
                Button { adding = true } label: {
                    Text("+ tag").font(Fonts.mono(12)).foregroundStyle(p.accent)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $adding, arrowEdge: .bottom) {
                    Themed {
                        TagInput(onDone: { adding = false })
                            .environmentObject(state)
                            .frame(width: 260)
                            .popIn()
                            .presentationCompactAdaptation(.popover)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

struct TagInput: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    let onDone: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private var normalized: String { Tags.normalize(text) }
    private var suggestions: [(tag: String, count: Int)] { Array(state.tagSuggestions(text).prefix(8)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("tag", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(Fonts.mono(13))
                .focused($focused)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .onSubmit(add)
                .onKeyPress(.delete) {
                    guard text.isEmpty, let last = state.current?.tags.last else { return .ignored }
                    state.removeTag(last)
                    return .handled
                }
            ForEach(suggestions, id: \.tag) { s in
                Button { state.addTag(s.tag); text = "" } label: {
                    HStack {
                        Text("#\(s.tag)").font(Fonts.mono(12)).foregroundStyle(p.ink)
                        Spacer()
                        Text("\(s.count)").font(Fonts.mono(11)).foregroundStyle(p.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if !normalized.isEmpty && !suggestions.contains(where: { $0.tag == normalized }) && !(state.current?.tags.contains(normalized) ?? false) {
                Button { add() } label: {
                    Text("Create #\(normalized)").font(Fonts.ui(12, .medium)).foregroundStyle(p.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .onAppear { focused = true }
    }

    private func add() {
        guard !normalized.isEmpty else { onDone(); return }
        state.addTag(normalized)
        text = ""
    }
}
