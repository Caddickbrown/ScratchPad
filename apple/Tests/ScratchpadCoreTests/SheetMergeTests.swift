import XCTest
@testable import ScratchpadCore

/// Review 17 Nov, ScratchPad 5 and 8: an iPad and an iPhone both have the sheet open; the stale one's
/// next keystroke wrote its whole copy over the other's to-dos. A save now merges the other device's
/// changes in first, and ⌘K "Today" only makes a sheet when "New sheet each day" is on.
final class SheetMergeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func pad(_ todos: [Todo], title: String = "Plan", tags: [String] = ["work"], blocks: [Block] = []) -> Pad {
        Pad(id: "p", date: "2026-11-18", title: title, tags: tags, createdAt: t0, updatedAt: t0, blocks: blocks, todos: todos)
    }
    private func todo(_ id: String, _ text: String, _ status: TodoStatus = .open) -> Todo {
        Todo(id: id, text: text, status: status, createdAt: t0)
    }

    func testTheOtherDevicesNewTodosSurviveAStaleKeystroke() {
        let base = pad([todo("a", "Milk")])
        let theirs = pad([todo("a", "Milk"), todo("b", "Eggs"), todo("c", "Bread")])
        var ours = base
        ours.todos[0].text = "Milk x2"
        let merged = SheetMerge.merge(base: base, ours: ours, theirs: theirs)
        XCTAssertEqual(merged.todos.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(merged.todos[0].text, "Milk x2")
    }

    func testEachSideKeepsWhatOnlyItChanged() {
        let base = pad([todo("a", "Milk"), todo("b", "Eggs"), todo("c", "Bread")])
        var ours = base
        ours.todos.removeAll { $0.id == "b" }          // deleted here
        ours.todos.append(todo("d", "Jam"))            // added here
        ours.title = "Shopping"
        var theirs = base
        theirs.todos[2].status = .done                 // ticked there
        theirs.tags = ["home"]
        let merged = SheetMerge.merge(base: base, ours: ours, theirs: theirs)
        XCTAssertEqual(merged.todos.map(\.id), ["a", "c", "d"])
        XCTAssertEqual(merged.todos.first { $0.id == "c" }?.status, .done)
        XCTAssertEqual(merged.title, "Shopping")
        XCTAssertEqual(merged.tags, ["home"])
    }

    func testDeletedThereButEditedHereIsKept() {
        let base = pad([todo("a", "Milk")])
        var ours = base
        ours.todos[0].text = "Oat milk"
        let theirs = pad([])
        XCTAssertEqual(SheetMerge.merge(base: base, ours: ours, theirs: theirs).todos.map(\.text), ["Oat milk"])
        // Deleted there and untouched here: it goes.
        XCTAssertTrue(SheetMerge.merge(base: base, ours: base, theirs: theirs).todos.isEmpty)
    }

    func testBlocksMergeTheSameWay() {
        let b1 = Block(id: "b1", kind: .text, x: 0, y: 0, w: 96, text: "Hi")
        let b2 = Block(id: "b2", kind: .text, x: 0, y: 48, w: 96, text: "There")
        let base = pad([], blocks: [b1])
        var ours = base
        ours.blocks[0].text = "Hello"
        let theirs = pad([], blocks: [b1, b2])
        let merged = SheetMerge.merge(base: base, ours: ours, theirs: theirs)
        XCTAssertEqual(merged.blocks.map(\.id), ["b1", "b2"])
        XCTAssertEqual(merged.blocks[0].text, "Hello")
    }

    func testNothingChangedThereIsJustOurs() {
        let base = pad([todo("a", "Milk")])
        var ours = base
        ours.todos.append(todo("b", "Eggs"))
        XCTAssertEqual(SheetMerge.merge(base: base, ours: ours, theirs: base), ours)
    }

    func testCommandTodayOpensTodaysSheetAndMakesOneOnlyWhenAsked() {
        let old = Pad(id: "o", date: "2026-11-17", createdAt: t0, updatedAt: t0)
        let a = Pad(id: "a", date: "2026-11-18", createdAt: t0, updatedAt: t0)
        let b = Pad(id: "b", date: "2026-11-18", createdAt: t0, updatedAt: t0.addingTimeInterval(60))
        XCTAssertEqual(Resume.today(among: [old, a, b], today: "2026-11-18", newSheetEachDay: false), .open("b"))
        XCTAssertEqual(Resume.today(among: [old], today: "2026-11-18", newSheetEachDay: false), .noSheet)
        XCTAssertEqual(Resume.today(among: [old], today: "2026-11-18", newSheetEachDay: true), .makeToday)
        XCTAssertEqual(Resume.today(among: [old, a], today: "2026-11-18", newSheetEachDay: true), .open("a"))
    }
}
