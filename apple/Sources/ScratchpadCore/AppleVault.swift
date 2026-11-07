import Foundation
import ScratchpadFFI

/// Files for the core, on Apple. Plain reads and coordinated writes: Quire measured about 25 ms per
/// file for coordinated reads on a file-provider folder. An evicted iCloud file, a hidden
/// `.<id>.json.icloud` stand-in, is listed under its real name as not downloaded, and asked for.
final class AppleVault: Vault, @unchecked Sendable {
    private let root: URL

    init(root: URL) { self.root = root.standardizedFileURL }

    /// The file for a vault path. Anything that would leave the root is refused.
    private func url(_ path: String) throws -> URL {
        let target = root.appendingPathComponent(path).standardizedFileURL
        guard !path.hasPrefix("/"), target.path.hasPrefix(root.path + "/") else {
            throw VaultFailure.Failed(message: "Outside the store: \(path)")
        }
        return target
    }

    private func failing<T>(_ body: () throws -> T) throws -> T {
        do { return try body() }
        catch let failure as VaultFailure { throw failure }
        catch { throw VaultFailure.Failed(message: error.localizedDescription) }
    }

    func list(dir: String) throws -> [VaultItem] {
        try failing {
            let folder = try url(dir)
            return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]).map { file in
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970
                if let id = PadStore.placeholderID(file.lastPathComponent) {
                    PadStore.requestDownload(folder.appendingPathComponent("\(id).json"))
                    return VaultItem(path: "\(dir)/\(id).json", modified: modified, downloaded: false)
                }
                return VaultItem(path: "\(dir)/\(file.lastPathComponent)", modified: modified, downloaded: true)
            }
        }
    }

    func read(path: String) throws -> Data { try failing { try Data(contentsOf: url(path)) } }

    func write(path: String, data: Data) throws {
        try failing {
            try PadStore.coordinated(url(path), .replacing) { try data.write(to: $0, options: .atomic) }
        }
    }

    func remove(path: String) throws {
        try failing {
            try PadStore.coordinated(url(path), .deleting) { try FileManager.default.removeItem(at: $0) }
        }
    }

    func exists(path: String) -> Bool {
        guard let target = try? url(path) else { return false }
        return FileManager.default.fileExists(atPath: target.path)
    }

    func localUrl(path: String) -> String? { (try? url(path))?.path }
}

/// A copy of everything, outside the synced folder, before the core first writes to it.
public enum Backup {
    public static let kept = 3

    /// Application Support/Scratchpad Backups: beside the store, never inside it.
    public static func folder() -> URL? {
        (try? PadStore.defaultRoot())?.deletingLastPathComponent().appendingPathComponent("Scratchpad Backups", isDirectory: true)
    }

    /// One archive a day at most for each store, read by the Swift store so the core isn't involved,
    /// keeping the last three.
    public static func make(of root: URL, in folder: URL, now: Date) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        // The local store and iCloud's are both called Scratchpad; what holds them tells them apart.
        let tail = "-\(root.deletingLastPathComponent().lastPathComponent)-\(root.lastPathComponent).scratchpad"
        let file = folder.appendingPathComponent("before-core-\(ISODate.string(now).prefix(10))\(tail)")
        if fm.fileExists(atPath: file.path) { return }
        let store = try PadStore(root: root, engine: .swift)
        let archive = ScratchpadArchive.build(sheets: try store.list(), store: store, now: now)
        try archive.encoded().write(to: file, options: .atomic)
        let all = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("before-core-") && $0.lastPathComponent.hasSuffix(tail) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in all.dropFirst(kept) { try fm.removeItem(at: old) }
    }
}
