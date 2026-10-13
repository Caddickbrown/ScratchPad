import Foundation

/// File-backed store: <root>/pads/<id>.json and <root>/assets/<uuid>.<ext>.
/// Same layout as the Linux store, so a synced folder works across both.
public final class PadStore: @unchecked Sendable {
    public enum StoreError: Error, LocalizedError {
        case invalidID(String)
        public var errorDescription: String? {
            switch self { case .invalidID(let id): return "Not a valid sheet id: \(id)" }
        }
    }

    public let root: URL
    private let queue = DispatchQueue(label: "scratchpad.store")

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root.appendingPathComponent("pads"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
    }

    /// Local location: Application Support/Scratchpad.
    public static func defaultRoot() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("Scratchpad", isDirectory: true)
    }

    /// iCloud Drive location when the app has the container entitlement and the user is signed in, else nil.
    /// Slow: call off the main thread. Pads/ and assets/ live under Documents so they show in Files.
    public static func iCloudRoot() -> URL? {
        #if canImport(Darwin)
        return FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents/Scratchpad", isDirectory: true)
        #else
        return nil
        #endif
    }

    private func padURL(_ id: String) -> URL { root.appendingPathComponent("pads/\(id).json") }

    /// Every sheet, newest date first (pinned last), then most recently updated.
    public func list() throws -> [Pad] {
        let dir = root.appendingPathComponent("pads")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? PadJSON.decoder.decode(Pad.self, from: Data(contentsOf: $0)) }
            .sorted(by: PadStore.newestFirst)
    }

    /// Dated sheets by date descending, pinned after, ties by updatedAt descending.
    public static func newestFirst(_ a: Pad, _ b: Pad) -> Bool {
        let da = a.date ?? "", db = b.date ?? ""
        if da != db { return da > db }
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        return a.id < b.id
    }

    public func load(_ id: String) throws -> Pad? {
        guard SheetID.isValid(id) else { return nil }
        let url = padURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try PadJSON.decoder.decode(Pad.self, from: Data(contentsOf: url))
    }

    /// Writes v2 JSON. `touch` stamps updatedAt (off for imports, which keep their times). Empty to-do rows are dropped.
    @discardableResult
    public func save(_ pad: Pad, touch: Bool = true) throws -> Pad {
        guard SheetID.isValid(pad.id) else { throw StoreError.invalidID(pad.id) }
        var p = pad.compacted
        if touch { p.updatedAt = Date() }
        let data = try PadJSON.encoder.encode(p)
        try queue.sync { try data.write(to: padURL(p.id), options: .atomic) }
        return p
    }

    public func delete(_ id: String) throws {
        guard SheetID.isValid(id) else { throw StoreError.invalidID(id) }
        try FileManager.default.removeItem(at: padURL(id))
    }

    /// Today on launch: when no sheet is dated today, create one with carry-over; when several exist,
    /// the most recently updated.
    public func today(now: Date = Date(), timeZone: TimeZone = .current) throws -> Pad {
        let key = DayKey.key(for: now, timeZone: timeZone)
        let all = try list()
        if let existing = all.filter({ $0.date == key }).max(by: { $0.updatedAt < $1.updatedAt }) { return existing }
        return try create(date: key, tags: [], now: now, timeZone: timeZone, among: all)
    }

    /// New dated sheet. When it is the first sheet dated today, it carries over from the latest earlier day.
    @discardableResult
    public func create(date: String, tags: [String] = [], title: String = "", now: Date = Date(),
                       timeZone: TimeZone = .current) throws -> Pad {
        try create(date: date, tags: tags, title: title, now: now, timeZone: timeZone, among: try list())
    }

    private func create(date: String, tags: [String], title: String = "", now: Date, timeZone: TimeZone, among all: [Pad]) throws -> Pad {
        var pad = Pad.dated(date, tags: tags, title: title, now: now)
        while all.contains(where: { $0.id == pad.id }) { pad.id = SheetID.make(for: date) }
        let todayKey = DayKey.key(for: now, timeZone: timeZone)
        if date == todayKey, !all.contains(where: { $0.date == todayKey }) {
            pad = Rollover.carried(from: Rollover.sources(for: todayKey, among: all), into: pad)
        }
        return try save(pad, touch: false)
    }

    /// New pinned sheet with a slug id.
    @discardableResult
    public func createPinned(title: String, tags: [String] = [], now: Date = Date()) throws -> Pad {
        let existing = Set(try list().map(\.id))
        let pad = Pad(id: SheetID.slug(title, existing: existing), date: nil, title: title, tags: tags, pinned: true, createdAt: now, updatedAt: now)
        return try save(pad, touch: false)
    }

    /// Duplicate: blocks and open to-dos copied, new ids, title + " copy". Same date (or pinned).
    @discardableResult
    public func duplicate(_ pad: Pad, now: Date = Date()) throws -> Pad {
        let existing = Set(try list().map(\.id))
        let newID: String
        if let d = pad.date {
            var id = SheetID.make(for: d)
            while existing.contains(id) { id = SheetID.make(for: d) }
            newID = id
        } else {
            newID = SheetID.slug(pad.title + " copy", existing: existing)
        }
        return try save(pad.duplicate(id: newID, now: now), touch: false)
    }

    /// Moves a sheet to another date (unpinning it). Its id is re-keyed to the new date; the old file goes.
    @discardableResult
    public func move(_ pad: Pad, to day: String) throws -> Pad {
        guard pad.date != day || pad.pinned else { return pad }
        return try save(pad.moved(to: day))
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
