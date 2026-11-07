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

    // MARK: A sheet that isn't here yet, or won't read, still holds its name

    private func unreadable(_ id: String, in store: PadStore) throws -> URL {
        let url = store.root.appendingPathComponent("pads/\(id).json")
        try Data("{ not a sheet".utf8).write(to: url)
        return url
    }

    func testANewPinnedSheetNeverLandsOnOneThatWontRead() throws {
        let store = try makeStore()
        let file = try unreadable("plans", in: store)
        let made = try store.createPinned(title: "Plans", now: now)
        XCTAssertNotEqual(made.id, "plans")
        XCTAssertEqual(try Data(contentsOf: file), Data("{ not a sheet".utf8), "an unreadable sheet was overwritten")
    }

    func testANewPinnedSheetNeverLandsOnOneStillDownloading() throws {
        let store = try makeStore()
        try placeholder("plans", in: store)
        XCTAssertNotEqual(try store.createPinned(title: "Plans", now: now).id, "plans")
    }

    func testADuplicateNeverLandsOnOneThatWontRead() throws {
        let store = try makeStore()
        let file = try unreadable("plans-copy", in: store)
        let pinned = try store.createPinned(title: "Plans", now: now)
        XCTAssertNotEqual(try store.duplicate(pinned, now: now).id, "plans-copy")
        XCTAssertEqual(try Data(contentsOf: file), Data("{ not a sheet".utf8))
    }

    // MARK: Carrying over needs the whole picture

    private func yesterdayWithATodo(in store: PadStore) throws {
        let yesterday = DayMath.add(days: -1, to: todayKey)!
        var pad = try store.create(date: yesterday, now: now)
        pad.todos = [Todo(text: "Ring the bank", createdAt: now)]
        try store.save(pad, touch: false)
    }

    /// Today's real sheet may be the one on its way, and it has these to-dos already.
    func testANewSheetDoesntCarryWhileSheetsAreDownloading() throws {
        let store = try makeStore()
        try yesterdayWithATodo(in: store)
        try placeholder("\(todayKey)-abcd", in: store)
        XCTAssertTrue(try store.create(date: todayKey, now: now).todos.isEmpty, "to-dos carried from a partial list")
    }

    func testGivingUpOnDownloadsMakesASheetWithNoCarryOver() throws {
        let store = try makeStore()
        try yesterdayWithATodo(in: store)
        try placeholder("\(todayKey)-abcd", in: store)
        XCTAssertTrue(try store.today(now: now, ignoringDownloads: true).todos.isEmpty, "to-dos carried from a partial list")
    }

    func testCarryOverStillHappensWithNothingDownloading() throws {
        let store = try makeStore()
        try yesterdayWithATodo(in: store)
        XCTAssertEqual(try store.today(now: now).todos.map(\.text), ["Ring the bank"])
    }

    // MARK: Importing a backup

    private func archive(_ pads: [Pad]) -> ScratchpadArchive { ScratchpadArchive(sheets: pads, assets: [:], exportedAt: now) }

    func testImportingAnOldBackupKeepsTheNewerSheet() throws {
        let store = try makeStore()
        var old = try store.create(date: "2026-01-02", title: "Old", now: now)
        old.updatedAt = now
        var newer = old
        newer.title = "Newer"
        newer.updatedAt = now.addingTimeInterval(60)
        try store.save(newer, touch: false)
        let result = try archive([old]).importInto(store)
        XCTAssertEqual(try store.load(old.id)?.title, "Newer", "a backup reverted a newer sheet")
        XCTAssertEqual(result.sheets, 0)
        XCTAssertEqual(result.keptNewer, 1)
    }

    func testImportingANewerSheetReplacesTheOlderOne() throws {
        let store = try makeStore()
        let old = try store.create(date: "2026-01-02", title: "Old", now: now)
        var newer = old
        newer.title = "Newer"
        newer.updatedAt = now.addingTimeInterval(60)
        let result = try archive([newer]).importInto(store)
        XCTAssertEqual(try store.load(old.id)?.title, "Newer")
        XCTAssertEqual(result.overwritten, 1)
    }

    func testImportingNeverReplacesASheetThatWontReadOrHasntArrived() throws {
        let store = try makeStore()
        let file = try unreadable("2026-01-02-bad000", in: store)
        try placeholder("2026-01-03-away00", in: store)
        let sheets = ["2026-01-02-bad000", "2026-01-03-away00"].map { Pad(id: $0, date: nil, createdAt: now, updatedAt: now) }
        let result = try archive(sheets).importInto(store)
        XCTAssertEqual(try Data(contentsOf: file), Data("{ not a sheet".utf8))
        XCTAssertNil(try store.load("2026-01-03-away00"), "it should wait for the sheet to arrive")
        XCTAssertEqual(result.skipped, 2)
    }

    // MARK: Coming back to the app

    private func sheet(_ date: String?, updated: TimeInterval = 0) -> Pad {
        Pad(id: "s", date: date, createdAt: now, updatedAt: now.addingTimeInterval(updated))
    }

    func testComingBackToTheSameDayWithNothingNewChangesNothing() {
        let here = sheet("2026-01-02")
        XCTAssertEqual(Resume.step(current: here, onDisk: here, lastToday: "2026-01-02", today: "2026-01-02"), .nothing)
    }

    func testComingBackPicksUpWhatAnotherDeviceSaved() {
        let theirs = sheet("2026-01-02", updated: 60)
        XCTAssertEqual(Resume.step(current: sheet("2026-01-02"), onDisk: theirs, lastToday: "2026-01-02", today: "2026-01-02"),
                       .load(theirs))
    }

    func testComingBackDoesntReplaceTheSheetWithAnOlderCopy() {
        let here = sheet("2026-01-02", updated: 60)
        XCTAssertEqual(Resume.step(current: here, onDisk: sheet("2026-01-02"), lastToday: "2026-01-02", today: "2026-01-02"), .nothing)
    }

    func testComingBackOnANewDayMovesOffYesterdaysSheet() {
        let here = sheet("2026-01-02")
        XCTAssertEqual(Resume.step(current: here, onDisk: here, lastToday: "2026-01-02", today: "2026-01-03"), .openToday)
    }

    func testANewDayLeavesAnOlderSheetYouChoseToOpen() {
        let here = sheet("2025-12-25")
        XCTAssertEqual(Resume.step(current: here, onDisk: here, lastToday: "2026-01-02", today: "2026-01-03"), .nothing)
    }

    func testANewDayLeavesAPinnedSheetOpen() {
        let here = sheet(nil)
        XCTAssertEqual(Resume.step(current: here, onDisk: here, lastToday: "2026-01-02", today: "2026-01-03"), .nothing)
    }

    func testComingBackWithNoSheetOpensToday() {
        XCTAssertEqual(Resume.step(current: nil, onDisk: nil, lastToday: "2026-01-02", today: "2026-01-02"), .openToday)
    }

    // MARK: Dates other writers leave

    func testReadsAnyFractionalDigitsTheLinuxAppMayHaveWritten() throws {
        for s in ["2026-11-07T12:30:45Z", "2026-11-07T12:30:45.1Z", "2026-11-07T12:30:45.123Z",
                  "2026-11-07T12:30:45.123456Z", "2026-11-07T12:30:45.123456789Z"] {
            let d = try XCTUnwrap(ISODate.parse(s), "\(s) wouldn't parse, so the sheet would go unreadable")
            XCTAssertEqual(d.timeIntervalSince1970, 1_794_054_645, accuracy: 1, s)
        }
    }

    func testAVeryLargeNumberShowsNoFloatDust() {
        XCTAssertEqual(Formula.format(99_999_999_999_999), "99,999,999,999,999")
        XCTAssertEqual(Formula.format(1234.5678), "1,234.5678")
        XCTAssertEqual(Formula.format(0.99995), "1")
        XCTAssertEqual(Formula.format(-1.5), "-1.5")
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
