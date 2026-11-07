import XCTest
@testable import ScratchpadCore

final class SheetMenuTests: XCTestCase {
    func testInsertOffersWhatCanBeInserted() {
        XCTAssertEqual(SheetMenus.insert, [.text, .table, .code, .link, .divider])
    }

    func testEveryInsertHasItsOwnIcon() {
        let symbols = SheetMenus.insert.map(SheetMenus.symbol)
        XCTAssertTrue(symbols.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(symbols).count, symbols.count)
    }

    /// The sheet's menu is about the sheet: bringing in an archive isn't, so it's in Settings.
    func testTheSheetMenuIsAboutTheSheet() {
        XCTAssertEqual(SheetMenus.more, [.duplicate, .export, .delete])
    }

    func testDeleteComesLast() {
        XCTAssertEqual(SheetMenus.more.last, .delete)
    }
}

final class StoreWordsTests: XCTestCase {
    func testSaysWhereSheetsLiveInPlainWords() {
        XCTAssertEqual(StoreWords.place(usingICloud: true), "iCloud Drive")
        XCTAssertEqual(StoreWords.place(usingICloud: false), "This device")
    }

    func testSaysWhatThatMeans() {
        XCTAssertEqual(StoreWords.meaning(usingICloud: true), "Your sheets sync across your devices.")
        XCTAssertEqual(StoreWords.meaning(usingICloud: false), "Your sheets stay here and don't sync.")
    }

    func testAFolderReadsAsItsNameNotItsPath() {
        XCTAssertEqual(StoreWords.folder("/private/var/mobile/Containers/Data/Application/ABC/Documents/Scratchpad"), "Scratchpad")
        XCTAssertEqual(StoreWords.folder("/a/b/"), "b")
    }
}
