import Foundation

/// File-backed store: <root>/pads/<id>.json and <root>/assets/<uuid>.<ext>.
/// Same layout as the Linux store, so a synced folder works across both.
public final class PadStore: @unchecked Sendable {
    public enum StoreError: Error, LocalizedError {
        case invalidID(String)
        /// Sheets are on their way from iCloud, so what's here isn't the whole picture yet.
        case stillDownloading
        public var errorDescription: String? {
            switch self {
            case .invalidID(let id): return "Not a valid sheet id: \(id)"
            case .stillDownloading: return "Your sheets are still downloading from iCloud."
            }
        }
    }

    /// What's in the store, including what can't be shown.
    public struct Scan {
        public var pads: [Pad] = []
        /// File names that are there but aren't sheets this app can read.
        public var unreadable: [String] = []
        /// Ids of sheets iCloud has but hasn't downloaded yet.
        public var downloading: [String] = []
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
    public func list() throws -> [Pad] { try scan().pads }

    /// The sheets, and what couldn't be listed: a file that won't parse is reported, and an
    /// evicted iCloud file (a hidden `.<id>.json.icloud` stand-in) is asked for.
    public func scan() throws -> Scan {
        let dir = root.appendingPathComponent("pads")
        var result = Scan()
        for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            let name = file.lastPathComponent
            if let id = PadStore.placeholderID(name) {
                result.downloading.append(id)
                requestDownload(padURL(id))
            } else if file.pathExtension == "json", !name.hasPrefix(".") {
                if let pad = try? PadJSON.decoder.decode(Pad.self, from: Data(contentsOf: file)) {
                    result.pads.append(pad)
                } else {
                    result.unreadable.append(name)
                }
            }
        }
        result.pads.sort(by: PadStore.newestFirst)
        result.unreadable.sort()
        result.downloading.sort()
        return result
    }

    /// The id in an iCloud stand-in's file name.
    private static func placeholderID(_ name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".json.icloud") else { return nil }
        return String(name.dropFirst().dropLast(".json.icloud".count))
    }

    private func requestDownload(_ url: URL) {
        #if canImport(Darwin)
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        #endif
    }

    /// Runs a write under file coordination, so it never races the iCloud daemon.
    private func coordinated(_ url: URL, _ options: CoordinatedWrite, _ body: (URL) throws -> Void) throws {
        #if canImport(Darwin)
        var coordinationError: NSError?
        var bodyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url, options: options == .deleting ? .forDeleting : .forReplacing,
            error: &coordinationError
        ) { target in
            do { try body(target) } catch { bodyError = error }
        }
        if let error = coordinationError ?? bodyError { throw error }
        #else
        try body(url)
        #endif
    }

    private enum CoordinatedWrite { case replacing, deleting }

    /// One-off, when iCloud arrives: brings the sheets and pictures of `local` here. An id
    /// already here stays as it is. A sheet still downloading is left for next time, as it
    /// can't be compared yet. Nothing is deleted: each file handled moves to
    /// `moved-to-icloud/` beside the local store, so it's never brought across twice.
    @discardableResult
    public func adopt(from local: PadStore) throws -> Int {
        let fm = FileManager.default
        let here = try scan()
        let known = Set(try fm.contentsOfDirectory(atPath: root.appendingPathComponent("pads").path))
        let waiting = Set(here.downloading)
        let aside = local.root.appendingPathComponent("moved-to-icloud/pads", isDirectory: true)
        let sources = try fm.contentsOfDirectory(at: local.root.appendingPathComponent("pads"),
                                                 includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") }
        guard !sources.isEmpty else { return 0 }
        try fm.createDirectory(at: aside, withIntermediateDirectories: true)
        // Pictures first: a sheet must never arrive before what it shows.
        let assets = root.appendingPathComponent("assets")
        for item in try fm.contentsOfDirectory(at: local.root.appendingPathComponent("assets"),
                                               includingPropertiesForKeys: nil) {
            let target = assets.appendingPathComponent(item.lastPathComponent)
            if !fm.fileExists(atPath: target.path) {
                let data = try Data(contentsOf: item)
                try coordinated(target, .replacing) { try data.write(to: $0, options: .atomic) }
            }
        }
        var brought = 0
        for file in sources {
            let name = file.lastPathComponent
            if waiting.contains(file.deletingPathExtension().lastPathComponent) { continue }
            if !known.contains(name) {
                let data = try Data(contentsOf: file)
                try coordinated(root.appendingPathComponent("pads/\(name)"), .replacing) {
                    try data.write(to: $0, options: .atomic)
                }
                brought += 1
            }
            let target = aside.appendingPathComponent(name)
            try? fm.removeItem(at: target)
            try fm.moveItem(at: file, to: target)
        }
        return brought
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
        try queue.sync {
            try coordinated(padURL(p.id), .replacing) { try data.write(to: $0, options: .atomic) }
        }
        return p
    }

    public func delete(_ id: String) throws {
        guard SheetID.isValid(id) else { throw StoreError.invalidID(id) }
        try coordinated(padURL(id), .deleting) { try FileManager.default.removeItem(at: $0) }
    }

    /// Today on launch: when no sheet is dated today, create one with carry-over; when several exist,
    /// the most recently updated. While sheets are downloading it throws `stillDownloading` rather
    /// than make one: today's may be among them, and carrying over from a partial list would carry
    /// to-dos twice. `ignoringDownloads` is for a device that has waited and can't reach iCloud.
    public func today(now: Date = Date(), timeZone: TimeZone = .current, ignoringDownloads: Bool = false) throws -> Pad {
        let key = DayKey.key(for: now, timeZone: timeZone)
        let scan = try scan()
        let all = scan.pads
        if let existing = all.filter({ $0.date == key }).max(by: { $0.updatedAt < $1.updatedAt }) { return existing }
        if !scan.downloading.isEmpty && !ignoringDownloads { throw StoreError.stillDownloading }
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
        try coordinated(root.appendingPathComponent(name), .replacing) { try data.write(to: $0, options: .atomic) }
        return name
    }

    public func copyAsset(from url: URL) throws -> String {
        try storeAsset(Data(contentsOf: url), ext: url.pathExtension)
    }

    public func assetURL(_ rel: String) -> URL { root.appendingPathComponent(rel) }
}
