import SwiftUI
import ScratchpadCore

/// The to-do column: title with a live "N of M done" count and the sort menu, the rows (in the view order)
/// plus exactly one blank row, then "+ Add to-do" and the carry footer.
struct TodoColumnView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    @Environment(\.motion) var motion
    @AppStorage(SettingsKey.todoSort) private var sort: TodoSortMode = .manual
    @AppStorage(SettingsKey.doneSinks) private var doneSinks = true
    @AppStorage(SettingsKey.stamped) private var stamped = ""
    let compact: Bool
    @FocusState private var focused: String?
    @State private var stampShown = false
    @State private var thud = 0
    @State private var countBumps = 0
    /// The row at the top of the list, mirrored into `AppState.todoTopRow` so a fold keeps the scroll.
    @State private var topRow: String?

    private var pad: Pad { state.current ?? Pad.daily("") }

    /// View order plus the blank row.
    private var rows: [Todo] {
        TodoSort.sorted(pad.todos, mode: sort, doneSinks: doneSinks) + [Todo(id: state.blankTodoID, text: "")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, todo in
                        TodoRow(todo: todo, isBlank: todo.id == state.blankTodoID, compact: compact, focused: $focused,
                                hop: state.hopSheetID == pad.id && todo.carriedFrom != nil, hopIndex: index,
                                onSubmit: { focusNext(after: todo.id) },
                                onDrop: { dragged, after in reorder(dragged, target: todo.id, after: after) })
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 2)
            }
            .scrollPosition(id: $topRow, anchor: .top)
            .onAppear {
                if let kept = state.todoTopRow, kept.sheetID == pad.id { topRow = kept.rowID }
            }
            .onChange(of: topRow) { _, id in
                if let id { state.todoTopRow = (pad.id, id) }
            }
            .overlay { if stampShown { AllClearStamp().allowsHitTesting(false).transition(AllClearStamp.transition(motion)) } }
            footer
        }
        .padding(compact ? 16 : 20)
        .background(p.paper)
        .keyframeAnimator(initialValue: Thud(), trigger: thud) { content, v in
            content.offset(y: v.y)
        } keyframes: { _ in
            KeyframeTrack(\.y) {
                CubicKeyframe(0, duration: 0.2)
                CubicKeyframe(2, duration: 0.06)
                SpringKeyframe(0, duration: 0.2)
            }
        }
        .onChange(of: pad.openCount) { old, new in
            if old > 0 && new == 0 && pad.doneCount > 0 { allClear() }
            if new > 0 && stampShown { stampShown = false }
        }
        .onChange(of: pad.doneCount) { _, _ in countBumps += 1 }
        .onChange(of: pad.filledCount) { _, _ in countBumps += 1 }
        .onChange(of: pad.id) { _, _ in stampShown = false }
        .onChange(of: focused) { old, _ in
            if let old, old != state.blankTodoID { state.dropTodoIfEmpty(old) }
        }
    }

    // MARK: Header and footer

    private var header: some View {
        HStack(spacing: 8) {
            Text("To-do").font(Fonts.ui(14, .medium)).foregroundStyle(p.ink)
            Spacer()
            Text(pad.countLabel)
                .font(Fonts.mono(12)).foregroundStyle(p.muted)
                .contentTransition(.numericText())
                .keyframeAnimator(initialValue: Thud(), trigger: motion.isOff ? 0 : countBumps) { content, v in
                    content.offset(y: v.y)
                } keyframes: { _ in
                    KeyframeTrack(\.y) {
                        CubicKeyframe(-4, duration: 0.12)
                        SpringKeyframe(0, duration: 0.24)
                    }
                }
                .animation(motion.count, value: pad.countLabel)
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(TodoSortMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("Done sinks to the bottom", isOn: $doneSinks)
            } label: {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 12))
            }
            .fixedSize()
            .help("Sort: \(sort.label)")
            .accessibilityLabel("Sort to-dos")
        }
        .padding(.horizontal, 12).frame(height: 34)
        .overlay(Rectangle().stroke(p.rule, lineWidth: 1))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { focused = state.blankTodoID } label: {
                Text("+ Add to-do").font(Fonts.ui(13, .medium))
            }
            .buttonStyle(.plain).foregroundStyle(p.accent)
            .keyboardShortcut("t", modifiers: [.command, .shift])
            Text(pad.footerLabel).font(Fonts.ui(12)).foregroundStyle(p.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: Actions

    private func focusNext(after id: String) {
        let ids = rows.map(\.id)
        guard let i = ids.firstIndex(of: id) else { return }
        focused = i + 1 < ids.count ? ids[i + 1] : state.blankTodoID
    }

    /// Dragging while a non-manual sort is active writes the view order into the file, then switches to Manual.
    /// The row lands before `target`, or after it when dropped on its lower half.
    private func reorder(_ dragged: String, target: String, after: Bool) {
        animate(motion.reorder) {
            if sort != .manual || doneSinks {
                state.commitTodoOrder(TodoSort.sorted(pad.todos, mode: sort, doneSinks: doneSinks))
                if sort != .manual { sort = .manual }
            }
            var before: String? = target
            if after || target == state.blankTodoID {
                let ids = (state.current?.todos ?? []).map(\.id).filter { $0 != dragged }
                if let i = ids.firstIndex(of: target) { before = i + 1 < ids.count ? ids[i + 1] : nil } else { before = nil }
            }
            state.moveTodo(dragged, before: before)
        }
    }

    /// "ALL CLEAR" once per sheet per day.
    private func allClear() {
        let key = "\(pad.id)|\(state.todayKey)"
        var seen = stamped.split(separator: "\n").map(String.init)
        guard !seen.contains(key) else { return }
        seen.append(key)
        stamped = seen.suffix(60).joined(separator: "\n")
        if motion.isOff { stampShown = true } else {
            withAnimation(motion.isFull ? .spring(response: 0.52, dampingFraction: 0.6) : .easeOut(duration: 0.3)) { stampShown = true }
        }
        if motion.isFull { thud += 1 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            animate(motion.isOff ? nil : .easeOut(duration: 0.4)) { stampShown = false }
        }
    }
}

struct Thud { var y = 0.0 }

/// Double-bordered rubber stamp in the overdue colour, -8 degrees. Drops in from scale 1.9 at -16 degrees (Full).
struct AllClearStamp: View {
    @Environment(\.palette) var p
    var body: some View {
        Text("ALL CLEAR")
            .font(.system(size: 26, weight: .heavy, design: .rounded))
            .tracking(3)
            .foregroundStyle(p.overdue)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(p.overdue, lineWidth: 2.5))
            .padding(4)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(p.overdue, lineWidth: 1.2))
            .rotationEffect(.degrees(-8))
            .opacity(0.9)
    }

    static func transition(_ motion: Motion) -> AnyTransition {
        motion.isFull ? .modifier(active: StampDrop(progress: 0), identity: StampDrop(progress: 1)) : .opacity
    }
}

struct StampDrop: ViewModifier {
    var progress: Double
    func body(content: Content) -> some View {
        content
            .scaleEffect(1.9 - 0.9 * progress)
            .rotationEffect(.degrees(-8 * (1 - progress)))
            .opacity(progress)
    }
}

struct TickFlecks { var t = 1.0 }
struct Pop { var scale = 1.0 }
struct Draw { var tick = 1.0; var strike = 1.0 }

struct TodoRow: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    @Environment(\.motion) var motion
    let todo: Todo
    let isBlank: Bool
    let compact: Bool
    var focused: FocusState<String?>.Binding
    let hop: Bool
    let hopIndex: Int
    let onSubmit: () -> Void
    /// (dragged id, dropped on the lower half)
    let onDrop: (String, Bool) -> Void
    @State private var ticks = 0
    @State private var gripHovers = 0
    @State private var dropTarget = false
    @State private var hopProgress: Double

    init(todo: Todo, isBlank: Bool, compact: Bool, focused: FocusState<String?>.Binding, hop: Bool, hopIndex: Int,
         onSubmit: @escaping () -> Void, onDrop: @escaping (String, Bool) -> Void) {
        self.todo = todo; self.isBlank = isBlank; self.compact = compact; self.focused = focused
        self.hop = hop; self.hopIndex = hopIndex; self.onSubmit = onSubmit; self.onDrop = onDrop
        _hopProgress = State(initialValue: hop ? 0 : 1)
    }

    private var text: Binding<String> {
        Binding(get: { state.current?.todos.first { $0.id == todo.id }?.text ?? "" },
                set: { state.setTodoText(todo.id, $0) })
    }

    private var inkColor: Color {
        if todo.status != .open { return p.rule }
        return todo.isOverdue() ? p.overdue : p.ink
    }

    var body: some View {
        HStack(spacing: 6) {
            grip
            statusCircle
            ZStack(alignment: .leading) {
                KeptTextField(isBlank ? "New to-do" : "", field: Caret.todo(todo.id), text: text)
                    .textFieldStyle(.plain)
                    .font(Fonts.ui(compact ? 15 : 13)).foregroundStyle(inkColor)
                    .focused(focused, equals: todo.id)
                    .keepsFocus(Caret.todo(todo.id), isFocused: focused.wrappedValue == todo.id) { focused.wrappedValue = todo.id }
                    .onSubmit(onSubmit)
                strike
            }
            .padding(.vertical, 4)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(focused.wrappedValue == todo.id ? p.accent : p.hairline)
                    .frame(height: focused.wrappedValue == todo.id ? 1.5 : 1)
            }
        }
        .frame(height: compact ? 44 : 34)
        .overlay(alignment: .top) {
            if dropTarget { Rectangle().fill(p.accent).frame(height: 2).offset(y: -1) }
        }
        .modifier(HopEffect(progress: hopProgress, arc: motion.isFull))
        .onAppear {
            guard hopProgress < 1 else { return }
            if motion.isOff { hopProgress = 1; return }
            withAnimation(.easeOut(duration: 0.42).delay(0.09 * Double(hopIndex))) { hopProgress = 1 }
        }
        .dropDestination(for: String.self) { items, location in
            guard let id = items.compactMap(TodoDrag.id).first, id != todo.id else { return false }
            let half: CGFloat = compact ? 22 : 17
            onDrop(id, location.y >= half && !isBlank)
            return true
        } isTargeted: { dropTarget = $0 }
        .onChange(of: todo.status) { _, new in if new == .done && !motion.isOff { ticks += 1 } }
    }

    /// Six-dot grip: drag to reorder, onto the canvas, or onto a sheet in the sidebar.
    private var grip: some View {
        Image(systemName: "circle.grid.2x3.fill")
            .font(.system(size: 9))
            .foregroundStyle(p.muted.opacity(isBlank ? 0.3 : 0.8))
            .frame(width: 14, height: compact ? 44 : 30)
            .contentShape(Rectangle())
            .wiggle(trigger: motion.isFull ? gripHovers : 0)
            .onHover { if $0 && !isBlank { gripHovers += 1 } }
            .draggable(TodoDrag.payload(todo.id)) {
                Text(todo.text.isEmpty ? "(empty)" : todo.text).font(Fonts.ui(13)).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(p.cell).overlay(Rectangle().stroke(p.accent, lineWidth: 1))
            }
            .accessibilityLabel("Drag to reorder, onto the sheet, or onto another sheet")
            .opacity(isBlank ? 0 : 1)
            .allowsHitTesting(!isBlank)
    }

    /// Status circle: click cycles open, done, deferred. Ticking pops the circle, draws the tick and throws flecks.
    private var statusCircle: some View {
        Button { if !isBlank { state.cycle(todo.id) } } label: {
            ZStack {
                Circle().stroke(todo.status == .done ? p.accent : p.rule, lineWidth: 1.5)
                if todo.status == .done { Circle().fill(p.accent) }
                if todo.status == .deferred {
                    Path { $0.move(to: CGPoint(x: 15, y: 5)); $0.addLine(to: CGPoint(x: 5, y: 15)) }.stroke(p.rule, lineWidth: 1.5)
                }
                if todo.status == .done {
                    TickShape()
                        .keyframeAnimator(initialValue: Draw(), trigger: ticks) { content, v in
                            content.mask(alignment: .leading) { Rectangle().scaleEffect(x: v.tick, anchor: .leading) }
                        } keyframes: { _ in
                            KeyframeTrack(\.tick) {
                                MoveKeyframe(0)
                                LinearKeyframe(0, duration: 0.09)
                                CubicKeyframe(1, duration: motion.isFull ? 0.26 : 0.18)
                            }
                        }
                        .foregroundStyle(p.accentInk)
                }
            }
            .frame(width: 20, height: 20)
            .keyframeAnimator(initialValue: Pop(), trigger: ticks) { content, v in
                content.scaleEffect(v.scale)
            } keyframes: { _ in
                // Full: 1 -> 1.3 -> 0.9 -> 1 over 460 ms. Subtle: a 260 ms pop.
                KeyframeTrack(\.scale) {
                    SpringKeyframe(motion.isFull ? 1.3 : 1.15, duration: motion.isFull ? 0.14 : 0.1)
                    SpringKeyframe(motion.isFull ? 0.9 : 1.0, duration: motion.isFull ? 0.14 : 0.08)
                    SpringKeyframe(1.0, duration: motion.isFull ? 0.18 : 0.08)
                }
            }
            .background { if motion.isFull { Flecks(trigger: ticks, color: p.accent) } }
            .frame(width: compact ? 44 : 30, height: compact ? 44 : 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isBlank ? 0.35 : 1)
        .accessibilityLabel("Status: \(todo.status.rawValue)")
    }

    /// Strike line scales in from the left, 300 ms after 140 ms.
    @ViewBuilder private var strike: some View {
        if todo.status == .done && !isBlank {
            Rectangle()
                .fill(p.rule)
                .frame(height: 1)
                .keyframeAnimator(initialValue: Draw(), trigger: ticks) { content, v in
                    content.scaleEffect(x: v.strike, anchor: .leading)
                } keyframes: { _ in
                    KeyframeTrack(\.strike) {
                        MoveKeyframe(0)
                        LinearKeyframe(0, duration: 0.14)
                        CubicKeyframe(1, duration: 0.3)
                    }
                }
                .allowsHitTesting(false)
        }
    }
}

/// Six ink flecks fly 18-24 px out from the circle and fade, 560 ms.
struct Flecks: View {
    let trigger: Int
    let color: Color
    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                Circle().fill(color).frame(width: 3, height: 3)
                    .keyframeAnimator(initialValue: TickFlecks(), trigger: trigger) { content, v in
                        let angle = Double(i) * .pi / 3 + 0.3
                        let distance = (18 + Double(i % 3) * 3) * v.t
                        content
                            .offset(x: cos(angle) * distance, y: sin(angle) * distance)
                            .opacity(v.t >= 1 ? 0 : 1 - v.t)
                    } keyframes: { _ in
                        KeyframeTrack(\.t) {
                            MoveKeyframe(0)
                            CubicKeyframe(1, duration: 0.56)
                        }
                    }
            }
        }
        .allowsHitTesting(false)
    }
}

struct TickShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.28, y: rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.width * 0.44, y: rect.height * 0.68))
        path.addLine(to: CGPoint(x: rect.width * 0.74, y: rect.height * 0.34))
        return path.strokedPath(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}

/// A dragged to-do travels as a prefixed string so the canvas can tell it from dropped text.
enum TodoDrag {
    static let prefix = "scratchpad-todo:"
    static func payload(_ id: String) -> String { prefix + id }
    static func id(_ s: String) -> String? { s.hasPrefix(prefix) ? String(s.dropFirst(prefix.count)) : nil }
}
