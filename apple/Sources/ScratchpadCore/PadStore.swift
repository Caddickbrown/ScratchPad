import Foundation

/// File-backed store: <root>/pads/<id>.json and <root>/assets/<uuid>.<ext>.
/// Same layout as the Linux store, so a synced folder works across both.
public final class PadStore: @unchecked Sendable {
    public let root: URL
    private let queue = DispatchQueue(label: "scratchpad.store")

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root.appendingPathComponent("pads"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
    }

    /// Default location: Application Support/Scratchpad. Replace with the iCloud container for sync.
    public static func defaultRoot() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("Scratchpad", isDirectory: true)
    }

    private func padURL(_ id: String) -> URL { root.appendingPathComponent("pads/\(id).json") }

    public func list() throws -> [Pad] {
        let dir = root.appendingPathComponent("pads")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        return files.filter { $0.pathExtension == "json" }.compactMap { try? PadJSON.decoder.decode(Pad.self, from: Data(contentsOf: $0)) }
            .sorted { ($0.date ?? "") > ($1.date ?? "") }
    }

    public func load(_ id: String) throws -> Pad? {
        let url = padURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try PadJSON.decoder.decode(Pad.self, from: Data(contentsOf: url))
    }

    public func save(_ pad: Pad) throws {
        var p = pad
        p.updatedAt = Date()
        let data = try PadJSON.encoder.encode(p)
        try queue.sync { try data.write(to: padURL(p.id), options: .atomic) }
    }

    public func delete(_ id: String) throws {
        try FileManager.default.removeItem(at: padURL(id))
    }

    /// Today's pad, created with rollover from the latest earlier dated pad when it does not exist yet.
    public func today(now: Date = Date()) throws -> Pad {
        let key = DayKey.key(for: now)
        if let existing = try load(key) { return existing }
        var pad = Pad.daily(key, now: now)
        if let prev = Rollover.source(for: key, among: try list()) {
            pad = Rollover.carried(from: prev, into: pad)
        }
        try save(pad)
        return pad
    }

    /// Writes bytes into assets/ and returns the store-relative path to put in a block.
    public func storeAsset(_ data: Data, ext: String) throws -> String {
        let name = "assets/\(UUID().uuidString.lowercased()).\(ext.isEmpty ? "bin" : ext)"
        try data.write(to: root.appendingPathComponent(name), options: .atomic)
        return name
    }

    public func copyAsset(from url: URL) throws -> String {
        try storeAsset(Data(contentsOf: url), ext: url.pathExtension)
    }

    public func assetURL(_ rel: String) -> URL { root.appendingPathComponent(rel) }
}
