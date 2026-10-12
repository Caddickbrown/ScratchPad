import XCTest
@testable import ScratchpadCore

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
    }
    func testRoundTripsSample() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("shared/samples/2026-10-12.json")
        let pad = try PadJSON.decoder.decode(Pad.self, from: Data(contentsOf: url))
        XCTAssertEqual(pad.blocks.count, 4)
        XCTAssertEqual(pad.todos[2].status, .deferred)
        let again = try PadJSON.decoder.decode(Pad.self, from: PadJSON.encoder.encode(pad))
        XCTAssertEqual(again, pad)
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
    func testSourceIsLatestEarlierDatedPad() {
        let pads = [Pad.daily("2026-10-09"), Pad.daily("2026-10-11"), Pad.daily("2026-10-13"), Pad(id: "ideas", date: nil, pinned: true)]
        XCTAssertEqual(Rollover.source(for: "2026-10-12", among: pads)?.id, "2026-10-11")
    }
    func testStoreCreatesTodayWithRollover() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try PadStore(root: tmp)
        var prev = Pad.daily("2000-01-01")
        prev.todos = [Todo(text: "carry me", status: .open)]
        try store.save(prev)
        let today = try store.today()
        XCTAssertEqual(today.todos.first?.text, "carry me")
        XCTAssertNotNil(try store.load(today.id))
    }
}
