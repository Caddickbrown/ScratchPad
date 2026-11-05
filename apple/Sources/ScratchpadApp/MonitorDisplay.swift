//
//  MonitorDisplay.swift
//
//  Monitor mode: plug an iPhone or iPad into a monitor and Scratchpad gets a window of its own
//  there instead of a mirror (the external-display scene declared in project.yml points at
//  `MonitorSceneDelegate` below). The monitor shows the whole sheet as a whiteboard, with the
//  to-dos down its side; the phone is a window onto it, at full size, and a frame on the monitor
//  shows where that window is. Panning the phone's canvas moves the frame, so there is no new
//  gesture: the canvas's own scroll is the window (`CanvasScrollKeeper` reports it here).
//
//  The monitor can't be touched, so it only draws. Editing stays on the phone, and the monitor
//  follows: blocks, text as it is typed, the selected block, ticks in the to-do list, and a block
//  in the middle of a drag or a resize, which reaches `AppState` only when it's let go.
//
//  iOS only: the Mac app has its own windows.
//

#if os(iOS)
import SwiftUI
import UIKit
import ScratchpadCore

// MARK: - Shared state

/// The phone's window onto the sheet, in canvas points.
struct MonitorViewport: Equatable {
    var visible: CGRect
    var content: CGSize
}

/// A block in the phone's hands: as it is drawn right now, not yet in `AppState`.
struct MonitorLiveBlock {
    /// With a resize or a column drag already applied.
    var block: Block
    /// How far a move has carried it, in canvas points.
    var offset: CGSize = .zero
    var isMoving = false
}

/// The live block, on its own because it changes with every touch of a drag: only
/// `MonitorLiveLayer` watches it, so a drag redraws that one block and not the board.
@MainActor final class MonitorLive: ObservableObject {
    @Published fileprivate(set) var current: MonitorLiveBlock?
}

/// Which block the phone has hold of. Changes only as a gesture starts and ends.
struct MonitorHold: Equatable {
    var sheetID: String
    var blockID: String
    var isMoving: Bool
}

/// Shared between the app's scene and the monitor's. A singleton because the monitor's window is
/// built by a UIKit scene delegate, which can't reach the app scene's environment.
@MainActor final class MonitorModel: ObservableObject {
    static let shared = MonitorModel()

    @Published private(set) var isConnected = false
    /// The app's state, so the monitor draws the open sheet live. Set once by the app's root view.
    @Published private(set) var state: AppState?
    /// An external-display scene doesn't follow the device's appearance, so the app pushes its
    /// resolved scheme here and the monitor forces it.
    @Published var colorScheme: ColorScheme = .light
    /// Where the phone's window sits, for the sheet it is on. Nil while no canvas is showing
    /// (the iPhone's sheet list, say), and then the monitor draws no frame.
    @Published private(set) var viewport: (sheetID: String, rect: MonitorViewport)?
    /// The phone is on its sheet list, so the monitor shows the list too (`MonitorHome`).
    @Published var atHome = false
    /// The block being dragged or resized on the phone, if any.
    @Published private(set) var hold: MonitorHold?
    let live = MonitorLive()

    /// Kept while nothing is attached, so connecting draws the frame straight away.
    private var latest: (sheetID: String, rect: MonitorViewport)?

    private init() {}

    func attach(_ state: AppState) {
        if self.state !== state { self.state = state }
    }

    /// Called on every scroll; cheap while no monitor is attached.
    func canvasMoved(sheetID: String, _ v: MonitorViewport) {
        latest = (sheetID, v)
        guard isConnected else { return }
        if viewport?.sheetID != sheetID || viewport?.rect != v { viewport = latest }
    }

    func canvasGone() {
        latest = nil
        if isConnected, viewport != nil { viewport = nil }
        blockLetGo()
    }

    /// Called on every touch of a drag or resize; cheap while no monitor is attached.
    func blockHeld(sheetID: String, _ held: MonitorLiveBlock) {
        guard isConnected else { return }
        live.current = held
        let next = MonitorHold(sheetID: sheetID, blockID: held.block.id, isMoving: held.isMoving)
        if hold != next { hold = next }
    }

    func blockLetGo() {
        if hold != nil { hold = nil }
        if live.current != nil { live.current = nil }
    }

    func displayDidConnect() {
        isConnected = true
        viewport = latest
        updateIdleTimer()
    }

    func displayDidDisconnect() {
        isConnected = false
        viewport = nil
        blockLetGo()
        updateIdleTimer()
    }

    /// The phone stays awake while it's driving a monitor.
    func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = isConnected
    }
}

// MARK: - Scene plumbing

/// Delegate for the `UIWindowSceneSessionRoleExternalDisplayNonInteractive` role. Declaring that
/// role in the scene manifest is what stops iOS mirroring the app onto the monitor.
final class MonitorSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard session.role == .windowExternalDisplayNonInteractive,
              let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: MonitorRoot())
        // Shown but never made key: the phone keeps keyboard focus.
        window.isHidden = false
        self.window = window
        MonitorModel.shared.displayDidConnect()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        guard scene.session.role == .windowExternalDisplayNonInteractive else { return }
        window = nil
        MonitorModel.shared.displayDidDisconnect()
    }
}

// MARK: - Esc

/// Esc on the phone's keyboard while a monitor is attached, heard two ways, as no one way reaches
/// everywhere. With nothing being typed in, `MonitorEscapeController` holds first responder and has
/// the key, whatever is presented over it. A field being typed in has first responder instead and
/// the controller isn't in its chain, so `Themed`, which wraps the root and every sheet and popover,
/// listens with `onKeyPress`. A field in an alert goes to the alert's own Cancel, with the same result.
struct MonitorEscape: UIViewControllerRepresentable {
    let stepBack: () -> Void

    func makeUIViewController(context: Context) -> MonitorEscapeController { MonitorEscapeController() }

    func updateUIViewController(_ controller: MonitorEscapeController, context: Context) {
        controller.stepBack = stepBack
    }

    /// Takes the caret out of whatever has it. False if nothing was being typed in.
    static func endTyping() -> Bool {
        guard UIResponder.monitorFirstResponder() is UIKeyInput else { return false }
        return UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

final class MonitorEscapeController: UIViewController {
    private static weak var active: MonitorEscapeController?
    var stepBack: () -> Void = {}
    private var reclaim: Timer?

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        let command = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escape))
        command.wantsPriorityOverSystemBehavior = true
        return [command]
    }

    @objc private func escape() { stepBack() }

    /// For `Themed`'s `onKeyPress`. False with no monitor attached, which leaves Esc to the system.
    static func heard() -> Bool {
        guard let active else { return false }
        active.stepBack()
        return true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Self.active = self
        becomeFirstResponder()
        // A closing sheet or a field giving up the keyboard leaves no first responder, and then no
        // key reaches the app. Take it back, but never from a field being typed in.
        reclaim?.invalidate()
        reclaim = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.view.window != nil, !self.isFirstResponder else { return }
                if !(UIResponder.monitorFirstResponder() is UIKeyInput) { self.becomeFirstResponder() }
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if Self.active === self { Self.active = nil }
        reclaim?.invalidate()
        reclaim = nil
    }
}

extension UIResponder {
    private static weak var captured: UIResponder?

    /// Who has first responder, if anyone. UIKit doesn't say, so an action sent to nobody in
    /// particular goes to whoever does, and it reports itself.
    fileprivate static func monitorFirstResponder() -> UIResponder? {
        captured = nil
        UIApplication.shared.sendAction(#selector(monitorCaptureFirstResponder), to: nil, from: nil, for: nil)
        return captured
    }

    @objc private func monitorCaptureFirstResponder() { UIResponder.captured = self }
}

// MARK: - Monitor views

struct MonitorRoot: View {
    @ObservedObject private var model = MonitorModel.shared

    var body: some View {
        Themed {
            Group {
                if let state = model.state {
                    MonitorBoard(viewport: model.viewport, hold: model.hold, atHome: model.atHome).environmentObject(state)
                } else {
                    Color.clear
                }
            }
        }
        .environment(\.colorScheme, model.colorScheme)
        .preferredColorScheme(model.colorScheme)
        .ignoresSafeArea()
    }
}

/// Type sized off the panel rather than the phone's text settings.
private struct MonitorMetrics {
    let text: CGFloat
    let padding: CGFloat
    let column: CGFloat

    init(size: CGSize) {
        text = min(26, max(14, size.height * 0.017))
        // TVs overscan and monitors have bezels; keep well inside both.
        padding = max(24, min(size.width, size.height) * 0.03)
        column = min(420, max(240, size.width * 0.2))
    }
}

/// The whole sheet on the desk, the phone's window framed on it, the to-dos at its side.
struct MonitorBoard: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    let viewport: (sheetID: String, rect: MonitorViewport)?
    let hold: MonitorHold?
    let atHome: Bool

    var body: some View {
        GeometryReader { geo in
            let m = MonitorMetrics(size: geo.size)
            ZStack {
                p.desk
                if atHome {
                    MonitorHome(metrics: m).padding(m.padding)
                } else if let pad = state.current {
                    VStack(alignment: .leading, spacing: m.padding * 0.5) {
                        MonitorHeader(pad: pad, metrics: m)
                        HStack(alignment: .top, spacing: m.padding) {
                            MonitorSheet(pad: pad, selectedID: state.selectedBlockID,
                                         viewport: viewport?.sheetID == pad.id ? viewport?.rect : nil,
                                         hold: hold?.sheetID == pad.id ? hold : nil)
                            MonitorTodos(pad: pad, metrics: m).frame(width: m.column)
                        }
                    }
                    .padding(m.padding)
                } else {
                    Text("Scratchpad").font(Fonts.ui(m.text * 2, .semibold)).foregroundStyle(p.muted)
                }
            }
        }
    }
}

/// The phone's sheet list, on the monitor: where Esc ends up, so it shows on the screen being
/// watched. Newest edits first, in columns, narrowing as the phone's search does.
private struct MonitorHome: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    let metrics: MonitorMetrics

    private var sheets: [Pad] { Sidebar.recent(state.filteredPads).flatMap(\.sheets) + Sidebar.pinned(state.filteredPads) }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.padding * 0.75) {
            Text("Scratchpad").font(Fonts.ui(metrics.text * 2, .bold)).foregroundStyle(p.ink)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: metrics.column), spacing: metrics.text)], alignment: .leading, spacing: metrics.text) {
                ForEach(sheets.prefix(48)) { pad in
                    VStack(alignment: .leading, spacing: metrics.text * 0.2) {
                        Text(pad.displayTitle).font(Fonts.ui(metrics.text, .medium)).foregroundStyle(p.ink).lineLimit(1)
                        Text(pad.date ?? "Pinned").font(Fonts.mono(metrics.text * 0.7)).foregroundStyle(p.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(metrics.text * 0.8)
                    .background(p.paper, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }
}

private struct MonitorHeader: View {
    @Environment(\.palette) var p
    let pad: Pad
    let metrics: MonitorMetrics

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: metrics.text) {
            Text(pad.displayTitle).font(Fonts.ui(metrics.text * 1.5, .semibold)).foregroundStyle(p.ink).lineLimit(1)
            if let date = pad.date {
                Text(date).font(Fonts.mono(metrics.text * 0.8)).foregroundStyle(p.muted)
            }
            ForEach(pad.tags, id: \.self) { tag in
                Text("#\(tag)").font(Fonts.ui(metrics.text * 0.8)).foregroundStyle(p.muted)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The sheet scaled to fit its space, the paper reaching past the content to fill what's left of
/// the panel (`MonitorFit`), so a wide monitor gets a wide sheet. Past `minScale` a big sheet would be unreadable, so it
/// stays at that scale and keeps the phone's window in view instead, except while a block is being
/// moved: then it shrinks as far as it takes, so the block can be placed against the whole sheet.
struct MonitorSheet: View {
    @Environment(\.palette) var p
    @Environment(\.motion) var motion
    let pad: Pad
    let selectedID: String?
    let viewport: MonitorViewport?
    let hold: MonitorHold?
    /// Heights of blocks that size to their content, as drawn here.
    @State private var heights: [String: CGFloat] = [:]

    static let minScale: CGFloat = 0.45
    static let maxScale: CGFloat = 1.6
    /// The floor while a block is moving: past readable, but it only has to show where things are.
    static let overviewScale: CGFloat = 0.05

    private var overview: Bool { hold?.isMoving == true }

    private func height(of b: Block) -> CGFloat { b.h.map { CGFloat($0) } ?? heights[b.id] ?? 120 }

    /// The canvas's own extent rule (`CanvasView.contentSize`), on the heights drawn here. The phone's
    /// extent isn't used: it measures a text block's editor as far taller than its text, which
    /// would shrink the sheet to `minScale`. Only the phone's window has to stay on the sheet.
    private var contentSize: CGSize {
        let maxY = pad.blocks.map { CGFloat($0.y) + height(of: $0) }.max() ?? 0
        let maxX = pad.blocks.map { CGFloat($0.x + $0.w) }.max() ?? 0
        let own = CGSize(width: max(900, maxX + 240), height: max(720, maxY + 480))
        guard let v = viewport else { return own }
        return CGSize(width: max(own.width, min(v.visible.maxX, v.content.width)),
                      height: max(own.height, min(v.visible.maxY, v.content.height)))
    }

    var body: some View {
        GeometryReader { geo in
            let fit = MonitorFit(content: contentSize, space: geo.size,
                                 least: overview ? Self.overviewScale : Self.minScale, most: Self.maxScale)
            let size = fit.paper, scale = fit.scale
            let shown = CGSize(width: size.width * scale, height: size.height * scale)
            let shift = pan(shown: shown, space: geo.size, scale: scale)
            ZStack(alignment: .topLeading) {
                DotGrid(color: p.dot).frame(width: size.width, height: size.height)
                // The held block is left to the live layer, which draws it where the finger has it.
                ForEach(pad.blocks.filter { $0.id != hold?.blockID }) { block in
                    MonitorBlock(block: block, selected: block.id == selectedID)
                }
                if let hold {
                    MonitorLiveLayer(live: MonitorModel.shared.live, height: heights[hold.blockID] ?? 120)
                }
                if let v = viewport {
                    ViewportFrame(rect: v.visible, scale: scale, accent: p.accent)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .onPreferenceChange(MonitorBlockHeights.self) { measured in
                // A held block is drawn by the live layer and drops out of this; it keeps its height.
                let all = heights.merging(measured) { $1 }
                if all != heights { heights = all }
            }
            .background(p.paper)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: shown.width, height: shown.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.1), radius: 10, y: 2)
            .offset(shift)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            .animation(motion.isOff ? nil : .easeInOut(duration: 0.2), value: overview)
        }
    }

    /// Centres a sheet that fits; scrolls one that doesn't so the phone's window stays in the
    /// middle, without running past the sheet's edges.
    private func pan(shown: CGSize, space: CGSize, scale: CGFloat) -> CGSize {
        func axis(_ shown: CGFloat, _ space: CGFloat, _ centre: CGFloat?) -> CGFloat {
            if shown <= space { return (space - shown) / 2 }
            guard let centre else { return 0 }
            return min(0, max(space - shown, space / 2 - centre * scale))
        }
        let v = viewport?.visible
        return CGSize(width: axis(shown.width, space.width, v?.midX), height: axis(shown.height, space.height, v?.midY))
    }
}

/// The block in the phone's hands, redrawn on every touch while the sheet under it stands still:
/// the block as the phone shows it and, for a move, the dashed outline of where it will land.
/// The offset sits outside `MonitorBlock`, so a move shifts the block without rebuilding it.
private struct MonitorLiveLayer: View {
    @ObservedObject var live: MonitorLive
    /// The block's content height, for a block with none set.
    let height: CGFloat

    var body: some View {
        if let held = live.current {
            if held.isMoving {
                LandingGuide(block: held.block, height: held.block.h.map { CGFloat($0) } ?? height, offset: held.offset, snap: true)
            }
            MonitorBlock(block: held.block, selected: true)
                .shadow(color: .black.opacity(held.isMoving ? 0.22 : 0), radius: 14, y: 8)
                .offset(held.offset)
        }
    }
}

/// The phone's window: a frame drawn at the same thickness whatever the sheet's scale, with the
/// rest of the sheet faintly dimmed so the eye finds it.
private struct ViewportFrame: View {
    let rect: CGRect
    let scale: CGFloat
    let accent: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .reverseMask(rect: rect)
                .allowsHitTesting(false)
            RoundedRectangle(cornerRadius: 10 / scale)
                .stroke(accent, lineWidth: 3 / scale)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        }
    }
}

private extension View {
    /// Everything but `rect`.
    func reverseMask(rect: CGRect) -> some View {
        mask {
            Canvas { ctx, size in
                var path = Path(CGRect(origin: .zero, size: size))
                path.addRect(rect)
                ctx.fill(path, with: .color(.black), style: FillStyle(eoFill: true))
            }
        }
    }
}

/// Blocks' drawn heights by id, gathered for the sheet's extent.
private struct MonitorBlockHeights: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// One block, drawn read-only. Not `BlockView`: its editors keep focus and caret in `AppState`,
/// and a second copy on the monitor would fight the phone's for them.
private struct MonitorBlock: View {
    @Environment(\.palette) var p
    let block: Block
    let selected: Bool

    var body: some View {
        content
            .frame(width: CGFloat(block.w), height: block.h.map { CGFloat($0) }, alignment: .topLeading)
            .clipped()
            .background(GeometryReader { g in
                Color.clear.preference(key: MonitorBlockHeights.self, value: [block.id: g.size.height])
            })
            .overlay {
                if selected { Rectangle().stroke(p.accent, lineWidth: 1.5).padding(-3) }
            }
            .rotationEffect(.degrees(block.rotation))
            .offset(x: CGFloat(block.x), y: CGFloat(block.y))
    }

    @ViewBuilder private var content: some View {
        switch block.kind {
        case .text:
            // TextEditor's own insets: the text container's 8 pt and the line fragment's 5 pt.
            Text(block.text ?? "")
                .font(Fonts.block(block)).foregroundStyle(p.ink)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                .padding(.horizontal, 13).padding(.vertical, 12)
        case .code:
            Text(block.text ?? "")
                .font(Fonts.block(block.font == .sans ? .mono : block.font, size: CGFloat(block.fontSize) - 2, bold: block.bold, italic: block.italic))
                .foregroundStyle(p.codeInk)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                .padding(.horizontal, 13).padding(.vertical, 16)
                .background(p.codeBg, in: RoundedRectangle(cornerRadius: 4))
        case .table:
            MonitorTable(block: block)
        case .image:
            ImageBlock(block: block)
        case .file:
            FileBlock(block: block).allowsHitTesting(false)
        case .link:
            VStack(alignment: .leading, spacing: 2) {
                Text(block.text ?? "").font(Fonts.block(block.font, size: CGFloat(block.fontSize), bold: true, italic: block.italic))
                    .foregroundStyle(p.ink).lineLimit(1)
                Text(block.url ?? "").font(Fonts.mono(11)).foregroundStyle(p.muted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(p.cell, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(p.rule, lineWidth: 1))
        case .divider:
            Rectangle().fill(p.rule).frame(height: 1).padding(.vertical, 11)
        }
    }
}

/// A table's computed values, laid out as `TableBlock` lays them out.
private struct MonitorTable: View {
    @Environment(\.palette) var p
    let block: Block

    var body: some View {
        let rows = block.rows ?? [[""]]
        let cols = max(1, rows.map(\.count).max() ?? 1)
        let widths = TableLayout.widths(for: block)
        let eval = TableEvaluator(rows: rows)
        let size = CGFloat(max(10, block.fontSize - 1))
        VStack(alignment: .leading, spacing: 6) {
            if let caption = block.caption, !caption.isEmpty {
                Text(caption).font(Fonts.ui(12, .semibold)).foregroundStyle(p.muted).padding(.leading, 4)
            }
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<cols, id: \.self) { c in
                            let raw = eval.raw(r, c)
                            let isFormula = Formula.isFormula(raw)
                            let value = eval.value(row: r, col: c)
                            let isError: Bool = { if case .error = value { return true } else { return false } }()
                            Text(isFormula ? value.display : raw)
                                .font(isFormula ? Fonts.mono(size, r == 0 ? .semibold : .regular)
                                      : Fonts.block(block.font, size: size, bold: r == 0 || block.bold, italic: block.italic))
                                .foregroundStyle(isError ? p.overdue : p.ink)
                                .lineLimit(1)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .frame(width: CGFloat(c < widths.count ? widths[c] : TableLayout.minColumn),
                                       alignment: isFormula ? .trailing : .leading)
                                .background(r == 0 ? p.chrome : p.cell)
                                .overlay(alignment: .bottom) { Rectangle().fill(r == 0 ? p.rule : p.hairline).frame(height: 1) }
                                .overlay(alignment: .trailing) { if c < cols - 1 { Rectangle().fill(p.hairline).frame(width: 1) } }
                        }
                    }
                }
            }
            .overlay(Rectangle().stroke(p.rule, lineWidth: 1))
        }
    }
}

/// The to-do column, read-only: what's left, what's done, what's deferred.
private struct MonitorTodos: View {
    @Environment(\.palette) var p
    let pad: Pad
    let metrics: MonitorMetrics

    var body: some View {
        let rows = pad.todos.filter(\.isFilled)
        VStack(alignment: .leading, spacing: metrics.text * 0.6) {
            HStack(alignment: .firstTextBaseline) {
                Text("To-do").font(Fonts.ui(metrics.text, .semibold)).foregroundStyle(p.ink)
                Spacer(minLength: 0)
                if !rows.isEmpty {
                    Text(pad.countLabel).font(Fonts.ui(metrics.text * 0.75)).foregroundStyle(p.muted)
                }
            }
            Rectangle().fill(p.hairline).frame(height: 1)
            if rows.isEmpty {
                Text("Nothing yet").font(Fonts.ui(metrics.text * 0.85)).foregroundStyle(p.muted)
            }
            ForEach(rows) { todo in
                HStack(alignment: .firstTextBaseline, spacing: metrics.text * 0.5) {
                    Image(systemName: glyph(todo.status))
                        .foregroundStyle(todo.status == .done ? p.accent : p.muted)
                    Text(todo.text)
                        .strikethrough(todo.status == .done, color: p.muted)
                        .foregroundStyle(todo.status == .open ? p.ink : p.muted)
                        .lineLimit(3)
                }
                .font(Fonts.ui(metrics.text * 0.9))
            }
            Spacer(minLength: 0)
        }
        .padding(metrics.text)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(p.paper, in: RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 2)
    }

    private func glyph(_ s: TodoStatus) -> String {
        switch s {
        case .open: return "circle"
        case .done: return "checkmark.circle.fill"
        case .deferred: return "arrow.right.circle"
        }
    }
}
#endif
