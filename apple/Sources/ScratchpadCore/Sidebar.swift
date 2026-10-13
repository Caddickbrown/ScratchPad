import Foundation

/// Sidebar grouping (spec section 2). Same rules as linux/src/model.ts.
public struct SheetGroup: Identifiable, Equatable, Sendable {
    /// Day key, tag, or "" for Untagged.
    public var id: String
    public var label: String
    /// Short date for day groups, sheet count for tag groups.
    public var detail: String
    public var sheets: [Pad]
}

public enum TagSort: String, CaseIterable, Identifiable, Sendable {
    case alphabetical, mostSheets, recentlyUsed
    public var id: String { rawValue }
    public var label: String {
        switch self { case .alphabetical: return "A to Z"; case .mostSheets: return "Most sheets"; case .recentlyUsed: return "Recently used" }
    }
}

public enum SidebarMode: String, CaseIterable, Identifiable, Sendable {
    case byDay, byTag
    public var id: String { rawValue }
    public var label: String { self == .byDay ? "By day" : "By tag" }
}

public enum Sidebar {
    /// Dated sheets grouped by day, newest first. Pinned sheets have their own section.
    public static func byDay(_ pads: [Pad], today: String) -> [SheetGroup] {
        let dated = pads.filter { !$0.pinned && $0.date != nil }.sorted(by: PadStore.newestFirst)
        var groups: [SheetGroup] = []
        for p in dated {
            let d = p.date!
            if groups.last?.id == d { groups[groups.count - 1].sheets.append(p) }
            else { groups.append(SheetGroup(id: d, label: DayLabel.group(d, today: today), detail: DayLabel.shortDate(d), sheets: [p])) }
        }
        return groups
    }

    /// One group per tag (a sheet appears under each of its tags), Untagged last.
    public static func byTag(_ pads: [Pad], sort: TagSort) -> [SheetGroup] {
        var order: [String] = []
        var members: [String: [Pad]] = [:]
        var recent: [String: Date] = [:]
        for p in pads {
            for t in p.tags.isEmpty ? [""] : p.tags {
                if members[t] == nil { order.append(t) }
                members[t, default: []].append(p)
                recent[t] = max(recent[t] ?? .distantPast, p.updatedAt)
            }
        }
        let keys = order.sorted { a, b in
            if a.isEmpty != b.isEmpty { return b.isEmpty }
            switch sort {
            case .alphabetical: return a < b
            case .mostSheets:
                let ca = members[a]!.count, cb = members[b]!.count
                return ca != cb ? ca > cb : a < b
            case .recentlyUsed:
                let ra = recent[a]!, rb = recent[b]!
                return ra != rb ? ra > rb : a < b
            }
        }
        return keys.map { k in
            let sheets = members[k]!.sorted(by: PadStore.newestFirst)
            return SheetGroup(id: k, label: k.isEmpty ? "Untagged" : "#\(k)", detail: String(sheets.count), sheets: sheets)
        }
    }

    public static func pinned(_ pads: [Pad]) -> [Pad] {
        pads.filter { $0.pinned }.sorted { $0.displayTitle.lowercased() < $1.displayTitle.lowercased() }
    }

    /// Day keys that have at least one sheet, for the dots under the date picker.
    public static func datesWithSheets(_ pads: [Pad]) -> Set<String> { Set(pads.compactMap(\.date)) }
}
