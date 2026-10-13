import XCTest
@testable import ScratchpadCore

/// apple/Tests/ScratchpadCoreTests/CoreTests.swift -> repo root.
let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()

func sample(_ name: String) throws -> Data {
    try Data(contentsOf: repoRoot.appendingPathComponent("shared/samples/\(name)"))
}

func tempStore() throws -> PadStore {
    try PadStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("scratchpad-tests-\(UUID().uuidString)"))
}

final class PasteClassifierTests: XCTestCase {
    func testPlainTextBecomesText() {
        XCTAssertEqual(PasteClassifier.classify(.init(plain: "hello world")), [.text("hello world")])
    }
    func testURLBecomesLink() {
        XCTAssertEqual(PasteClassifier.classify(.init(plain: "https://tauri.app/docs")), [.link(url: "https://tauri.app/docs", title: nil)])
    }
    func testURLInsideProseStaysText() {
        XCTAssertEqual(PasteClassifier.classify(.init(plain: "see https://tauri.app")).first?.kind, .text)
    }
    func testTSVBecomesTable() {
        let r = PasteClassifier.classify(.init(plain: "Item\tStatus\nDrag\tDone"))
        XCTAssertEqual(r, [.table([["Item", "Status"], ["Drag", "Done"]])])
    }
    func testHTMLTableWinsOverPlain() {
        let html = "<table><tr><th>A</th><th>B</th></tr><tr><td>1 &amp; 2</td><td><b>3</b></td></tr></table>"
        XCTAssertEqual(PasteClassifier.classify(.init(plain: "A B", html: html)), [.table([["A", "B"], ["1 & 2", "3"]])])
    }
    func testFencedCode() {
        XCTAssertEqual(PasteClassifier.classify(.init(plain: "```swift\nlet a = 1\n```")), [.code("let a = 1", language: "swift")])
    }
    func testImageDataWinsOverText() {
        XCTAssertEqual(PasteClassifier.classify(.init(plain: "x", imageData: Data([1, 2]), imageExtension: "png")).first?.kind, .image)
    }
}

final class ModelTests: XCTestCase {
    func testSnap() {
        var b = Block(kind: .text, x: 13, y: 35, w: 100)
        b.snap()
        XCTAssertEqual([b.x, b.y, b.w], [24, 24, 96])
    }
    func testStatusCycle() {
        XCTAssertEqual(TodoStatus.open.next, .done)
        XCTAssertEqual(TodoStatus.done.next, .deferred)
        XCTAssertEqual(TodoStatus.deferred.next, .open)
    }
    func testOverdue() {
        let old = Todo(text: "x", createdAt: Date(timeIntervalSinceNow: -4 * 86_400))
        XCTAssertTrue(old.isOverdue())
        XCTAssertFalse(Todo(text: "x").isOverdue())
        XCTAssertFalse(Todo(text: "  ", createdAt: Date(timeIntervalSinceNow: -4 * 86_400)).isOverdue())
    }

    func testV1SampleMigratesAndRoundTrips() throws {
        let pad = try PadJSON.decoder.decode(Pad.self, from: sample("pad-v1.json"))
        XCTAssertEqual(pad.v, 2)
        XCTAssertEqual(pad.id, "2026-10-12")
        XCTAssertEqual(pad.tags, ["work"])
        XCTAssertEqual(pad.blocks.count, 4)
        XCTAssertEqual(pad.blocks[0].font, .sans)
        XCTAssertEqual(pad.blocks[0].fontSize, 14)
        XCTAssertEqual(pad.blocks[0].rotation, 0)
        XCTAssertFalse(pad.blocks[0].bold)
        XCTAssertNil(pad.blocks[1].colWidths)
        XCTAssertEqual(pad.todos[2].status, .deferred)
        let data = try PadJSON.encoder.encode(pad)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["v"] as? Int, 2)
        XCTAssertNil(json["tag"])
        XCTAssertEqual(json["tags"] as? [String], ["work"])
        let again = try PadJSON.decoder.decode(Pad.self, from: data)
        XCTAssertEqual(again, pad)
    }

    func testV2SampleRoundTrips() throws {
        let pad = try PadJSON.decoder.decode(Pad.self, from: sample("sheet-v2.json"))
        XCTAssertEqual(pad.id, "2026-10-12-a1b2c3")
        XCTAssertTrue(SheetID.isDated(pad.id))
        XCTAssertEqual(pad.tags, ["work", "q4"])
        XCTAssertEqual(pad.blocks.count, 5)
        XCTAssertEqual(pad.blocks[1].colWidths, [220, 104, 104])
        XCTAssertEqual(pad.blocks[2].rotation, -3)
        XCTAssertEqual(pad.blocks[4].font, .hand)
        XCTAssertEqual(pad.blocks[4].fontSize, 24)
        XCTAssertEqual(pad.blocks[4].rotation, 2.5)
        let again = try PadJSON.decoder.decode(Pad.self, from: PadJSON.encoder.encode(pad))
        XCTAssertEqual(again, pad)
        let eval = TableEvaluator(rows: pad.blocks[1].rows!)
        XCTAssertEqual(eval.display(row: 4, col: 1), "19")
        XCTAssertEqual(eval.display(row: 4, col: 2), "8")
    }

    func testDecodesFractionalSecondsAndMissingFields() throws {
        let json = #"{"v":2,"id":"x","date":null,"title":"T","createdAt":"2026-10-12T08:02:11.123Z","updatedAt":"2026-10-12T08:02:11Z","blocks":[{"id":"b","kind":"text","x":0,"y":0,"w":96,"rotation":540,"fontSize":99}],"todos":[]}"#
        let pad = try PadJSON.decoder.decode(Pad.self, from: Data(json.utf8))
        XCTAssertTrue(pad.pinned)
        XCTAssertEqual(pad.tags, [])
        XCTAssertEqual(pad.blocks[0].rotation, 180)
        XCTAssertEqual(pad.blocks[0].fontSize, 48)
    }

    func testTagNormalisation() {
        XCTAssertEqual(Tags.normalize(" #Work Stuff "), "workstuff")
        XCTAssertEqual(Tags.normalize("##q4"), "q4")
        XCTAssertEqual(Tags.normalize("-x"), "x")
        XCTAssertEqual(Tags.normalized(["Work", "work", "#q4", "", "  "]), ["work", "q4"])
    }

    func testRotationNormalised() {
        XCTAssertEqual(Block.normalizedRotation(0), 0)
        XCTAssertEqual(Block.normalizedRotation(-180), 180)
        XCTAssertEqual(Block.normalizedRotation(180), 180)
        XCTAssertEqual(Block.normalizedRotation(190), -170)
        XCTAssertEqual(Block.normalizedRotation(-190), 170)
        XCTAssertEqual(Block.normalizedRotation(720 + 15), 15)
        var b = Block(kind: .text, x: 0, y: 0, w: 96, rotation: 175)
        b.rotateStep()
        XCTAssertEqual(b.rotation, -170)
    }

    func testResizeCornersAndMinimum() {
        let b = Block(kind: .text, x: 100, y: 100, w: 200, h: 100)
        let br = b.resized(corner: .bottomRight, dx: 40, dy: 20, startHeight: 100, keepAspect: false)
        XCTAssertEqual([br.x, br.y, br.w, br.h], [100, 100, 240, 120])
        let tl = b.resized(corner: .topLeft, dx: 40, dy: 20, startHeight: 100, keepAspect: false)
        XCTAssertEqual([tl.x, tl.y, tl.w, tl.h], [140, 120, 160, 80])
        let tiny = b.resized(corner: .bottomRight, dx: -500, dy: -500, startHeight: 100, keepAspect: false)
        XCTAssertEqual([tiny.w, tiny.h], [48, 24])
        let aspect = b.resized(corner: .bottomRight, dx: 100, dy: 0, startHeight: 100, keepAspect: true)
        XCTAssertEqual([aspect.w, aspect.h], [300, 150])
    }

    func testDuplicateBlockOffsets() {
        let b = Block(id: "a", kind: .text, x: 24, y: 48, w: 96, text: "hi")
        let d = b.duplicated(id: "b")
        XCTAssertEqual([d.x, d.y], [48, 72])
        XCTAssertEqual(d.text, "hi")
        XCTAssertEqual(d.id, "b")
    }

    func testSheetIDs() {
        let id = SheetID.make(for: "2026-10-13")
        XCTAssertTrue(SheetID.isDated(id))
        XCTAssertTrue(SheetID.isValid(id))
        XCTAssertTrue(id.hasPrefix("2026-10-13-"))
        XCTAssertFalse(SheetID.isValid("../etc/passwd"))
        XCTAssertEqual(SheetID.slug("Ideas & Plans!"), "ideas-plans")
        XCTAssertEqual(SheetID.slug("Ideas", existing: ["ideas"]), "ideas-2")
    }

    func testDuplicateSheetCopiesBlocksAndOpenTodos() {
        var p = Pad.dated("2026-10-12", tags: ["work"], title: "Plan")
        p.blocks = [Block(id: "b1", kind: .text, x: 0, y: 0, w: 96, text: "x")]
        p.todos = [Todo(id: "t1", text: "open"), Todo(id: "t2", text: "done", status: .done), Todo(id: "t3", text: "later", status: .deferred)]
        let d = p.duplicate(id: "2026-10-12-zzzzzz")
        XCTAssertEqual(d.title, "Plan copy")
        XCTAssertEqual(d.tags, ["work"])
        XCTAssertEqual(d.blocks.count, 1)
        XCTAssertNotEqual(d.blocks[0].id, "b1")
        XCTAssertEqual(d.todos.map(\.text), ["open"])
        XCTAssertNotEqual(d.todos[0].id, "t1")
    }

    func testCountsAndFooter() {
        var p = Pad.dated("2026-10-12")
        XCTAssertEqual(p.footerLabel, "Nothing here yet")
        p.todos = [Todo(text: "a", status: .done), Todo(text: "b"), Todo(text: "c", status: .deferred), Todo(text: "")]
        XCTAssertEqual(p.countLabel, "1 of 3 done")
        XCTAssertEqual(p.footerLabel, "2 open will carry to tomorrow")
        p.todos = [Todo(text: "a", status: .done)]
        XCTAssertEqual(p.footerLabel, "Nothing to carry. Nice.")
    }
}

final class SearchAndTitleTests: XCTestCase {
    func testSearchHitsBlocksTodosAndTags() {
        var pad = Pad.daily("2026-10-12")
        pad.blocks = [Block(kind: .table, x: 0, y: 0, w: 96, rows: [["Item", "Berlin"]]), Block(kind: .file, x: 0, y: 0, w: 96, name: "Roadmap.pdf")]
        pad.todos = [Todo(text: "Call Mum")]
        pad.tags = ["travel"]
        XCTAssertTrue(pad.matches("berlin"))
        XCTAssertTrue(pad.matches("MUM"))
        XCTAssertTrue(pad.matches("#trav"))
        XCTAssertTrue(pad.matches("roadmap"))
        XCTAssertFalse(pad.matches("paris"))
        XCTAssertTrue(pad.matches(""))
    }
    func testMoveTodo() {
        var pad = Pad.daily("2026-10-12")
        pad.todos = ["a", "b", "c"].map { Todo(id: $0, text: $0) }
        pad.moveTodo("c", before: "a")
        XCTAssertEqual(pad.todos.map(\.id), ["c", "a", "b"])
        pad.moveTodo("c", before: nil)
        XCTAssertEqual(pad.todos.map(\.id), ["a", "b", "c"])
    }
    func testTitleParse() {
        XCTAssertEqual(LinkTitle.parse("<html><head><TITLE>  Tauri &amp;\n  friends </title>"), "Tauri & friends")
        XCTAssertNil(LinkTitle.parse("<p>no title</p>"))
    }
}

final class RolloverTests: XCTestCase {
    func testCarriesOpenAndDeferredNotDone() {
        var prev = Pad.daily("2026-10-11")
        prev.todos = [Todo(text: "a", status: .open), Todo(text: "b", status: .done), Todo(text: "c", status: .deferred), Todo(text: "", status: .open)]
        let next = Rollover.carried(from: prev, into: Pad.daily("2026-10-12"))
        XCTAssertEqual(next.todos.map(\.text), ["a", "c"])
        XCTAssertTrue(next.todos.allSatisfy { $0.status == .open && $0.carriedFrom == "2026-10-11" })
    }

    func testSourcesAreAllSheetsOfLatestEarlierDay() {
        let a = Pad(id: "2026-10-11-aaaaaa", date: "2026-10-11", createdAt: Date(timeIntervalSince1970: 1))
        let b = Pad(id: "2026-10-11-bbbbbb", date: "2026-10-11", createdAt: Date(timeIntervalSince1970: 2))
        let pads = [Pad.daily("2026-10-09"), b, a, Pad.daily("2026-10-13"), Pad(id: "ideas", date: nil, pinned: true)]
        XCTAssertEqual(Set(Rollover.sources(for: "2026-10-12", among: pads).map(\.id)), [a.id, b.id])
        XCTAssertTrue(Rollover.sources(for: "2026-10-01", among: pads).isEmpty)
    }

    func testCarryAcrossSeveralSheetsKeepsCreatedAtAndSource() {
        let created = Date(timeIntervalSince1970: 1_000)
        var a = Pad(id: "2026-10-11-aaaaaa", date: "2026-10-11", createdAt: Date(timeIntervalSince1970: 1))
        a.todos = [Todo(text: "from a", createdAt: created)]
        var b = Pad(id: "2026-10-11-bbbbbb", date: "2026-10-11", createdAt: Date(timeIntervalSince1970: 2))
        b.todos = [Todo(text: "from b", status: .deferred), Todo(text: "done b", status: .done)]
        let next = Rollover.carried(from: [b, a], into: Pad.dated("2026-10-12"))
        XCTAssertEqual(next.todos.map(\.text), ["from a", "from b"])
        XCTAssertEqual(next.todos.map(\.carriedFrom), [a.id, b.id])
        XCTAssertEqual(next.todos[0].createdAt, created)
        XCTAssertTrue(next.todos.allSatisfy { $0.status == .open })
    }

    func testStoreTodayCreatesWithRolloverFromEverySheet() throws {
        let store = try tempStore()
        var a = Pad(id: "2000-01-01-aaaaaa", date: "2000-01-01")
        a.todos = [Todo(text: "carry a")]
        var b = Pad(id: "2000-01-01-bbbbbb", date: "2000-01-01")
        b.todos = [Todo(text: "carry b", status: .deferred), Todo(text: "stay", status: .done)]
        try store.save(a)
        try store.save(b)
        let today = try store.today()
        XCTAssertTrue(SheetID.isDated(today.id))
        XCTAssertEqual(Set(today.todos.map(\.text)), ["carry a", "carry b"])
        XCTAssertNotNil(try store.load(today.id))
        // A second launch opens the same sheet rather than creating another.
        XCTAssertEqual(try store.today().id, today.id)
    }

    func testTodayOpensMostRecentlyUpdatedOfSeveral() throws {
        let store = try tempStore()
        let key = DayKey.key(for: Date())
        let older = Pad(id: "\(key)-aaaaaa", date: key, updatedAt: Date(timeIntervalSinceNow: -100))
        let newer = Pad(id: "\(key)-bbbbbb", date: key, updatedAt: Date())
        try store.save(older, touch: false)
        try store.save(newer, touch: false)
        XCTAssertEqual(try store.today().id, newer.id)
    }

    func testCreateSecondSheetTodayDoesNotCarryAgainAndInheritsTags() throws {
        let store = try tempStore()
        var prev = Pad(id: "2000-01-01-aaaaaa", date: "2000-01-01")
        prev.todos = [Todo(text: "carry")]
        try store.save(prev)
        let first = try store.today()
        XCTAssertEqual(first.todos.count, 1)
        let key = DayKey.key(for: Date())
        let second = try store.create(date: key, tags: ["work", "#Q4"])
        XCTAssertEqual(second.date, key)
        XCTAssertEqual(second.tags, ["work", "q4"])
        XCTAssertTrue(second.todos.isEmpty)
        XCTAssertNotEqual(second.id, first.id)
        XCTAssertEqual(try store.list().filter { $0.date == key }.count, 2)
    }

    func testMoveKeepsIDAndUnpins() throws {
        let store = try tempStore()
        let pinned = try store.createPinned(title: "Ideas")
        XCTAssertEqual(pinned.id, "ideas")
        let moved = try store.move(pinned, to: "2026-10-15")
        XCTAssertFalse(moved.pinned)
        XCTAssertEqual(moved.date, "2026-10-15")
        XCTAssertEqual(moved.id, "ideas")
        XCTAssertEqual(try store.load("ideas")?.date, "2026-10-15")
        XCTAssertEqual(try store.list().count, 1)
    }

    func testSaveDropsEmptyRowsAndRejectsBadIDs() throws {
        let store = try tempStore()
        var p = Pad.dated("2026-10-12")
        p.todos = [Todo(text: "a"), Todo(text: "")]
        try store.save(p)
        XCTAssertEqual(try store.load(p.id)?.todos.count, 1)
        XCTAssertThrowsError(try store.save(Pad(id: "../x", date: nil)))
    }
}

final class FormulaTests: XCTestCase {
    func eval(_ rows: [[String]], _ r: Int, _ c: Int) -> String { TableEvaluator(rows: rows).display(row: r, col: c) }
    func one(_ formula: String, _ extra: [[String]] = []) -> String {
        eval([[formula]] + extra, 0, 0)
    }

    func testArithmeticAndPrecedence() {
        XCTAssertEqual(one("=1+2*3"), "7")
        XCTAssertEqual(one("=(1+2)*3"), "9")
        XCTAssertEqual(one("=-2+5"), "3")
        XCTAssertEqual(one("=--2"), "2")
        XCTAssertEqual(one("=10/4"), "2.5")
        XCTAssertEqual(one("=1/3"), "0.3333")
        XCTAssertEqual(one("= 2 * -(3 - 1)"), "-4")
    }

    func testReferencesAreCaseInsensitive() {
        let rows = [["1", "2", "=a1+B1"]]
        XCTAssertEqual(eval(rows, 0, 2), "3")
    }

    func testFunctionsAndRanges() {
        let rows = [["Item", "Est"], ["a", "6"], ["b", "8"], ["c", ""], ["d", "x"],
                    ["=SUM(B2:B5)", "=AVG(B2:B5)", "=AVERAGE(B2,B3)", "=MIN(B2:B5, 7)", "=MAX(B2:B5)", "=COUNT(B1:B5)", "=sum(B2:B3, 1+1)"]]
        XCTAssertEqual(eval(rows, 5, 0), "14")
        XCTAssertEqual(eval(rows, 5, 1), "7")
        XCTAssertEqual(eval(rows, 5, 2), "7")
        XCTAssertEqual(eval(rows, 5, 3), "6")
        XCTAssertEqual(eval(rows, 5, 4), "8")
        XCTAssertEqual(eval(rows, 5, 5), "2")
        XCTAssertEqual(eval(rows, 5, 6), "16")
    }

    func testCellNumbersStripCurrencyCommasAndPercent() {
        let rows = [["£1,240", " $3 ", "15%", "€2.5", "=SUM(A1:D1)"]]
        XCTAssertEqual(eval(rows, 0, 4), "1,260.5")
        XCTAssertEqual(Formula.parseNumber("-£5"), -5)
        XCTAssertNil(Formula.parseNumber("12abc"))
        XCTAssertNil(Formula.parseNumber(""))
    }

    func testEmptyIsZeroInArithmetic() {
        XCTAssertEqual(eval([["", "=A1+1"]], 0, 1), "1")
    }

    func testErrors() {
        XCTAssertEqual(one("=Z9"), "#REF!")
        XCTAssertEqual(one("=A2", [["1"]]), "1")
        XCTAssertEqual(one("=A3", [["1"]]), "#REF!")
        XCTAssertEqual(one("=SUM(A1:C1)"), "#CYCLE!")
        XCTAssertEqual(one("=1/0"), "#DIV/0!")
        XCTAssertEqual(one("=AVG(B1)"), "#REF!")
        XCTAssertEqual(eval([["=B1", "=A1"]], 0, 0), "#CYCLE!")
        XCTAssertEqual(eval([["=B1", "=A1"]], 0, 1), "#CYCLE!")
        XCTAssertEqual(one("=A1"), "#CYCLE!")
        XCTAssertEqual(one("=1+"), "#ERR!")
        XCTAssertEqual(one("="), "#ERR!")
        XCTAssertEqual(one("=FOO(1)"), "#ERR!")
        XCTAssertEqual(one("=A1:B2"), "#ERR!")
        XCTAssertEqual(one("=1 2"), "#ERR!")
        XCTAssertEqual(one("=(1"), "#ERR!")
        XCTAssertEqual(one("=2#"), "#ERR!")
        XCTAssertEqual(eval([["", "=AVG(A1)"]], 0, 1), "#DIV/0!")
    }

    func testErrorsPropagate() {
        XCTAssertEqual(eval([["=1/0", "=A1+1", "=SUM(A1:A1)"]], 0, 1), "#DIV/0!")
        XCTAssertEqual(eval([["=1/0", "=A1+1", "=SUM(A1:A1)"]], 0, 2), "#DIV/0!")
    }

    func testNumberFormatting() {
        XCTAssertEqual(Formula.format(0), "0")
        XCTAssertEqual(Formula.format(-0.00001), "0")
        XCTAssertEqual(Formula.format(2.50), "2.5")
        XCTAssertEqual(Formula.format(1.23456), "1.2346")
        XCTAssertEqual(Formula.format(999), "999")
        XCTAssertEqual(Formula.format(1000), "1,000")
        XCTAssertEqual(Formula.format(-1234567.891), "-1,234,567.891")
        XCTAssertEqual(Formula.format(999.99999), "1,000")
        XCTAssertEqual(Formula.format(-0.5), "-0.5")
    }

    func testPlainCellsDisplayRaw() {
        let rows = [["Item", "1,240"]]
        XCTAssertEqual(eval(rows, 0, 0), "Item")
        XCTAssertEqual(TableEvaluator(rows: rows).value(row: 0, col: 1), .number(1240))
    }

    func testColumnNamesAndAddresses() {
        XCTAssertEqual(Formula.columnName(0), "A")
        XCTAssertEqual(Formula.columnName(25), "Z")
        XCTAssertEqual(Formula.columnName(26), "AA")
        XCTAssertEqual(Formula.columnIndex("aa"), 26)
        XCTAssertEqual(Formula.address(row: 2, col: 1), "B3")
    }

    func testColumnWidths() {
        let b = Block(kind: .table, x: 0, y: 0, w: 360, rows: [["a", "b", "c"]])
        XCTAssertEqual(TableLayout.widths(for: b), [120, 120, 120])
        var c = b
        c.colWidths = [200, 10]
        XCTAssertEqual(TableLayout.widths(for: c), [200, 40, 40])
        XCTAssertEqual(TableLayout.fitWidth(column: 0, rows: [["abcd"], ["ab"]]), 50)
        XCTAssertEqual(TableLayout.fitWidth(column: 0, rows: [[""]]), 40)
        XCTAssertEqual(TableLayout.fitWidth(column: 0, rows: [[String(repeating: "x", count: 200)]]), 480)
        XCTAssertEqual(TableLayout.fitWidth(column: 1, rows: [["1000", "=A1*1000"]]), 88) // "1,000,000"
    }
}

final class DatePhraseTests: XCTestCase {
    // 2026-10-13 is a Tuesday.
    let today = "2026-10-13"
    func parse(_ s: String) -> String? { DatePhrase.parse(s, today: today) }

    func testRelativeWords() {
        XCTAssertEqual(parse("today"), "2026-10-13")
        XCTAssertEqual(parse(" Tomorrow "), "2026-10-14")
        XCTAssertEqual(parse("yesterday"), "2026-10-12")
        XCTAssertEqual(parse("+3"), "2026-10-16")
        XCTAssertEqual(parse("-2"), "2026-10-11")
        XCTAssertEqual(parse("+30"), "2026-11-12")
    }

    func testWeekdaysNextOccurrenceTodayCounts() {
        XCTAssertEqual(parse("tue"), "2026-10-13")
        XCTAssertEqual(parse("tuesday"), "2026-10-13")
        XCTAssertEqual(parse("wed"), "2026-10-14")
        XCTAssertEqual(parse("Monday"), "2026-10-19")
        XCTAssertEqual(parse("sun"), "2026-10-18")
        XCTAssertNil(parse("mo"))
    }

    func testDayMonthForms() {
        XCTAssertEqual(parse("15 oct"), "2026-10-15")
        XCTAssertEqual(parse("oct 15"), "2026-10-15")
        XCTAssertEqual(parse("15 October"), "2026-10-15")
        XCTAssertEqual(parse("15/10"), "2026-10-15")
        XCTAssertEqual(parse("1/2/2027"), "2027-02-01")
        XCTAssertEqual(parse("2026-10-15"), "2026-10-15")
        XCTAssertEqual(parse("3 jan 2027"), "2027-01-03")
    }

    func testRejectsNonsense() {
        XCTAssertNil(parse(""))
        XCTAssertNil(parse("31 feb"))
        XCTAssertNil(parse("2026-13-01"))
        XCTAssertNil(parse("next week"))
        XCTAssertNil(parse("32/10"))
    }

    func testMonthGridMondayFirst() {
        let weeks = MonthGrid.weeks(year: 2026, month: 10)
        // 1 Oct 2026 is a Thursday: three leading blanks.
        XCTAssertEqual(weeks[0], [nil, nil, nil, "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"])
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
        XCTAssertEqual(weeks.flatMap { $0 }.compactMap { $0 }.count, 31)
        XCTAssertEqual(MonthGrid.shift(year: 2026, month: 12, by: 1).year, 2027)
        XCTAssertEqual(MonthGrid.shift(year: 2026, month: 1, by: -1).month, 12)
    }
}

final class SidebarTests: XCTestCase {
    let today = "2026-10-13"

    func pad(_ id: String, _ date: String?, tags: [String] = [], updated: TimeInterval = 0, pinned: Bool = false) -> Pad {
        Pad(id: id, date: date, title: id, tags: tags, pinned: pinned, createdAt: Date(timeIntervalSince1970: updated), updatedAt: Date(timeIntervalSince1970: updated))
    }

    func testDayLabels() {
        XCTAssertEqual(DayLabel.group("2026-10-13", today: today), "Today")
        XCTAssertEqual(DayLabel.group("2026-10-12", today: today), "Yesterday")
        XCTAssertEqual(DayLabel.group("2026-10-14", today: today), "Tomorrow")
        XCTAssertEqual(DayLabel.group("2026-10-08", today: today), "Thursday")
        XCTAssertEqual(DayLabel.group("2026-10-07", today: today), "Wednesday")
        XCTAssertEqual(DayLabel.group("2026-10-06", today: today), "Tue 6 Oct")
        XCTAssertEqual(DayLabel.group("2026-10-20", today: today), "Tue 20 Oct")
        XCTAssertEqual(DayLabel.shortDate("2026-10-07"), "7 Oct")
        XCTAssertEqual(DayLabel.longDate("2026-10-12"), "Mon 12 Oct 2026")
        XCTAssertEqual(DayLabel.longDate(nil), "Pinned")
    }

    func testByDayGroupsNewestFirstAndSkipsPinned() {
        let pads = [pad("a", "2026-10-12", updated: 1), pad("b", "2026-10-13", updated: 1), pad("c", "2026-10-13", updated: 5), pad("p", nil, pinned: true)]
        let groups = Sidebar.byDay(pads, today: today)
        XCTAssertEqual(groups.map(\.label), ["Today", "Yesterday"])
        XCTAssertEqual(groups[0].sheets.map(\.id), ["c", "b"])
        XCTAssertEqual(groups[0].detail, "13 Oct")
        XCTAssertEqual(Sidebar.pinned(pads).map(\.id), ["p"])
    }

    func testByTagSorts() {
        let pads = [pad("a", "2026-10-12", tags: ["zeta", "work"], updated: 1),
                    pad("b", "2026-10-13", tags: ["work"], updated: 2),
                    pad("c", "2026-10-11", tags: ["alpha"], updated: 9),
                    pad("d", "2026-10-10", updated: 3)]
        XCTAssertEqual(Sidebar.byTag(pads, sort: .alphabetical).map(\.label), ["#alpha", "#work", "#zeta", "Untagged"])
        XCTAssertEqual(Sidebar.byTag(pads, sort: .mostSheets).map(\.label), ["#work", "#alpha", "#zeta", "Untagged"])
        XCTAssertEqual(Sidebar.byTag(pads, sort: .recentlyUsed).map(\.label), ["#alpha", "#work", "#zeta", "Untagged"])
        let work = Sidebar.byTag(pads, sort: .alphabetical)[1]
        XCTAssertEqual(work.sheets.map(\.id), ["b", "a"])
        XCTAssertEqual(work.detail, "2")
    }

    func testTagSuggestions() {
        let pads = [pad("a", "2026-10-12", tags: ["work", "writing"]), pad("b", "2026-10-13", tags: ["work"]), pad("c", nil, tags: ["home"])]
        XCTAssertEqual(Tags.suggestions(prefix: "w", pads: pads).map(\.tag), ["work", "writing"])
        XCTAssertEqual(Tags.suggestions(prefix: "#W", pads: pads).first?.count, 2)
        XCTAssertEqual(Tags.suggestions(prefix: "", pads: pads, excluding: ["work"]).map(\.tag), ["home", "writing"])
    }
}

final class TodoSortTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 10 * 86_400)
    var todos: [Todo] {
        [Todo(id: "1", text: "banana", status: .done, createdAt: Date(timeIntervalSince1970: 5 * 86_400)),
         Todo(id: "2", text: "apple", status: .deferred, createdAt: Date(timeIntervalSince1970: 9 * 86_400)),
         Todo(id: "3", text: "Cherry", status: .open, createdAt: Date(timeIntervalSince1970: 1 * 86_400)),
         Todo(id: "4", text: "date", status: .open, createdAt: Date(timeIntervalSince1970: 9 * 86_400))]
    }
    func ids(_ mode: TodoSortMode, sinks: Bool) -> [String] {
        TodoSort.sorted(todos, mode: mode, doneSinks: sinks, now: now).map(\.id)
    }

    func testManual() {
        XCTAssertEqual(ids(.manual, sinks: false), ["1", "2", "3", "4"])
        XCTAssertEqual(ids(.manual, sinks: true), ["2", "3", "4", "1"])
    }
    func testOpenFirst() {
        XCTAssertEqual(ids(.openFirst, sinks: false), ["3", "4", "2", "1"])
    }
    func testOverdueFirst() {
        XCTAssertEqual(ids(.overdueFirst, sinks: true), ["3", "4", "2", "1"])
    }
    func testAlphabetical() {
        XCTAssertEqual(ids(.alphabetical, sinks: false), ["2", "1", "3", "4"])
        XCTAssertEqual(ids(.alphabetical, sinks: true), ["2", "3", "4", "1"])
    }
    func testOldestFirst() {
        XCTAssertEqual(ids(.oldestFirst, sinks: false), ["3", "1", "2", "4"])
    }
    func testEmptyRowsStayLast() {
        let list = [Todo(id: "e", text: ""), Todo(id: "a", text: "a")]
        XCTAssertEqual(TodoSort.sorted(list, mode: .alphabetical, doneSinks: true).map(\.id), ["a", "e"])
    }
}

final class ExportTests: XCTestCase {
    func v2() throws -> Pad { try PadJSON.decoder.decode(Pad.self, from: sample("sheet-v2.json")) }

    func testTodoMarkdownDefaults() throws {
        let md = ExportMarkdown.todos([try v2()])
        XCTAssertEqual(md, """
        ## Sprint planning, odds and ends, Mon 12 Oct 2026

        - [ ] Draft release notes 0.3
        - [ ] Renew passport (deferred)

        """)
    }

    func testTodoMarkdownIncludeDoneAndSections() throws {
        var pinned = Pad(id: "ideas", date: nil, title: "", pinned: true)
        pinned.todos = [Todo(text: "Think", status: .open)]
        var empty = Pad.dated("2026-10-13")
        empty.todos = [Todo(text: "x", status: .done)]
        let md = ExportMarkdown.todos([pinned, try v2(), empty], includeDone: true, includeDeferred: false)
        XCTAssertEqual(md, """
        ## Untitled sheet, Tue 13 Oct 2026

        - [x] x

        ## Sprint planning, odds and ends, Mon 12 Oct 2026

        - [x] Reply to Priya re: contract
        - [ ] Draft release notes 0.3

        ## Untitled sheet, Pinned

        - [ ] Think

        """)
    }

    func testEveryOpenOmitsEmptySections() throws {
        var done = Pad.dated("2026-10-13")
        done.todos = [Todo(text: "x", status: .done)]
        let md = ExportMarkdown.todos([done, try v2()], includeDone: true, includeDeferred: false, openOnly: true)
        XCTAssertEqual(md, "## Sprint planning, odds and ends, Mon 12 Oct 2026\n\n- [ ] Draft release notes 0.3\n")
    }

    func testEverythingMarkdown() throws {
        let md = ExportMarkdown.sheet(try v2())
        XCTAssertTrue(md.hasPrefix("# Sprint planning, odds and ends\n\n_Mon 12 Oct 2026 · #work #q4_\n\nStandup\n"))
        XCTAssertTrue(md.contains("**Release 0.3**\n\n| Item | Est (h) | Spent (h) |\n| --- | --- | --- |\n| Block toolbar | 6 | 5 |"))
        XCTAssertTrue(md.contains("| Total | 19 | 8 |"))
        XCTAssertTrue(md.contains("[Q4-roadmap.pdf](assets/q4-roadmap.pdf)"))
        XCTAssertTrue(md.contains("[Tauri v2 window customisation](https://tauri.app)"))
        XCTAssertTrue(md.hasSuffix("## To-do\n\n- [x] Reply to Priya re: contract\n- [ ] Draft release notes 0.3\n- [ ] Renew passport (deferred)"))
        // Reading order: y then x. b5 (y 192) comes before the table (y 216).
        let hand = md.range(of: "Ask Priya")!.lowerBound
        let table = md.range(of: "**Release 0.3**")!.lowerBound
        XCTAssertLessThan(hand, table)
    }

    func testMarkdownBlockKinds() {
        var p = Pad(id: "x", date: nil, title: "Kinds", pinned: true)
        p.blocks = [Block(kind: .code, x: 0, y: 0, w: 96, text: "let a = 1", language: "swift"),
                    Block(kind: .divider, x: 0, y: 24, w: 96),
                    Block(kind: .image, x: 0, y: 48, w: 96, asset: "assets/a.png", caption: "Cat"),
                    Block(kind: .table, x: 0, y: 72, w: 96, rows: [["A|B"]])]
        let md = ExportMarkdown.sheet(p)
        XCTAssertEqual(md, "# Kinds\n\n_Pinned_\n\n```swift\nlet a = 1\n```\n\n---\n\n![Cat](assets/a.png)\n\n| A\\|B |\n| --- |")
    }

    func testArchiveRoundTripWithAssets() throws {
        let src = try tempStore()
        var pad = try v2()
        let asset = try src.storeAsset(Data([0, 1, 2, 250]), ext: "bin")
        pad.blocks.append(Block(kind: .image, x: 0, y: 600, w: 96, asset: asset))
        try src.save(pad, touch: false)
        let archive = ScratchpadArchive.build(sheets: try src.list(), store: src)
        XCTAssertEqual(archive.assets.count, 1) // q4-roadmap.pdf is not in the store and is skipped.
        XCTAssertEqual(archive.assets[asset], Data([0, 1, 2, 250]).base64EncodedString())
        let data = try archive.encoded()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["format"] as? String, "scratchpad-archive")
        XCTAssertEqual(json["v"] as? Int, 1)

        let dst = try tempStore()
        var existing = pad
        existing.title = "old"
        try dst.save(existing, touch: false)
        let result = try ScratchpadArchive.decode(data).importInto(dst)
        XCTAssertEqual(result.sheets, 1)
        XCTAssertEqual(result.overwritten, 1)
        XCTAssertEqual(result.assetsWritten, 1)
        XCTAssertEqual(try dst.load(pad.id)?.title, pad.title)
        XCTAssertEqual(try Data(contentsOf: dst.assetURL(asset)), Data([0, 1, 2, 250]))
        // Assets are only written when missing.
        XCTAssertEqual(try ScratchpadArchive.decode(data).importInto(dst).assetsWritten, 0)
    }

    func testArchiveImportSkipsUnsafePaths() throws {
        let archive = ScratchpadArchive(sheets: [Pad(id: "../evil", date: nil)], assets: ["assets/../../x": "AA==", "other/x": "AA==", "assets/ok.txt": "AA=="])
        let store = try tempStore()
        let r = try ScratchpadArchive.decode(archive.encoded()).importInto(store)
        XCTAssertEqual(r.sheets, 0)
        XCTAssertEqual(r.assetsWritten, 1)
        XCTAssertEqual(r.skipped, 3)
        XCTAssertThrowsError(try ScratchpadArchive.decode(Data("{}".utf8)))
    }

    func testJSONExportIsArrayOfV2Sheets() throws {
        let data = try ExportJSON.sheets([try v2()])
        let arr = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(arr.first?["v"] as? Int, 2)
    }

    func testTodoScopes() throws {
        let a = Pad.dated("2026-10-13"), b = Pad.dated("2026-10-13"), c = Pad.dated("2026-10-12")
        XCTAssertEqual(TodoExportScope.todaysSheets.sheets(current: c, all: [a, b, c], today: "2026-10-13").count, 2)
        XCTAssertEqual(TodoExportScope.thisSheet.sheets(current: c, all: [a, b, c], today: "2026-10-13").map(\.id), [c.id])
    }
}
