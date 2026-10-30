import SwiftUI
import ScratchpadCore

/// Modifier keys at the moment of a gesture. macOS reads them from NSEvent; iOS has no global query,
/// so Shift-snap, Shift-aspect and Alt-no-snap are macOS-only.
@MainActor
enum Modifiers {
    static var shift: Bool {
        #if os(macOS)
        return NSEvent.modifierFlags.contains(.shift)
        #else
        return false
        #endif
    }
    static var option: Bool {
        #if os(macOS)
        return NSEvent.modifierFlags.contains(.option)
        #else
        return false
        #endif
    }
}

/// The dot grid. Blocks sit at absolute points; a tap on the dots deselects, a double tap starts a text block,
/// Delete/Backspace deletes the selected block when no text inside it has focus.
struct CanvasView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    @Environment(\.motion) var motion
    @AppStorage(SettingsKey.defaultFont) private var defaultFont: BlockFont = .sans
    @State private var heights: [String: CGFloat] = [:]
    @State private var moving: (id: String, t: CGSize)?
    @State private var resizing: Block?
    @FocusState private var canvasFocused: Bool

    private var blocks: [Block] { state.current?.blocks ?? [] }
    private var selected: Block? { state.selectedBlockID.flatMap { id in blocks.first { $0.id == id } } }

    private func height(of b: Block) -> CGFloat {
        if let r = resizing, r.id == b.id, let h = r.h { return CGFloat(h) }
        return b.h.map { CGFloat($0) } ?? heights[b.id] ?? 120
    }

    private var contentSize: CGSize {
        let maxY = blocks.map { CGFloat($0.y) + height(of: $0) }.max() ?? 0
        let maxX = blocks.map { CGFloat($0.x + $0.w) }.max() ?? 0
        return CGSize(width: max(900, maxX + 240), height: max(720, maxY + 480))
    }

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            ZStack(alignment: .topLeading) {
                DotGrid(color: p.dot)
                    .frame(width: contentSize.width, height: contentSize.height)
                    .contentShape(Rectangle())
                    .focusable()
                    .focusEffectDisabled()
                    .focused($canvasFocused)
                    .onKeyPress(keys: [.delete, .deleteForward]) { _ in
                        guard let id = state.selectedBlockID else { return .ignored }
                        deleteBlock(id)
                        return .handled
                    }
                    .onTapGesture(count: 2) { location in
                        animate(motion.fall) { state.insert(.text, at: location, font: defaultFont) }
                    }
                    .onTapGesture { state.selectedBlockID = nil }
                    .contextMenu {
                        ForEach([BlockKind.text, .table, .code, .link, .divider], id: \.self) { k in
                            Button("Insert \(k.rawValue)") { animate(motion.fall) { state.insert(k, font: defaultFont) } }
                        }
                        Button("Paste as block") {
                            let c = PasteBridge.read()
                            animate(motion.fall) { state.paste(c, font: defaultFont) }
                        }
                    }
                if blocks.isEmpty {
                    EmptySheetHint().allowsHitTesting(false)
                }
                ForEach(blocks) { block in
                    CanvasBlock(
                        block: resizing?.id == block.id ? resizing! : block,
                        selected: state.selectedBlockID == block.id,
                        moveOffset: moving?.id == block.id ? moving!.t : .zero,
                        isMoving: moving?.id == block.id,
                        inserting: state.justInserted.contains(block.id),
                        measuredHeight: height(of: block),
                        onMeasure: { h in if heights[block.id] != h { heights[block.id] = h } },
                        onSelect: { focusCanvas in select(block.id, focusCanvas: focusCanvas) },
                        onMove: { t in moveChanged(block.id, t) },
                        onMoveEnd: { t in moveEnded(block.id, t) },
                        onResize: { corner, t in resizeChanged(block, corner, t) },
                        onResizeEnd: { resizeEnded() },
                        onDelete: { deleteBlock(block.id) }
                    )
                    .transition(motion.deleteTransition)
                    .zIndex(state.selectedBlockID == block.id ? 2 : 1)
                }
                if let sel = selected {
                    let shown = resizing?.id == sel.id ? resizing! : sel
                    let t = moving?.id == sel.id ? moving!.t : .zero
                    BlockToolbar(
                        block: shown,
                        height: height(of: sel),
                        onMove: { moveChanged(sel.id, $0) },
                        onMoveEnd: { moveEnded(sel.id, $0) },
                        onDelete: { deleteBlock(sel.id) }
                    )
                    .fixedSize()
                    .offset(x: CGFloat(shown.x) + t.width, y: max(0, CGFloat(shown.y) + t.height - (sel.kind == .table ? 92 : 46)))
                    .zIndex(3)
                }
            }
            .coordinateSpace(name: "canvas")
            .dropDestination(for: String.self) { items, location in
                guard let id = items.compactMap(TodoDrag.id).first else { return false }
                animate(motion.fall) { state.todoToBlock(id, at: location, font: defaultFont) }
                return true
            }
            #if os(macOS)
            .onDrop(of: PasteBridge.readableTypes, isTargeted: nil) { providers, location in
                PasteBridge.read(providers: providers) { contents in
                    animate(motion.fall) { state.paste(contents, at: location, font: defaultFont) }
                }
                return true
            }
            #endif
        }
        .modifier(KeepsCanvasScroll())
        #if os(macOS)
        .onPasteCommand(of: PasteBridge.readableTypes) { providers in
            PasteBridge.read(providers: providers) { contents in
                animate(motion.fall) { state.paste(contents, font: defaultFont) }
            }
        }
        #endif
        .overlay(alignment: .bottom) { undoToast }
    }

    // MARK: Actions

    private func select(_ id: String, focusCanvas: Bool) {
        if state.selectedBlockID != id { state.selectedBlockID = id }
        if focusCanvas { canvasFocused = true }
    }

    private func deleteBlock(_ id: String) {
        animate(motion.delete) { state.deleteBlock(id) }
    }

    private func moveChanged(_ id: String, _ t: CGSize) {
        if moving == nil {
            animate(motion.lift) { moving = (id, t) }
            select(id, focusCanvas: true)
        } else {
            moving = (id, t)
        }
    }

    private func moveEnded(_ id: String, _ t: CGSize) {
        guard let b = state.block(id) else { moving = nil; return }
        let snap = !Modifiers.option
        animate(motion.lift) {
            state.moveBlock(id, x: CGFloat(b.x) + t.width, y: CGFloat(b.y) + t.height, snap: snap)
            moving = nil
        }
    }

    private func resizeChanged(_ block: Block, _ corner: Block.Corner, _ t: CGSize) {
        let start = block.h.map { CGFloat($0) } ?? heights[block.id] ?? 120
        resizing = block.resized(corner: corner, dx: Double(t.width), dy: Double(t.height), startHeight: Double(start), keepAspect: Modifiers.shift)
        select(block.id, focusCanvas: true)
    }

    private func resizeEnded() {
        guard var r = resizing, let original = state.block(r.id) else { resizing = nil; return }
        if r.kind == .table {
            // Tables scale their columns to the new width.
            let widths = TableLayout.widths(for: original)
            let total = max(1, widths.reduce(0, +))
            r.colWidths = widths.map { max(TableLayout.minColumn, Int((Double($0) * Double(r.w) / Double(total)).rounded())) }
            r.w = r.colWidths!.reduce(0, +)
        }
        state.update(r)
        resizing = nil
    }

    // MARK: Undo toast

    @ViewBuilder private var undoToast: some View {
        if let d = state.deleted, d.sheetID == state.current?.id {
            HStack(spacing: 10) {
                Text("\(d.block.kind.label) deleted").font(Fonts.ui(13)).foregroundStyle(p.paper)
                Text("·").foregroundStyle(p.paper.opacity(0.6))
                Button { animate(motion.fall) { state.undoDelete() } } label: {
                    Text("Undo").font(Fonts.ui(13, .semibold)).foregroundStyle(p.paper).underline()
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(p.ink, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
            .padding(.bottom, 20)
            .transition(.asymmetric(insertion: .offset(y: 12).combined(with: .opacity), removal: .opacity))
            .id(d.token)
        }
    }
}

struct DotGrid: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let g = CGFloat(gridSize)
            var y = g / 2
            while y < size.height {
                var x = g / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2)), with: .color(color))
                    x += g
                }
                y += g
            }
        }
    }
}

/// Outer 4 px outside and 4 px inside the block's frame: the move handle. Inner content stays editable.
struct EdgeBand: Shape {
    var width: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        let inner = rect.insetBy(dx: width, dy: width)
        if inner.width > 0 && inner.height > 0 { path.addRect(inner) }
        return path
    }
}

struct Bounce { var scale = 1.0 }

/// One block on the canvas: selection chrome, edge-band move, corner resize, rotation and motion.
struct CanvasBlock: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    @Environment(\.motion) var motion
    let block: Block
    let selected: Bool
    let moveOffset: CGSize
    let isMoving: Bool
    let measuredHeight: CGFloat
    let onMeasure: (CGFloat) -> Void
    let onSelect: (Bool) -> Void
    let onMove: (CGSize) -> Void
    let onMoveEnd: (CGSize) -> Void
    let onResize: (Block.Corner, CGSize) -> Void
    let onResizeEnd: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false
    @State private var drops = 0
    @State private var fall: Double
    @State private var ripple = false

    init(block: Block, selected: Bool, moveOffset: CGSize, isMoving: Bool, inserting: Bool, measuredHeight: CGFloat,
         onMeasure: @escaping (CGFloat) -> Void, onSelect: @escaping (Bool) -> Void,
         onMove: @escaping (CGSize) -> Void, onMoveEnd: @escaping (CGSize) -> Void,
         onResize: @escaping (Block.Corner, CGSize) -> Void, onResizeEnd: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.block = block; self.selected = selected; self.moveOffset = moveOffset; self.isMoving = isMoving
        self.measuredHeight = measuredHeight; self.onMeasure = onMeasure; self.onSelect = onSelect
        self.onMove = onMove; self.onMoveEnd = onMoveEnd; self.onResize = onResize; self.onResizeEnd = onResizeEnd
        self.onDelete = onDelete
        _fall = State(initialValue: inserting ? 0 : 1)
    }

    /// Text-bearing blocks keep keyboard focus in their editors when tapped.
    private var hasText: Bool { [.text, .code, .table, .link].contains(block.kind) }

    private var lift: CGFloat {
        if isMoving { return motion.isOff ? 0 : -5 }
        if hovering && motion.isFull { return -3 }
        return 0
    }

    private var tilt: Double {
        guard isMoving, motion.isFull, moveOffset.width != 0 else { return 0 }
        return moveOffset.width > 0 ? -2 : 2
    }

    var body: some View {
        BlockView(block: block, selected: selected)
            .frame(width: CGFloat(block.w), height: block.h.map { CGFloat($0) }, alignment: .topLeading)
            .mask { Rectangle().padding(block.h != nil && block.kind != .table ? 0 : -4000) }
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { if block.h == nil { onMeasure(g.size.height) } }
                    .onChange(of: g.size.height) { _, h in if block.h == nil { onMeasure(h) } }
            })
            .overlay { if ripple { Ripple().padding(-6) } }
            .overlay { band }
            .overlay { if selected { chrome } }
            .rotationEffect(.degrees(block.rotation + tilt))
            .keyframeAnimator(initialValue: Bounce(), trigger: drops) { content, v in
                content.scaleEffect(v.scale)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    SpringKeyframe(1.035, duration: 0.1)
                    SpringKeyframe(1.0, duration: 0.14)
                }
            }
            .shadow(color: .black.opacity(isMoving ? 0.22 : (lift < 0 ? 0.12 : 0)), radius: isMoving ? 14 : 6, y: isMoving ? 8 : 3)
            .offset(y: lift)
            .modifier(FallEffect(progress: fall))
            .offset(x: CGFloat(block.x) + moveOffset.width, y: CGFloat(block.y) + moveOffset.height)
            .onHover { inside in animate(motion.hover) { hovering = inside } }
            .simultaneousGesture(TapGesture().onEnded { onSelect(!hasText) })
            .contextMenu {
                Button("Duplicate") { animate(motion.fall) { state.duplicateBlock(block.id) } }
                Button("Rotate 15°") { state.mutate(block.id) { $0.rotateStep() } }
                Button("Reset rotation") { state.mutate(block.id) { $0.rotation = 0 } }
                Divider()
                Button("Delete", role: .destructive) { onDelete() }
            }
            .onChange(of: isMoving) { was, now in
                if was && !now && !motion.isOff { drops += 1 }
            }
            .onAppear {
                guard fall < 1 else { return }
                if motion.isOff { fall = 1; return }
                withAnimation(motion.fall) { fall = 1 }
                if motion.isFull {
                    ripple = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        ripple = false
                    }
                }
            }
    }

    /// 8 px band around the edge: drag to move, click to select.
    private var band: some View {
        Color.clear
            .padding(-4)
            .contentShape(EdgeBand(width: 8), eoFill: true)
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("canvas"))
                    .onChanged { onMove($0.translation) }
                    .onEnded { onMoveEnd($0.translation) }
            )
            .onTapGesture { onSelect(true) }
            #if os(macOS)
            .onHover { inside in if inside { NSCursor.openHand.push() } else { NSCursor.pop() } }
            #endif
    }

    /// 1.5 px accent outline offset 5 px, four 10 px corner handles.
    private var chrome: some View {
        ZStack {
            Rectangle().stroke(p.accent, lineWidth: 1.5).padding(-5).allowsHitTesting(false)
            handle(.topLeading, .topLeft)
            handle(.topTrailing, .topRight)
            handle(.bottomLeading, .bottomLeft)
            handle(.bottomTrailing, .bottomRight)
        }
    }

    private func handle(_ alignment: Alignment, _ corner: Block.Corner) -> some View {
        Rectangle()
            .fill(p.cell)
            .frame(width: 10, height: 10)
            .overlay(Rectangle().stroke(p.accent, lineWidth: 1.5))
            .padding(4)
            .contentShape(Rectangle())
            .offset(x: corner.isLeft ? -10 : 10, y: corner.isTop ? -10 : 10)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("canvas"))
                    .onChanged { onResize(corner, $0.translation) }
                    .onEnded { _ in onResizeEnd() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .accessibilityLabel("Resize")
    }
}

/// Floating toolbar above the selected block's top-left: Move grip, Font, Rotate, Duplicate, Delete.
struct BlockToolbar: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    @Environment(\.motion) var motion
    let block: Block
    let height: CGFloat
    let onMove: (CGSize) -> Void
    let onMoveEnd: (CGSize) -> Void
    let onDelete: () -> Void
    @State private var fontOpen = false
    @State private var rotateStart: (pointer: Double, rotation: Double)?
    @State private var gripHovers = 0

    private var center: CGPoint {
        CGPoint(x: Double(block.x) + Double(block.w) / 2, y: Double(block.y) + Double(height) / 2)
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .wiggle(trigger: motion.isFull ? gripHovers : 0)
                .onHover { if $0 { gripHovers += 1 } }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named("canvas"))
                        .onChanged { onMove($0.translation) }
                        .onEnded { onMoveEnd($0.translation) }
                )
                .help("Drag to move")
                .accessibilityLabel("Move")

            Button { fontOpen = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "textformat")
                    Text("\(block.font.label) \(block.fontSize)").font(Fonts.ui(12))
                }
                .padding(.horizontal, 6).frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $fontOpen, arrowEdge: .bottom) {
                Themed {
                    FontPanel(blockID: block.id)
                        .environmentObject(state)
                        .popIn()
                        .presentationCompactAdaptation(.popover)
                }
            }
            .help("Font")

            HStack(spacing: 4) {
                Image(systemName: "rotate.right")
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
                    .gesture(rotateGesture)
                    .help("Click to rotate 15°, drag to rotate freely (Shift snaps)")
                    .accessibilityLabel("Rotate 15 degrees")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { state.mutate(block.id) { $0.rotateStep() } }
                Text(angleText)
                    .font(Fonts.mono(11))
                    .frame(minWidth: 30, alignment: .leading)
                    .onTapGesture(count: 2) { state.mutate(block.id) { $0.rotation = 0 } }
                    .help("Double-click to reset")
            }

            Button { animate(motion.fall) { state.duplicateBlock(block.id) } } label: {
                Image(systemName: "plus.square.on.square").frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Duplicate")
            .accessibilityLabel("Duplicate")

            Rectangle().fill(p.hairline).frame(width: 1, height: 18).padding(.horizontal, 3)

            Button(action: onDelete) {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text("Delete").font(Fonts.ui(12, .medium))
                }
                .foregroundStyle(p.overdue)
                .padding(.horizontal, 8).frame(height: 26)
                .background(p.overdue.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(p.ink)
        .padding(.horizontal, 4).padding(.vertical, 3)
        .background(p.cell, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    private var angleText: String {
        let r = block.rotation
        return r == r.rounded() ? "\(Int(r))°" : String(format: "%.1f°", r)
    }

    private func degrees(_ pt: CGPoint) -> Double {
        atan2(Double(pt.y - center.y), Double(pt.x - center.x)) * 180 / .pi
    }

    /// A click (no travel) adds 15 degrees; a drag sets the angle from the block centre to the pointer.
    private var rotateGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
            .onChanged { v in
                let travel = hypot(v.translation.width, v.translation.height)
                guard travel >= 3 else { return }
                if rotateStart == nil { rotateStart = (degrees(v.startLocation), block.rotation) }
                guard let s = rotateStart else { return }
                var angle = s.rotation + degrees(v.location) - s.pointer
                if Modifiers.shift { angle = (angle / 15).rounded() * 15 }
                state.mutate(block.id) { $0.rotation = Block.normalizedRotation(angle) }
            }
            .onEnded { v in
                if rotateStart == nil && hypot(v.translation.width, v.translation.height) < 3 {
                    animate(motion.lift) { state.mutate(block.id) { $0.rotateStep() } }
                }
                rotateStart = nil
            }
    }
}

/// Font family, size stepper 10-48, bold, italic.
struct FontPanel: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    let blockID: String

    private var block: Block? { state.block(blockID) }

    private func binding<T>(_ path: WritableKeyPath<Block, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { state.block(blockID)?[keyPath: path] ?? fallback },
                set: { v in state.mutate(blockID) { $0[keyPath: path] = v } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Font", selection: binding(\.font, .sans)) {
                ForEach(BlockFont.allCases) { f in Text(f.label).tag(f) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack(spacing: 8) {
                ForEach(BlockFont.allCases) { f in
                    Text("Aa").font(Fonts.block(f, size: 16)).foregroundStyle(block?.font == f ? p.accent : p.muted).frame(maxWidth: .infinity)
                }
            }
            Stepper(value: binding(\.fontSize, Block.defaultFontSize), in: Block.fontSizeRange) {
                Text("Size \(block?.fontSize ?? Block.defaultFontSize)").font(Fonts.ui(13))
            }
            Toggle("Bold", isOn: binding(\.bold, false))
            Toggle("Italic", isOn: binding(\.italic, false))
        }
        .padding(16)
        .frame(width: 260)
    }
}

/// Empty sheet: a pencil squiggle draws itself (Full), then the hint fades in.
struct EmptySheetHint: View {
    @Environment(\.palette) var p
    @Environment(\.motion) var motion
    @State private var draw = 0.0
    @State private var showText = false

    private var hint: String {
        #if os(macOS)
        return "Paste anything here, or double-click the dots to write."
        #else
        return "Paste anything here, or double-tap the dots to write."
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Squiggle()
                .trim(from: 0, to: draw)
                .stroke(p.muted, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 180, height: 36)
                .opacity(motion.isFull ? 1 : 0)
            Text(hint).font(Fonts.ui(13)).foregroundStyle(p.muted).opacity(showText ? 1 : 0)
        }
        .padding(.leading, 48).padding(.top, 48)
        .onAppear {
            switch motion.level {
            case .full:
                withAnimation(.easeInOut(duration: 1.4).delay(0.5)) { draw = 1 }
                withAnimation(.easeOut(duration: 0.3).delay(1.9)) { showText = true }
            case .subtle:
                withAnimation(.easeOut(duration: 0.3).delay(0.2)) { showText = true }
            case .off:
                draw = 1; showText = true
            }
        }
    }
}

struct Squiggle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let h = rect.height, w = rect.width
        path.move(to: CGPoint(x: 0, y: h * 0.6))
        let steps = 6
        for i in 0..<steps {
            let x0 = w * CGFloat(i) / CGFloat(steps), x1 = w * CGFloat(i + 1) / CGFloat(steps)
            let up = i % 2 == 0
            path.addCurve(to: CGPoint(x: x1, y: h * (up ? 0.45 : 0.6)),
                          control1: CGPoint(x: x0 + (x1 - x0) * 0.3, y: up ? 0 : h),
                          control2: CGPoint(x: x0 + (x1 - x0) * 0.7, y: up ? 0 : h))
        }
        return path
    }
}

/// Keeps the canvas's scroll offset in `AppState.canvasOffset`, so a fold or unfold (which rebuilds
/// the sheet in the other layout) lands on the same part of the sheet, and on iOS tells an attached
/// monitor where the phone's window is. Uses `ScrollPosition` and `onScrollGeometryChange`.
struct KeepsCanvasScroll: ViewModifier {
    func body(content: Content) -> some View {
        content.modifier(CanvasScrollKeeper())
    }
}

private struct CanvasScrollKeeper: ViewModifier {
    @EnvironmentObject var state: AppState
    @State private var position = ScrollPosition()
    /// Offsets reported before the saved one is put back (the first layout, at zero) aren't recorded.
    @State private var restored = false

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGPoint.self, of: { $0.contentOffset }) { _, offset in
                guard restored, let id = state.current?.id else { return }
                state.canvasOffset = (id, offset)
            }
            #if os(iOS)
            // The phone's window onto the sheet, framed on an attached monitor (MonitorDisplay.swift).
            .onScrollGeometryChange(for: MonitorViewport.self, of: { MonitorViewport(visible: $0.visibleRect, content: $0.contentSize) }) { _, v in
                guard let id = state.current?.id else { return }
                MonitorModel.shared.canvasMoved(sheetID: id, v)
            }
            .onDisappear { MonitorModel.shared.canvasGone() }
            #endif
            .onAppear {
                if let saved = state.canvasOffset, saved.sheetID == state.current?.id {
                    position.scrollTo(point: saved.point)
                }
                restored = true
            }
    }
}
