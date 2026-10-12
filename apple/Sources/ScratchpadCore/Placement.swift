import Foundation

/// Turns a paste result into a block at a grid point, storing any bytes through the store.
public enum Placement {
    public static let defaultWidth = 408

    public static func block(from result: PasteResult, at point: (x: Int, y: Int), store: PadStore?) throws -> Block {
        var b: Block
        switch result {
        case .text(let s): b = Block(kind: .text, x: point.x, y: point.y, w: defaultWidth, text: s)
        case .code(let s, let lang): b = Block(kind: .code, x: point.x, y: point.y, w: defaultWidth, text: s, language: lang)
        case .link(let url, let title): b = Block(kind: .link, x: point.x, y: point.y, w: 300, text: title ?? url, url: url)
        case .table(let rows): b = Block(kind: .table, x: point.x, y: point.y, w: min(720, 120 * max(2, rows[0].count) + 24), rows: rows)
        case .image(let data, let ext):
            let asset = try store?.storeAsset(data, ext: ext) ?? ""
            b = Block(kind: .image, x: point.x, y: point.y, w: 300, asset: asset)
        case .file(let url):
            let asset = try store?.copyAsset(from: url) ?? url.path
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            b = Block(kind: .file, x: point.x, y: point.y, w: 300, asset: asset, name: url.lastPathComponent, size: size)
        }
        b.snap()
        return b
    }

    /// First free grid point below everything on the pad, in the left column.
    public static func nextFreePoint(on pad: Pad) -> (x: Int, y: Int) {
        let bottom = pad.blocks.map { $0.y + ($0.h ?? 120) }.max() ?? 0
        return (gridSize, Block.snapped(bottom + gridSize))
    }
}
