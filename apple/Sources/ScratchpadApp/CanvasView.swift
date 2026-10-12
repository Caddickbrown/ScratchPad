import SwiftUI
import ScratchpadCore

/// The dot grid. Blocks sit at absolute grid points; drag moves them, a tap on the dots deselects,
/// a double tap on the dots starts a text block there.
struct CanvasView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p

    private var contentHeight: CGFloat {
        CGFloat((state.current?.blocks.map { $0.y + ($0.h ?? 240) }.max() ?? 0) + 480)
    }

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            ZStack(alignment: .topLeading) {
                DotGrid(color: p.dot)
                    .frame(minWidth: 900, minHeight: max(720, contentHeight))
                    .contentShape(Rectangle())
                    .onTapGesture { state.selectedBlockID = nil }
                    .onTapGesture(count: 2) { location in state.insert(.text, at: location) }
                    .contextMenu {
                        ForEach([BlockKind.text, .table, .code, .link, .divider], id: \.self) { k in
                            Button("Insert \(k.rawValue)") { state.insert(k) }
                        }
                        Button("Paste as block") { state.paste(PasteBridge.read()) }
                    }
                ForEach(state.current?.blocks ?? []) { block in
                    DraggableBlock(block: block)
                }
            }
        }
        .dropDestination(for: String.self) { items, location in
            guard let id = items.compactMap(TodoDrag.id).first else { return false }
            state.todoToBlock(id, at: location)
            return true
        }
        #if os(macOS)
        .onPasteCommand(of: PasteBridge.readableTypes) { providers in
            PasteBridge.read(providers: providers) { contents in state.paste(contents) }
        }
        .onDrop(of: PasteBridge.readableTypes, isTargeted: nil) { providers, location in
            PasteBridge.read(providers: providers) { contents in state.paste(contents, at: location) }
            return true
        }
        #endif
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

struct DraggableBlock: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    let block: Block
    @GestureState private var drag: CGSize = .zero
    @GestureState private var stretch: CGFloat = 0

    private var selected: Bool { state.selectedBlockID == block.id }

    private var handle: some View {
        Rectangle().fill(p.cell).frame(width: 8, height: 8).overlay(Rectangle().stroke(p.accent, lineWidth: 1.5)).allowsHitTesting(false)
    }

    var body: some View {
        BlockView(block: block)
            .frame(width: CGFloat(block.w) + stretch, alignment: .topLeading)
            .overlay { if selected { Rectangle().stroke(p.accent, lineWidth: 2).padding(-3).allowsHitTesting(false) } }
            .overlay(alignment: .topLeading) { if selected { handle.offset(x: -7, y: -7) } }
            .overlay(alignment: .topTrailing) { if selected { handle.offset(x: 7, y: -7) } }
            .overlay(alignment: .bottomLeading) { if selected { handle.offset(x: -7, y: 7) } }
            .overlay(alignment: .bottomTrailing) { if selected { handle.offset(x: 7, y: 7) } }
            .overlay(alignment: .trailing) {
                // Right-edge resize strip; corners on the design are drawn above, the strip is the live target.
                Color.clear.frame(width: 12).contentShape(Rectangle())
                    .gesture(DragGesture().updating($stretch) { v, s, _ in s = v.translation.width }
                        .onEnded { v in state.resize(block.id, width: CGFloat(block.w) + v.translation.width) })
                    #if os(macOS)
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    #endif
            }
            .offset(x: CGFloat(block.x) + drag.width, y: CGFloat(block.y) + drag.height)
            .onTapGesture { state.selectedBlockID = block.id }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .updating($drag) { v, s, _ in s = v.translation }
                    .onEnded { v in state.move(block.id, to: CGPoint(x: CGFloat(block.x) + v.translation.width, y: CGFloat(block.y) + v.translation.height)) }
            )
            .contextMenu {
                Button("Delete block", role: .destructive) { state.deleteBlock(block.id) }
            }
            .zIndex(selected ? 1 : 0)
    }
}
