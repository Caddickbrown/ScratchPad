import Foundation

/// To-do column view order (spec section 5). A per-device preference, never written to the file
/// except when a drag under a non-manual sort commits the current view order.
public enum TodoSortMode: String, CaseIterable, Identifiable, Sendable {
    case manual, openFirst, overdueFirst, alphabetical, oldestFirst
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .manual: return "Manual (drag)"
        case .openFirst: return "Open first"
        case .overdueFirst: return "Overdue first"
        case .alphabetical: return "A to Z"
        case .oldestFirst: return "Oldest first"
        }
    }
}

public enum TodoSort {
    static func rank(_ s: TodoStatus) -> Int {
        switch s { case .open: return 0; case .deferred: return 1; case .done: return 2 }
    }

    /// Stable sort. `doneSinks` pushes done rows to the bottom in every mode, Manual included.
    /// Empty rows always stay last.
    public static func sorted(_ todos: [Todo], mode: TodoSortMode, doneSinks: Bool, now: Date = Date()) -> [Todo] {
        func compare(_ a: Todo, _ b: Todo) -> Int {
            if a.isFilled != b.isFilled { return a.isFilled ? -1 : 1 }
            if doneSinks {
                let da = a.status == .done ? 1 : 0, db = b.status == .done ? 1 : 0
                if da != db { return da - db }
            }
            switch mode {
            case .manual: return 0
            case .openFirst: return rank(a.status) - rank(b.status)
            case .overdueFirst:
                let oa = a.isOverdue(now: now) ? 0 : 1, ob = b.isOverdue(now: now) ? 0 : 1
                if oa != ob { return oa - ob }
                return rank(a.status) - rank(b.status)
            case .alphabetical:
                switch a.text.localizedCaseInsensitiveCompare(b.text) {
                case .orderedAscending: return -1
                case .orderedDescending: return 1
                case .orderedSame: return 0
                }
            case .oldestFirst:
                return a.createdAt < b.createdAt ? -1 : (a.createdAt > b.createdAt ? 1 : 0)
            }
        }
        return todos.enumerated().sorted { x, y in
            let c = compare(x.element, y.element)
            return c != 0 ? c < 0 : x.offset < y.offset
        }.map(\.element)
    }

    /// The view order written into the file before a drag under a non-manual sort switches to Manual.
    public static func committingViewOrder(_ pad: Pad, mode: TodoSortMode, doneSinks: Bool, now: Date = Date()) -> Pad {
        var p = pad
        p.todos = sorted(pad.todos, mode: mode, doneSinks: doneSinks, now: now)
        return p
    }
}
