import XCTest
@testable import ScratchpadCore

final class SyncSafetyTests: XCTestCase {
    private var folders: [URL] = []

    private func makeStore() throws -> PadStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scratchpad-\(UUID().uuidString)")
        folders.append(url)
        return try PadStore(root: url)
    }

    override func tearDownWithError() throws {
        for url in folders { try? FileManager.default.removeItem(at: url) }
    }

    private func placeholder(_ id: String, in store: PadStore) throws {
        let url = store.root.appendingPathComponent("pads/.\(id).json.icloud")
        try Data("placeholder".utf8).write(to: url)
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var todayKey: String { DayKey.key(for: now, timeZone: .current) }

    /// A second device: today's sheet is in iCloud, not yet downloaded.
    func testTodayDoesntMakeASecondSheetWhileOneIsDownloading() throws {
        let store = try makeStore()
        try placeholder("\(todayKey)-abcd", in: store)
        XCTAssertThrowsError(try store.today(now: now))
        XCTAssertTrue(try store.list().isEmpty, "a second sheet for today was made")
    }

    func testTodayFindsAnArrivedSheetInsteadOfWaiting() throws {
        let store = try makeStore()
        let made = try store.create(date: todayKey, now: now)
        try placeholder("2020-01-01-abcd", in: store)
        XCTAssertEqual(try store.today(now: now).id, made.id)
    }

    func testAPhoneThatCantReachICloudCanStillStartToday() throws {
        let store = try makeStore()
        try placeholder("\(todayKey)-abcd", in: store)
        XCTAssertEqual(try store.today(now: now, ignoringDownloads: true).date, todayKey)
    }

    func testAPlaceholderIsReportedNotListed() throws {
        let store = try makeStore()
        try placeholder("2026-01-02-abcd", in: store)
        let scan = try store.scan()
        XCTAssertEqual(scan.downloading, ["2026-01-02-abcd"])
        XCTAssertTrue(scan.pads.isEmpty && scan.unreadable.isEmpty)
    }

    func testAnUnreadableSheetIsNamedAndTheRestStillList() throws {
        let store = try makeStore()
        let good = try store.create(date: "2026-01-02", now: now)
        try Data("{ not a sheet".utf8).write(to: store.root.appendingPathComponent("pads/2026-01-01-bad0.json"))
        let scan = try store.scan()
        XCTAssertEqual(scan.pads.map(\.id), [good.id])
        XCTAssertEqual(scan.unreadable, ["2026-01-01-bad0.json"])
    }

    func testAdoptBringsLocalSheetsAcrossAndKeepsTheOriginals() throws {
        let local = try makeStore(), cloud = try makeStore()
        let sheet = try local.create(date: "2026-01-02", title: "Local", now: now)
        let asset = try local.storeAsset(Data("picture".utf8), ext: "png")
        XCTAssertEqual(try cloud.adopt(from: local), 1)
        XCTAssertEqual(try cloud.load(sheet.id)?.title, "Local")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cloud.assetURL(asset).path))
        let kept = local.root.appendingPathComponent("moved-to-icloud/pads/\(sheet.id).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path), "the original must survive")
    }

    func testAdoptNeverReplacesASheetAlreadyInICloud() throws {
        let local = try makeStore(), cloud = try makeStore()
        var mine = try local.create(date: "2026-01-02", title: "Older", now: now)
        var theirs = mine
        theirs.title = "Already in iCloud"
        try cloud.save(theirs, touch: false)
        mine.title = "Local copy"
        try local.save(mine, touch: false)
        XCTAssertEqual(try cloud.adopt(from: local), 0)
        XCTAssertEqual(try cloud.load(mine.id)?.title, "Already in iCloud")
        let kept = local.root.appendingPathComponent("moved-to-icloud/pads/\(mine.id).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path), "the local copy must survive")
    }

    func testAdoptRunsOnlyOnce() throws {
        let local = try makeStore(), cloud = try makeStore()
        let sheet = try local.create(date: "2026-01-02", now: now)
        try cloud.adopt(from: local)
        try cloud.delete(sheet.id)
        XCTAssertEqual(try cloud.adopt(from: local), 0, "a sheet deleted in iCloud came back")
        XCTAssertNil(try cloud.load(sheet.id))
    }

    func testAdoptLeavesASheetStillDownloadingForNextTime() throws {
        let local = try makeStore(), cloud = try makeStore()
        let sheet = try local.create(date: "2026-01-02", now: now)
        try placeholder(sheet.id, in: cloud)
        XCTAssertEqual(try cloud.adopt(from: local), 0)
        XCTAssertNotNil(try local.load(sheet.id), "it can't be compared yet, so it stays put")
    }

    func testCoordinatedWritesStillRoundTrip() throws {
        let store = try makeStore()
        var pad = try store.create(date: "2026-01-02", now: now)
        pad.title = "Saved"
        try store.save(pad)
        XCTAssertEqual(try store.load(pad.id)?.title, "Saved")
        try store.delete(pad.id)
        XCTAssertNil(try store.load(pad.id))
    }
}
