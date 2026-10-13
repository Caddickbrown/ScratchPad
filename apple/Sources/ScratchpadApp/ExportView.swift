import SwiftUI
import UniformTypeIdentifiers
import ScratchpadCore

enum ExportTypes {
    static let archive = UTType(filenameExtension: "scratchpad", conformingTo: .json) ?? .json
    static let markdown = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
}

/// Bytes handed to fileExporter.
struct DataDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.png, .json, .plainText, .data, ExportTypes.archive, ExportTypes.markdown]
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

enum ExportMode: String, CaseIterable, Identifiable {
    case image, todos, everything
    var id: String { rawValue }
    var label: String {
        switch self { case .image: return "Sheet as image"; case .todos: return "To-dos as Markdown"; case .everything: return "Everything" }
    }
}

enum ImageTheme: String, CaseIterable, Identifiable {
    case light, dark, match
    var id: String { rawValue }
    var label: String { self == .match ? "Match app" : rawValue.capitalized }
}

enum EverythingScope: String, CaseIterable, Identifiable {
    case all, tag
    var id: String { rawValue }
    var label: String { self == .all ? "All sheets" : "One tag" }
}

/// One dialog, three modes (spec section 6).
struct ExportView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.palette) var p
    @Environment(\.colorScheme) var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var mode: ExportMode = .image

    // Image
    @State private var theme: ImageTheme = .match
    @State private var scale = 2
    @State private var includeTodos = true
    @State private var preview: PlatformPNG?

    // To-dos
    @State private var todoScope: TodoExportScope = .thisSheet
    @State private var includeDone = false
    @State private var includeDeferred = true

    // Everything
    @State private var format: EverythingFormat = .archive
    @State private var everythingScope: EverythingScope = .all
    @State private var tag = ""

    // Saving
    @State private var exporting = false
    @State private var document = DataDocument(data: Data())
    @State private var exportType: UTType = .png
    @State private var exportName = "Scratchpad"
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Export").font(Fonts.ui(16, .semibold)).foregroundStyle(p.ink)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Picker("Mode", selection: $mode) {
                ForEach(ExportMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Group {
                switch mode {
                case .image: imagePane
                case .todos: todosPane
                case .everything: everythingPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 520)
        .background(p.paper)
        .popIn()
        .fileExporter(isPresented: $exporting, document: document, contentType: exportType, defaultFilename: exportName) { result in
            if case .failure(let e) = result { state.error = e.localizedDescription }
        }
        .onAppear {
            if tag.isEmpty { tag = state.current?.tags.first ?? Tags.counts(state.pads).first?.tag ?? "" }
        }
    }

    private var sheetName: String {
        guard let pad = state.current else { return "Sheet" }
        let base = pad.title.isEmpty ? (pad.date ?? pad.id) : pad.title
        return base.replacingOccurrences(of: "/", with: "-")
    }

    // MARK: Image

    private var resolvedScheme: ColorScheme {
        switch theme { case .light: return .light; case .dark: return .dark; case .match: return scheme }
    }

    private var imagePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Theme", selection: $theme) { ForEach(ImageTheme.allCases) { Text($0.label).tag($0) } }
            Picker("Scale", selection: $scale) { ForEach(1...3, id: \.self) { Text("\($0)x").tag($0) } }.pickerStyle(.segmented)
            Toggle("Include to-do column", isOn: $includeTodos)
            ZStack {
                p.chrome
                if let preview { preview.image.resizable().aspectRatio(contentMode: .fit).padding(8) }
                else { ProgressView() }
            }
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 300)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack {
                Button(copied ? "Copied" : "Copy") {
                    if let png = renderPNG() { Clipboard.copyImage(png) ; flashCopied() }
                }
                Button("Save…") {
                    guard let png = renderPNG()?.data else { return }
                    save(png, type: .png, name: sheetName)
                }
                .keyboardShortcut(.defaultAction)
                if let preview {
                    ShareLink(item: preview.image, preview: SharePreview(sheetName, image: preview.image))
                }
            }
        }
        .onAppear(perform: refreshPreview)
        .onChange(of: theme) { _, _ in refreshPreview() }
        .onChange(of: includeTodos) { _, _ in refreshPreview() }
    }

    private func refreshPreview() { preview = render(scale: 1) }

    private func renderPNG() -> PlatformPNG? { render(scale: CGFloat(scale)) }

    private func render(scale: CGFloat) -> PlatformPNG? {
        guard let pad = state.current else { return nil }
        let pal = Palette.forScheme(resolvedScheme)
        let view = SheetSnapshot(pad: pad, includeTodos: includeTodos, store: state.store)
            .environment(\.palette, pal)
            .environment(\.colorScheme, resolvedScheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let cg = renderer.cgImage else { return nil }
        return PlatformPNG(cgImage: cg)
    }

    // MARK: To-dos

    private var todoMarkdown: String {
        let sheets = todoScope.sheets(current: state.current, all: state.pads.map { $0.id == state.current?.id ? state.current! : $0 }, today: state.todayKey)
        return ExportMarkdown.todos(sheets, includeDone: includeDone, includeDeferred: includeDeferred, openOnly: todoScope == .everyOpen)
    }

    private var todosPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Scope", selection: $todoScope) { ForEach(TodoExportScope.allCases) { Text($0.label).tag($0) } }
            Toggle("Include done", isOn: $includeDone).disabled(todoScope == .everyOpen)
            Toggle("Include deferred", isOn: $includeDeferred)
            ScrollView {
                Text(todoMarkdown).font(Fonts.mono(12)).foregroundStyle(p.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 280)
            .background(p.cell, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(p.hairline, lineWidth: 1))
            HStack {
                Button(copied ? "Copied" : "Copy") { Clipboard.copyText(todoMarkdown); flashCopied() }
                Button("Save .md…") { save(Data(todoMarkdown.utf8), type: ExportTypes.markdown, name: "\(sheetName) to-dos") }
                    .keyboardShortcut(.defaultAction)
                ShareLink(item: todoMarkdown)
            }
        }
    }

    // MARK: Everything

    private var everythingSheets: [Pad] {
        let all = state.pads.map { $0.id == state.current?.id ? state.current! : $0 }
        return everythingScope == .all ? all : all.filter { $0.tags.contains(tag) }
    }

    private var everythingPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Format", selection: $format) {
                ForEach(EverythingFormat.allCases) { f in Text("\(f.label) (.\(f.fileExtension))").tag(f) }
            }
            Picker("Scope", selection: $everythingScope) { ForEach(EverythingScope.allCases) { Text($0.label).tag($0) } }
                .pickerStyle(.segmented)
            if everythingScope == .tag {
                Picker("Tag", selection: $tag) {
                    ForEach(Tags.counts(state.pads), id: \.tag) { t in Text("#\(t.tag) (\(t.count))").tag(t.tag) }
                }
            }
            Text("\(everythingSheets.count) sheet\(everythingSheets.count == 1 ? "" : "s")").font(Fonts.ui(12)).foregroundStyle(p.muted)
            Divider()
            HStack {
                Button("Import archive…") { dismiss(); state.showImport = true }
                Spacer()
                Button("Save…") { saveEverything() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(everythingSheets.isEmpty)
            }
        }
    }

    private func saveEverything() {
        let sheets = everythingSheets
        let name = everythingScope == .tag && !tag.isEmpty ? "Scratchpad #\(tag)" : "Scratchpad"
        do {
            switch format {
            case .archive:
                save(try ScratchpadArchive.build(sheets: sheets, store: state.store).encoded(), type: ExportTypes.archive, name: name)
            case .markdown:
                save(Data(ExportMarkdown.everything(sheets).utf8), type: ExportTypes.markdown, name: name)
            case .json:
                save(try ExportJSON.sheets(sheets), type: .json, name: name)
            }
        } catch { state.error = error.localizedDescription }
    }

    // MARK: Helpers

    private func save(_ data: Data, type: UTType, name: String) {
        document = DataDocument(data: data)
        exportType = type
        exportName = name
        exporting = true
    }

    private func flashCopied() {
        copied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            copied = false
        }
    }
}

/// A rendered PNG plus a SwiftUI image for previews and the share sheet.
struct PlatformPNG {
    let cgImage: CGImage
    var image: Image {
        #if os(macOS)
        return Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
        #else
        return Image(uiImage: UIImage(cgImage: cgImage))
        #endif
    }
    var data: Data? {
        #if os(macOS)
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        #else
        return UIImage(cgImage: cgImage).pngData()
        #endif
    }
}

@MainActor
enum Clipboard {
    static func copyText(_ s: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        #else
        UIPasteboard.general.string = s
        #endif
    }

    static func copyImage(_ png: PlatformPNG) {
        #if os(macOS)
        guard let data = png.data else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: .png)
        #else
        UIPasteboard.general.image = UIImage(cgImage: png.cgImage)
        #endif
    }
}

/// Static rendering of a sheet for ImageRenderer: header, the canvas bounding box, optionally the to-do column.
/// No selection chrome and no text fields (ImageRenderer cannot draw platform text views).
struct SheetSnapshot: View {
    @Environment(\.palette) var p
    let pad: Pad
    let includeTodos: Bool
    let store: PadStore

    private static let margin: CGFloat = 24

    private var origin: CGPoint {
        CGPoint(x: CGFloat(pad.blocks.map(\.x).min() ?? 0), y: CGFloat(pad.blocks.map(\.y).min() ?? 0))
    }

    private func estimatedHeight(_ b: Block) -> CGFloat {
        if let h = b.h { return CGFloat(h) }
        switch b.kind {
        case .table: return CGFloat((b.rows?.count ?? 1) * 30 + ((b.caption ?? "").isEmpty ? 0 : 22))
        case .divider: return 24
        case .image: return 220
        case .file, .link: return 56
        case .text, .code:
            let chars = Double(b.w) / (Double(b.fontSize) * 0.55)
            let lines = (b.text ?? "").split(separator: "\n", omittingEmptySubsequences: false)
                .map { max(1, Int((Double($0.count) / max(1, chars)).rounded(.up))) }.reduce(0, +)
            return CGFloat(max(1, lines)) * CGFloat(b.fontSize) * 1.4 + 16
        }
    }

    private var canvasSize: CGSize {
        let maxX = pad.blocks.map { CGFloat($0.x + $0.w) }.max() ?? 400
        let maxY = pad.blocks.map { CGFloat($0.y) + estimatedHeight($0) }.max() ?? 200
        return CGSize(width: max(400, maxX - origin.x + 2 * Self.margin), height: max(160, maxY - origin.y + 2 * Self.margin))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                header
                ZStack(alignment: .topLeading) {
                    DotGrid(color: p.dot)
                    ForEach(pad.blocks) { b in
                        StaticBlock(block: b, store: store)
                            .frame(width: CGFloat(b.w), height: b.h.map { CGFloat($0) }, alignment: .topLeading)
                            .rotationEffect(.degrees(b.rotation))
                            .offset(x: CGFloat(b.x) - origin.x + Self.margin, y: CGFloat(b.y) - origin.y + Self.margin)
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
                .clipped()
            }
            .padding(20)
            if includeTodos {
                Rectangle().fill(p.hairline).frame(width: 1)
                todos.frame(width: 300).padding(20)
            }
        }
        .fixedSize()
        .background(p.paper)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("DATE").font(Fonts.ui(10, .semibold)).tracking(1).foregroundStyle(p.muted)
            Text(DayLabel.longDate(pad.date)).font(Fonts.mono(13)).foregroundStyle(p.ink)
            Rectangle().fill(p.rule).frame(width: 1, height: 20)
            Text(pad.displayTitle).font(Fonts.ui(15, .medium)).foregroundStyle(pad.title.isEmpty ? p.muted : p.ink)
            Spacer(minLength: 12)
            Text(pad.tags.map { "#\($0)" }.joined(separator: " ")).font(Fonts.mono(12)).foregroundStyle(p.muted)
        }
        .padding(.horizontal, 12).frame(height: 34)
        .overlay(Rectangle().stroke(p.rule, lineWidth: 1))
    }

    private var todos: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("To-do").font(Fonts.ui(14, .medium)).foregroundStyle(p.ink)
                Spacer()
                Text(pad.countLabel).font(Fonts.mono(12)).foregroundStyle(p.muted)
            }
            .padding(.horizontal, 12).frame(height: 34)
            .overlay(Rectangle().stroke(p.rule, lineWidth: 1))
            ForEach(pad.todos.filter(\.isFilled)) { t in
                HStack(spacing: 8) {
                    ZStack {
                        Circle().stroke(t.status == .done ? p.accent : p.rule, lineWidth: 1.5)
                        if t.status == .done {
                            Circle().fill(p.accent)
                            TickShape().foregroundStyle(p.accentInk)
                        }
                        if t.status == .deferred {
                            Path { $0.move(to: CGPoint(x: 13, y: 5)); $0.addLine(to: CGPoint(x: 5, y: 13)) }.stroke(p.rule, lineWidth: 1.5)
                        }
                    }
                    .frame(width: 18, height: 18)
                    Text(t.text).font(Fonts.ui(13))
                        .foregroundStyle(t.status != .open ? p.rule : (t.isOverdue() ? p.overdue : p.ink))
                        .strikethrough(t.status == .done, color: p.rule)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) { Rectangle().fill(p.hairline).frame(height: 1) }
            }
            Text(pad.footerLabel).font(Fonts.ui(12)).foregroundStyle(p.muted).padding(.top, 4)
        }
    }
}

/// Non-editable block rendering for the PNG export.
struct StaticBlock: View {
    @Environment(\.palette) var p
    let block: Block
    let store: PadStore

    var body: some View {
        switch block.kind {
        case .text:
            Text(block.text ?? "").font(Fonts.block(block)).foregroundStyle(p.ink)
                .padding(.horizontal, 13).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .code:
            Text(block.text ?? "").font(Fonts.block(block.font == .sans ? .mono : block.font, size: CGFloat(block.fontSize) - 2))
                .foregroundStyle(p.codeInk)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(p.codeBg, in: RoundedRectangle(cornerRadius: 4))
        case .table: table
        case .image:
            if let asset = block.asset, let img = PlatformImage.load(store.assetURL(asset)) {
                img.resizable().aspectRatio(contentMode: .fit)
            } else {
                p.chrome.frame(height: 120)
            }
        case .file:
            HStack(spacing: 10) {
                Image(systemName: "doc").foregroundStyle(p.ink)
                VStack(alignment: .leading, spacing: 1) {
                    Text(block.name ?? "File").font(Fonts.ui(14, .medium)).foregroundStyle(p.ink)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(block.size ?? 0), countStyle: .file)).font(Fonts.mono(11)).foregroundStyle(p.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(p.cell, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(p.rule, lineWidth: 1))
        case .link:
            VStack(alignment: .leading, spacing: 2) {
                Text((block.text ?? "").isEmpty ? (block.url ?? "") : block.text!).font(Fonts.ui(14, .medium)).foregroundStyle(p.ink)
                Text(block.url ?? "").font(Fonts.mono(11)).foregroundStyle(p.muted)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.cell, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(p.rule, lineWidth: 1))
        case .divider:
            Rectangle().fill(p.rule).frame(height: 1).padding(.vertical, 11)
        }
    }

    private var table: some View {
        let rows = block.rows ?? [[""]]
        let eval = TableEvaluator(rows: rows)
        let widths = TableLayout.widths(for: block)
        return VStack(alignment: .leading, spacing: 6) {
            if let c = block.caption, !c.isEmpty { Text(c).font(Fonts.ui(12, .semibold)).foregroundStyle(p.muted) }
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<widths.count, id: \.self) { c in
                            let raw = c < rows[r].count ? rows[r][c] : ""
                            let formula = Formula.isFormula(raw)
                            Text(eval.display(row: r, col: c))
                                .font(formula ? Fonts.mono(13) : Fonts.ui(13, r == 0 ? .semibold : .regular))
                                .foregroundStyle(p.ink)
                                .lineLimit(1)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .frame(width: CGFloat(widths[c]), alignment: formula ? .trailing : .leading)
                                .background(r == 0 ? p.chrome : p.cell)
                                .overlay(alignment: .bottom) { Rectangle().fill(r == 0 ? p.rule : p.hairline).frame(height: 1) }
                        }
                    }
                }
            }
            .overlay(Rectangle().stroke(p.rule, lineWidth: 1))
        }
    }
}
