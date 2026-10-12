import SwiftUI
import ScratchpadCore

struct BlockView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    let block: Block

    private var binding: Binding<Block> {
        Binding(get: { state.current?.blocks.first { $0.id == block.id } ?? block }, set: { state.update($0) })
    }

    var body: some View {
        switch block.kind {
        case .text: TextBlock(block: binding)
        case .code: CodeBlock(block: binding)
        case .table: TableBlock(block: binding)
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
            .font(Fonts.ui(14)).foregroundStyle(p.ink)
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
            .font(Fonts.mono(12)).foregroundStyle(p.codeInk)
            .scrollContentBackground(.hidden).scrollDisabled(true)
            .frame(minHeight: 40)
            .padding(8)
            .background(p.codeBg, in: RoundedRectangle(cornerRadius: 4))
    }
}

struct TableBlock: View {
    @Environment(\.palette) var p
    @Binding var block: Block

    private var rows: [[String]] { block.rows ?? [[""]] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let caption = block.caption, !caption.isEmpty {
                Text(caption).font(Fonts.ui(12, .semibold)).foregroundStyle(p.muted).padding(.leading, 4)
            }
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(rows.indices, id: \.self) { r in
                    GridRow {
                        ForEach(rows[r].indices, id: \.self) { c in
                            TextField("", text: cell(r, c))
                                .textFieldStyle(.plain)
                                .font(Fonts.ui(13, r == 0 ? .semibold : .regular)).foregroundStyle(p.ink)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(r == 0 ? p.chrome : p.cell)
                                .overlay(alignment: .bottom) { Rectangle().fill(r == 0 ? p.rule : p.hairline).frame(height: 1) }
                                .overlay(alignment: .trailing) { if c < rows[r].count - 1 { Rectangle().fill(p.hairline).frame(width: 1) } }
                        }
                    }
                }
            }
            .overlay(Rectangle().stroke(p.rule, lineWidth: 1))
            .contextMenu {
                Button("Add row") { block.rows?.append(Array(repeating: "", count: rows[0].count)) }
                Button("Add column") { block.rows = rows.map { $0 + [""] } }
                Button("Remove last row") { if rows.count > 1 { block.rows?.removeLast() } }
                Button("Remove last column") { if rows[0].count > 1 { block.rows = rows.map { Array($0.dropLast()) } } }
            }
        }
    }

    private func cell(_ r: Int, _ c: Int) -> Binding<String> {
        Binding(get: { block.rows?[r][c] ?? "" }, set: { block.rows?[r][c] = $0 })
    }
}

struct ImageBlock: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    let block: Block
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let asset = block.asset, let img = PlatformImage.load(state.store.assetURL(asset)) {
                img.resizable().aspectRatio(contentMode: .fit).frame(width: CGFloat(block.w))
            } else {
                ZStack {
                    p.chrome
                    VStack(spacing: 6) {
                        Image(systemName: "photo").font(.system(size: 24))
                        Text(block.asset ?? "[IMAGE]").font(Fonts.mono(11))
                    }.foregroundStyle(p.muted)
                }.frame(height: 180)
            }
            if let c = block.caption, !c.isEmpty { Text(c).font(Fonts.ui(12)).foregroundStyle(p.muted) }
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
                    Text(block.name ?? "File").font(Fonts.ui(14, .medium)).foregroundStyle(p.ink).lineLimit(1)
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
                .textFieldStyle(.plain).font(Fonts.ui(14, .medium)).foregroundStyle(p.ink)
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

enum PlatformOpen {
    static func reveal(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #else
        UIApplication.shared.open(url)
        #endif
    }
}
