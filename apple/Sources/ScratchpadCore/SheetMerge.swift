import Foundation

/// Two devices with the same sheet open (an iPad and an iPhone on iCloud): the one that last read the
/// file is stale, and saving its whole copy would write over what the other added. Before a save, when
/// the file changed since this device read it, the three versions are merged: `base` is what this device
/// last read or wrote, `ours` the copy in memory, `theirs` the file now.
///
/// To-dos and blocks merge by id: what only one side changed, added or deleted wins; when both changed
/// the same one, ours wins (it's what the person in front of this device just did). Something deleted
/// there but edited here is kept. The title, tags, date and pinned state go the same way field by field.
/// Order follows theirs, with ours' new items after.
public enum SheetMerge {
    /// `pad` as the file holds it: dates to the second, as `PadJSON` writes them. The copy in memory
    /// keeps a to-do made this session to the nanosecond, so compared whole it never equals the file's
    /// copy of it, and a to-do deleted here came back from the other side (review L49).
    /// Only the dates change; everything else (the core's `extras` too) is kept as it is.
    public static func asFiled(_ pad: Pad) -> Pad {
        func second(_ d: Date) -> Date { Date(timeIntervalSince1970: d.timeIntervalSince1970.rounded(.down)) }
        var p = pad
        p.createdAt = second(p.createdAt)
        p.updatedAt = second(p.updatedAt)
        for i in p.todos.indices { p.todos[i].createdAt = second(p.todos[i].createdAt) }
        return p
    }

    /// Whether the file changed since this device read or wrote `base`: by what it holds, not by two
    /// devices' clocks, which can't tell a save elsewhere in the same second (review L50).
    public static func changedSince(base: Pad, disk: Pad) -> Bool {
        var a = asFiled(base), b = asFiled(disk)
        a.updatedAt = b.updatedAt
        return a != b
    }

    public static func merge(base: Pad, ours: Pad, theirs: Pad) -> Pad {
        let base = asFiled(base), ours = asFiled(ours), theirs = asFiled(theirs)
        if ours == base { return theirs }
        if theirs == base { return ours }
        var out = theirs
        func pick<T: Equatable>(_ k: KeyPath<Pad, T>) -> T { ours[keyPath: k] != base[keyPath: k] ? ours[keyPath: k] : theirs[keyPath: k] }
        out.title = pick(\.title)
        out.tags = pick(\.tags)
        out.date = pick(\.date)
        out.pinned = pick(\.pinned)
        out.todos = items(base.todos, ours.todos, theirs.todos)
        out.blocks = items(base.blocks, ours.blocks, theirs.blocks)
        return out
    }

    static func items<T: Identifiable & Equatable>(_ base: [T], _ ours: [T], _ theirs: [T]) -> [T] where T.ID == String {
        let b = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let o = Dictionary(ours.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let t = Set(theirs.map(\.id))
        var out: [T] = []
        for item in theirs {
            if let mine = o[item.id] {
                // Both have it: ours if we changed it, else theirs.
                out.append(b[item.id].map { mine != $0 } ?? true ? mine : item)
            } else if let was = b[item.id], was == item {
                continue  // deleted here, untouched there
            } else {
                out.append(item)  // added there, or changed there after we deleted it
            }
        }
        for item in ours where !t.contains(item.id) {
            if let was = b[item.id], was == item { continue }  // deleted there, untouched here
            out.append(item)  // added here, or edited here after they deleted it
        }
        return out
    }
}
