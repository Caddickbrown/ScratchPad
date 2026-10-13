import SwiftUI
import ScratchpadCore

struct BlockView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    let block: Block
    var selected: Bool = false

    private var binding: Binding<Block> {
        Binding(get: { state.current?.blocks.first { $0.id == block.id } ?? block }, set: { state.update($0) })
    }

    var body: some View {
        switch block.kind {
        case .text: TextBlock(block: binding)
        case .code: CodeBlock(block: binding)
        case .table: TableBlock(block: binding, selected: selected)
        case .image: ImageBlock(block: block)
        case .file: FileBlock(block: block)
        case .link: LinkBlock(block: binding)
        case .divider: Rectangle().fill(p.rule).frame(height: 1).padding(.vertical, 11)
        }
    }
}

struct TextBlock: View {
    @Environment(\.palette) var p
    @Binding var block: Block
    var body: some View {
        TextEditor(text: Binding(get: { block.text ?? "" }, set: { block.text = $0 }))
            .font(Fonts.block(block)).foregroundStyle(p.ink)
            .scrollContentBackground(.hidden).scrollDisabled(true)
            .frame(minHeight: 40)
            .padding(.horizontal, 8).padding(.vertical, 4)
    }
}

struct CodeBlock: View {
    @Environment(\.palette) var p
    @Binding var block: Block
    var body: some View {
        TextEditor(text: Binding(get: { block.text ?? "" }, set: { block.text = $0 }))
            .font(Fonts.block(block.font == .sans ? .mono : block.font, size: CGFloat(block.fontSize) - 2, bold: block.bold, italic: block.italic))
            .foregroundStyle(p.codeInk)
            .scrollContentBackground(.hidden).scrollDisabled(true)
            .frame(minHeight: 40)
            .padding(8)
            .background(p.codeBg, in: RoundedRectangle(cornerRadius: 4))
    }
}

struct CellPos: Hashable {
    var r: Int
    var c: Int
}

/// Table with per-column widths, formulas, and (while selected) column letters, row numbers and a formula bar.
struct TableBlock: View {
    @Environment(\.palette) var p
    @Environment(\.motion) var motion
    @Binding var block: Block
    let selected: Bool
    @FocusState private var focused: CellPos?
    @State private var lastFocused: CellPos?
    @State private var liveWidths: [Int]?

    private static let gutter: CGFloat = 26
    private static let letterRow: CGFloat = 18

    private var rows: [[String]] { block.rows ?? [[""]] }
    private var cols: Int { max(1, rows.map(\.count).max() ?? 1) }
    private var widths: [Int] { liveWidths ?? TableLayout.widths(for: block) }

    var body: some View {
        let eval = TableEvaluator(rows: rows)
        VStack(alignment: .leading, spacing: 6) {
            if let caption = block.caption, !caption.isEmpty {
                Text(caption).font(Fonts.ui(12, .semibold)).foregroundStyle(p.muted).padding(.leading, 4)
            }
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<cols, id: \.self) { c in
                            cell(r, c, eval: eval)
                        }
                    }
                }
            }
            .overlay(Rectangle().stroke(p.rule, lineWidth: 1))
            .overlay(alignment: .topLeading) { if selected { letters.offset(y: -Self.letterRow - 2) } }
            .overlay(alignment: .topLeading) { if selected { rowNumbers.offset(x: -Self.gutter - 2) } }
            .overlay(alignment: .topLeading) { if selected { formulaBar(eval).offset(y: -Self.letterRow - 34) } }
            .contextMenu {
                Button("Add row") { block.rows = rows + [Array(repeating: "", count: cols)] }
                Button("Add column") { addColumn() }
                Button("Remove last row") { if rows.count > 1 { block.rows = Array(rows.dropLast()) } }
                Button("Remove last column") { removeColumn() }
            }
        }
        .onChange(of: focused) { _, f in if let f { lastFocused = f } }
    }

    // MARK: Cells

    @ViewBuilder
    private func cell(_ r: Int, _ c: Int, eval: TableEvaluator) -> some View {
        let raw = r < rows.count && c < rows[r].count ? rows[r][c] : ""
        let pos = CellPos(r: r, c: c)
        let isFormula = Formula.isFormula(raw)
        let showComputed = isFormula && focused != pos
        let value = eval.value(row: r, col: c)
        let isError: Bool = { if case .error = value { return true } else { return false } }()
        ZStack(alignment: showComputed ? .trailing : .leading) {
            TextField("", text: cellBinding(r, c))
                .textFieldStyle(.plain)
                .font(cellFont(header: r == 0, mono: isFormula))
                .foregroundStyle(p.ink)
                .focused($focused, equals: pos)
                .opacity(showComputed ? 0 : 1)
            if showComputed {
                Text(value.display)
                    .font(Fonts.mono(CGFloat(max(10, block.fontSize - 1)), r == 0 ? .semibold : .regular))
                    .foregroundStyle(isError ? p.overdue : p.ink)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(width: CGFloat(c < widths.count ? widths[c] : TableLayout.minColumn), alignment: showComputed ? .trailing : .leading)
        .background(r == 0 ? p.chrome : p.cell)
        .overlay(alignment: .bottom) { Rectangle().fill(r == 0 ? p.rule : p.hairline).frame(height: 1) }
        .overlay(alignment: .trailing) { if c < cols - 1 { Rectangle().fill(p.hairline).frame(width: 1) } }
        .overlay { if focused == pos { Rectangle().stroke(p.accent, lineWidth: 1.5) } }
    }

    private func cellFont(header: Bool, mono: Bool) -> Font {
        let size = CGFloat(max(10, block.fontSize - 1))
        if mono { return Fonts.mono(size, header ? .semibold : .regular) }
        return Fonts.block(block.font, size: size, bold: header || block.bold, italic: block.italic)
    }

    private func cellBinding(_ r: Int, _ c: Int) -> Binding<String> {
        Binding(
            get: { (r < rows.count && c < rows[r].count) ? rows[r][c] : "" },
            set: { v in
                var all = rows
                guard r < all.count else { return }
                while all[r].count <= c { all[r].append("") }
                all[r][c] = v
                block.rows = all
            })
    }

    // MARK: Selected chrome

    private var letters: some View {
        HStack(spacing: 0) {
            ForEach(0..<cols, id: \.self) { c in
                Text(Formula.columnName(c))
                    .font(Fonts.mono(10, .semibold)).foregroundStyle(p.muted)
                    .frame(width: CGFloat(widths[c]), height: Self.letterRow)
                    .overlay(alignment: .trailing) { columnHandle(c) }
            }
        }
    }

    private var rowNumbers: some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { r in
                Text("\(r + 1)")
                    .font(Fonts.mono(10, .semibold)).foregroundStyle(p.muted)
                    .frame(width: Self.gutter)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: Self.gutter)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Drag the boundary right of a column letter (min 40 px); double-click fits it to its content.
    private func columnHandle(_ c: Int) -> some View {
        Rectangle()
            .fill(p.accent.opacity(0.5))
            .frame(width: 2, height: Self.letterRow - 4)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .offset(x: 5)
            #if os(macOS)
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            #endif
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { v in
                        var w = TableLayout.widths(for: block)
                        w[c] = max(TableLayout.minColumn, w[c] + Int(v.translation.width))
                        liveWidths = w
                    }
                    .onEnded { _ in commitWidths(liveWidths) }
            )
            .onTapGesture(count: 2) {
                var w = TableLayout.widths(for: block)
                w[c] = TableLayout.fitWidth(column: c, rows: rows)
                commitWidths(w)
            }
            .accessibilityLabel("Resize column \(Formula.columnName(c))")
    }

    private func commitWidths(_ w: [Int]?) {
        guard let w else { return }
        var b = block
        b.colWidths = w
        b.w = max(Block.minWidth, w.reduce(0, +))
        block = b
        liveWidths = nil
    }

    private func formulaBar(_ eval: TableEvaluator) -> some View {
        let pos = focused ?? lastFocused
        return HStack(spacing: 8) {
            Text(pos.map { Formula.address(row: $0.r, col: $0.c) } ?? "–")
                .font(Fonts.mono(11, .semibold)).foregroundStyle(p.muted)
                .frame(width: 40, alignment: .leading)
            Rectangle().fill(p.hairline).frame(width: 1, height: 14)
            if let pos {
                TextField("Value or =formula", text: cellBinding(pos.r, pos.c))
                    .textFieldStyle(.plain)
                    .font(Fonts.mono(12)).foregroundStyle(p.ink)
            } else {
                Text("Select a cell").font(Fonts.ui(12)).foregroundStyle(p.muted)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: max(200, CGFloat(widths.reduce(0, +))), height: 26, alignment: .leading)
        .background(p.cell, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(p.hairline, lineWidth: 1))
    }

    private func addColumn() {
        let n = cols
        let w = Array(TableLayout.widths(for: block).prefix(n)) + [120]
        var b = block
        b.rows = rows.map { $0 + Array(repeating: "", count: max(0, n - $0.count)) + [""] }
        b.colWidths = w
        b.w = w.reduce(0, +)
        block = b
    }

    private func removeColumn() {
        let n = cols
        guard n > 1 else { return }
        let w = Array(TableLayout.widths(for: block).prefix(n - 1))
        var b = block
        b.rows = rows.map { Array($0.prefix(n - 1)) }
        b.colWidths = w
        b.w = max(Block.minWidth, w.reduce(0, +))
        block = b
    }
}

struct ImageBlock: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    let block: Block
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let asset = block.asset, let img = PlatformImage.load(state.store.assetURL(asset)) {
                img.resizable().aspectRatio(contentMode: block.h == nil ? .fit : .fill).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
                    p.chrome
                    VStack(spacing: 6) {
                        Image(systemName: "photo").font(.system(size: 24))
                        Text(block.asset ?? "[IMAGE]").font(Fonts.mono(11))
                    }.foregroundStyle(p.muted)
                }.frame(minHeight: 120)
            }
            if let c = block.caption, !c.isEmpty { Text(c).font(Fonts.block(block)).foregroundStyle(p.muted) }
        }
    }
}

struct FileBlock: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    let block: Block
    var body: some View {
        Button {
            if let a = block.asset { PlatformOpen.reveal(state.store.assetURL(a)) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc").font(.system(size: 18)).foregroundStyle(p.ink)
                VStack(alignment: .leading, spacing: 1) {
                    Text(block.name ?? "File").font(Fonts.block(block.font, size: CGFloat(block.fontSize), bold: true, italic: block.italic)).foregroundStyle(p.ink).lineLimit(1)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(block.size ?? 0), countStyle: .file)).font(Fonts.mono(11)).foregroundStyle(p.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(p.cell, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(p.rule, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

struct LinkBlock: View {
    @Environment(\.palette) var p
    @Environment(\.openURL) var openURL
    @Binding var block: Block
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField("Title", text: Binding(get: { block.text ?? "" }, set: { block.text = $0 }))
                .textFieldStyle(.plain).font(Fonts.block(block.font, size: CGFloat(block.fontSize), bold: true, italic: block.italic)).foregroundStyle(p.ink)
            HStack {
                TextField("https://", text: Binding(get: { block.url ?? "" }, set: { block.url = $0 }))
                    .textFieldStyle(.plain).font(Fonts.mono(11)).foregroundStyle(p.muted)
                Button { if let u = URL(string: block.url ?? "") { openURL(u) } } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.plain).foregroundStyle(p.accent).accessibilityLabel("Open link")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(p.cell, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(p.rule, lineWidth: 1))
    }
}

@MainActor
enum PlatformImage {
    static func load(_ url: URL) -> Image? {
        #if os(macOS)
        guard let img = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: img)
        #else
        guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else { return nil }
        return Image(uiImage: img)
        #endif
    }
}

@MainActor
enum PlatformOpen {
    static func reveal(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #else
        UIApplication.shared.open(url)
        #endif
    }
}
