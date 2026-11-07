import XCTest
@testable import ScratchpadCore

/// The two stores side by side on throwaway folders. Nothing here touches a real store.
final class CoreParityTests: XCTestCase {
    private var folders: [URL] = []

    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scratchpad-parity-\(UUID().uuidString)")
        folders.append(url)
        return url
    }

    override func tearDownWithError() throws {
        for url in folders { try? FileManager.default.removeItem(at: url) }
    }

    private let now = Date(timeIntervalSince1970: 1_794_000_000)

    /// Every file under a store, by relative path.
    private func tree(_ root: URL) throws -> [String: Data] {
        var out: [String: Data] = [:]
        for sub in ["pads", "assets"] {
            for name in try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(sub).path) {
                out["\(sub)/\(name)"] = try Data(contentsOf: root.appendingPathComponent("\(sub)/\(name)"))
            }
        }
        return out
    }

    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private let words = ["plan", "café", "🙂", "a/b", "quote \" here", "back\\slash", "line\nbreak", "tab\there", "日本語", "", "   ", "=SUM(A1:B2)"]

    private func text(_ g: inout Seeded) -> String { (0..<Int.random(in: 1...4, using: &g)).map { _ in words.randomElement(using: &g)! }.joined(separator: " ") }

    private func pad(_ id: String, _ g: inout Seeded) -> Pad {
        let day = "2026-\(String(format: "%02d", Int.random(in: 1...12, using: &g)))-\(String(format: "%02d", Int.random(in: 1...28, using: &g)))"
        let pinned = Bool.random(using: &g) && Bool.random(using: &g)
        var p = Pad(id: id, date: pinned ? nil : day, title: text(&g), tags: ["Work", "#home", "q4"].filter { _ in Bool.random(using: &g) }, pinned: pinned,
                    createdAt: now.addingTimeInterval(Double(Int.random(in: -9999...0, using: &g))),
                    updatedAt: now.addingTimeInterval(Double(Int.random(in: -9999...9999, using: &g))))
        for i in 0..<Int.random(in: 0...5, using: &g) {
            let kind = BlockKind.allCases.randomElement(using: &g)!
            var b = Block(id: "\(id)-b\(i)", kind: kind, x: Int.random(in: 0...40, using: &g) * 24, y: i * 240, w: 240, h: Bool.random(using: &g) ? 120 : nil,
                          rotation: [0, 15, -7.5, 179.9, 180][Int.random(in: 0...4, using: &g)], font: BlockFont.allCases.randomElement(using: &g)!,
                          fontSize: Int.random(in: 10...48, using: &g), bold: Bool.random(using: &g), italic: Bool.random(using: &g))
            switch kind {
            case .table: b.rows = [[text(&g), "=1+2"], ["3", text(&g)]]; b.colWidths = Bool.random(using: &g) ? [120, 90] : nil; b.caption = text(&g)
            case .image, .file: b.asset = "assets/x.png"; b.name = "x.png"; b.size = 12
            case .link: b.url = "https://example.test/\(i)"; b.text = text(&g)
            case .code: b.text = text(&g); b.language = Bool.random(using: &g) ? "swift" : nil
            case .text: b.text = text(&g)
            case .divider: break
            }
            p.blocks.append(b)
        }
        p.todos = (0..<Int.random(in: 0...5, using: &g)).map {
            Todo(id: "\(id)-t\($0)", text: text(&g), status: [.open, .done, .deferred][Int.random(in: 0...2, using: &g)],
                 createdAt: now.addingTimeInterval(Double(Int.random(in: -999999...0, using: &g))), carriedFrom: Bool.random(using: &g) ? "2026-01-01-aaaaaa" : nil)
        }
        return p
    }

    /// The same 3,000 operations on each store, comparing every answer and, often, every byte.
    func testSeededOperationsLeaveTheSameFoldersByteForByte() throws {
        let (rootA, rootB) = (folder(), folder())
        let a = try PadStore(root: rootA, engine: .swift), b = try PadStore(root: rootB, engine: .rust)
        XCTAssertFalse(a.usesCore)
        XCTAssertTrue(b.usesCore)
        var g = Seeded(state: 20261107)
        let ids = (0..<40).map { "2026-01-01-sheet\($0)" } + ["pinned-a", "pinned-b"]
        var compared = 0
        for step in 0..<3000 {
            let id = ids.randomElement(using: &g)!
            switch Int.random(in: 0..<100, using: &g) {
            case 0..<40:
                let p = pad(id, &g)
                let (x, y) = (try a.save(p, touch: false), try b.save(p, touch: false))
                XCTAssertEqual(x, y, "save \(step)")
            case 40..<50:
                let x = try? a.delete(id), y = try? b.delete(id)
                XCTAssertEqual(x == nil, y == nil, "delete \(step)")
            case 50..<70:
                let x = Result { try a.load(id) }, y = Result { try b.load(id) }
                switch (x, y) {
                case (.success(let p), .success(let q)): XCTAssertEqual(p, q, "load \(step)")
                case (.failure, .failure): break // A sheet that won't read fails in both.
                default: XCTFail("load \(step): one read it, one didn't")
                }
            case 70..<80:
                let x = try a.scan(), y = try b.scan()
                XCTAssertEqual(x.pads, y.pads, "scan \(step)")
                XCTAssertEqual(x.unreadable, y.unreadable, "scan \(step)")
                XCTAssertEqual(x.downloading, y.downloading, "scan \(step)")
            case 80..<86:
                for store in [a, b] { try Data("{ broken \(step % 3)".utf8).write(to: store.root.appendingPathComponent("pads/\(id).json")) }
            case 86..<92:
                let archive = ScratchpadArchive(sheets: (0..<4).map { _ in pad(ids.randomElement(using: &g)!, &g) }, assets: [:], exportedAt: now)
                let x = try archive.importInto(a), y = try archive.importInto(b)
                XCTAssertEqual(x, y, "import \(step)")
            case 92..<96:
                for store in [a, b] { try Data("stand-in".utf8).write(to: store.root.appendingPathComponent("pads/.\(id).json.icloud")) }
                XCTAssertEqual(try a.scan().downloading, try b.scan().downloading)
                for store in [a, b] { try FileManager.default.removeItem(at: store.root.appendingPathComponent("pads/.\(id).json.icloud")) }
            default:
                let title = ["Plans", "Ünï Côde", "Soup & Salad"].randomElement(using: &g)!
                let (x, y) = (try a.createPinned(title: title, now: now), try b.createPinned(title: title, now: now))
                XCTAssertEqual(x, y, "pinned \(step)")
            }
            if step % 25 == 0 {
                XCTAssertEqual(try tree(rootA), try tree(rootB), "folders differ at step \(step)")
                compared += 1
            }
        }
        XCTAssertEqual(try tree(rootA), try tree(rootB))
        XCTAssertEqual(compared, 120)
    }

    func testAFolderSwapsBetweenStoresInBothDirections() throws {
        let root = folder()
        var g = Seeded(state: 7)
        let swift = try PadStore(root: root, engine: .swift), core = try PadStore(root: root, engine: .rust)
        for round in 0..<200 {
            let id = "2026-01-01-swap\(round % 9)"
            let (writer, reader) = round % 2 == 0 ? (swift, core) : (core, swift)
            let saved = try writer.save(pad(id, &g), touch: false)
            let before = try Data(contentsOf: root.appendingPathComponent("pads/\(id).json"))
            let read = try XCTUnwrap(reader.load(id))
            XCTAssertEqual(read, saved)
            try reader.save(read, touch: false)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("pads/\(id).json")), before, "a reader rewrote a sheet differently")
        }
        XCTAssertTrue(try swift.scan().unreadable.isEmpty)
        XCTAssertTrue(try core.scan().unreadable.isEmpty)
    }

    func testUnknownFieldsSurviveTheCoreButNotTheSwiftStore() throws {
        let raw = #"{"id":"a","createdAt":"2026-01-02T03:04:05Z","mood":"good","blocks":[{"id":"b","kind":"text","x":0,"y":0,"w":96,"ink":"blue"}],"todos":[{"id":"t","text":"x","status":"open","createdAt":"2026-01-02T03:04:05Z","due":"soon"}]}"#
        let root = folder()
        let store = try PadStore(root: root, engine: .rust)
        let file = root.appendingPathComponent("pads/a.json")
        try Data(raw.utf8).write(to: file)
        var pad = try XCTUnwrap(store.load("a"))
        pad.title = "Edited"
        pad.blocks[0].x = 48
        try store.save(pad)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(saved["title"] as? String, "Edited")
        XCTAssertEqual(saved["mood"] as? String, "good")
        XCTAssertEqual((saved["blocks"] as? [[String: Any]])?.first?["ink"] as? String, "blue")
        XCTAssertEqual((saved["todos"] as? [[String: Any]])?.first?["due"] as? String, "soon")
    }

    func testTheCoreSeesPlaceholdersThroughTheAppleVault() throws {
        let store = try PadStore(root: folder(), engine: .rust)
        let key = DayKey.key(for: now)
        try Data("stand-in".utf8).write(to: store.root.appendingPathComponent("pads/.\(key)-abcd.json.icloud"))
        XCTAssertEqual(try store.scan().downloading, ["\(key)-abcd"])
        XCTAssertThrowsError(try store.today(now: now)) { XCTAssertEqual($0.localizedDescription, PadStore.StoreError.stillDownloading.localizedDescription) }
        XCTAssertTrue(try store.list().isEmpty)
        XCTAssertEqual(try store.today(now: now, ignoringDownloads: true).date, key)
    }

    func testTheAppleVaultRefusesPathsOutsideTheRoot() throws {
        let root = folder()
        _ = try PadStore(root: root, engine: .swift)
        let secret = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString)")
        try Data("x".utf8).write(to: secret)
        defer { try? FileManager.default.removeItem(at: secret) }
        let vault = AppleVault(root: root)
        for path in ["../\(secret.lastPathComponent)", "pads/../../\(secret.lastPathComponent)", secret.path] {
            XCTAssertThrowsError(try vault.read(path: path), path)
            XCTAssertThrowsError(try vault.write(path: path, data: Data("y".utf8)), path)
            XCTAssertThrowsError(try vault.remove(path: path), path)
            XCTAssertFalse(vault.exists(path: path), path)
        }
        XCTAssertEqual(try Data(contentsOf: secret), Data("x".utf8))
    }

    func testTheCoreBacksUpBeforeItOpensAndKeepsThreeOutsideTheStore() throws {
        let root = folder(), backups = folder()
        let swift = try PadStore(root: root, engine: .swift)
        try swift.create(date: "2026-01-02", title: "Kept", now: now)
        let store = try PadStore(root: root, engine: .rust, backups: backups)
        XCTAssertTrue(store.usesCore)
        var names = try FileManager.default.contentsOfDirectory(atPath: backups.path)
        XCTAssertEqual(names.count, 1)
        let archive = try ScratchpadArchive.decode(Data(contentsOf: backups.appendingPathComponent(names[0])))
        XCTAssertEqual(archive.sheets.map(\.title), ["Kept"])
        for day in 0..<5 { try Backup.make(of: root, in: backups, now: now.addingTimeInterval(Double(day) * 86_400)) }
        names = try FileManager.default.contentsOfDirectory(atPath: backups.path).sorted()
        XCTAssertEqual(names.count, Backup.kept)
    }

    func testTheLocalStoreAndICloudEachGetABackupOnTheSameDay() throws {
        let backups = folder(), base = folder()
        for parent in ["Application Support", "Documents"] {
            let root = base.appendingPathComponent("\(parent)/Scratchpad")
            _ = try PadStore(root: root, engine: .rust, backups: backups)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backups.path).count, 2)
    }

    func testAStoreStaysOnSwiftIfTheBackupCantBeMade() throws {
        let blocked = folder()
        try FileManager.default.createDirectory(at: blocked.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("a file, not a folder".utf8).write(to: blocked)
        XCTAssertFalse(try PadStore(root: folder(), engine: .rust, backups: blocked.appendingPathComponent("sub")).usesCore)
    }

    func testTheSwitchIsWhatTheTestRunAskedFor() throws {
        let asked = ProcessInfo.processInfo.environment["SCRATCHPAD_STORE"]
        XCTAssertEqual(try PadStore(root: folder()).usesCore, asked == "rust")
        XCTAssertEqual(CoreRules.enabled, ProcessInfo.processInfo.environment["SCRATCHPAD_RULES"] != "swift")
    }
}
