import Foundation

/// Carry-over (spec section 5): when today's first sheet is created, open and deferred non-empty rows from
/// every sheet of the latest earlier dated day are copied as open. createdAt is kept so overdue still counts
/// from the day the row was first written; carriedFrom is the source sheet id. Done rows stay.
public enum Rollover {
    public static func carried(from sources: [Pad], into target: Pad) -> Pad {
        var next = target
        let carry = sources.sorted { $0.createdAt < $1.createdAt }.flatMap { source in
            source.todos
                .filter { $0.isFilled && $0.status != .done }
                .map { Todo(id: UUID().uuidString, text: $0.text, status: .open, createdAt: $0.createdAt, carriedFrom: source.id) }
        }
        next.todos = carry + next.todos
        return next
    }

    public static func carried(from previous: Pad, into target: Pad) -> Pad {
        carried(from: [previous], into: target)
    }

    /// Every unpinned sheet of the latest date strictly before `day`.
    public static func sources(for day: String, among pads: [Pad]) -> [Pad] {
        let earlier = pads.filter { !$0.pinned && $0.date != nil && $0.date! < day }
        guard let latest = earlier.compactMap(\.date).max() else { return [] }
        return earlier.filter { $0.date == latest }
    }

    /// v0.1 single-source helper: the most recently updated sheet of the latest earlier day.
    public static func source(for day: String, among pads: [Pad]) -> Pad? {
        sources(for: day, among: pads).max { $0.updatedAt < $1.updatedAt }
    }
}

/// What coming back to the app should do, once anything typed has been saved.
public enum Resume {
    public enum Step: Equatable, Sendable {
        case nothing
        /// Another device saved this sheet since it was opened.
        case load(Pad)
        case openToday
    }

    /// A new day moves on from the sheet that was today's, and leaves any other sheet where it is.
    /// A sheet that's newer on disk replaces the copy in memory, which would otherwise overwrite it
    /// at the next keystroke.
    public static func step(current: Pad?, onDisk: Pad?, lastToday: String, today: String) -> Step {
        guard let current else { return .openToday }
        if lastToday != today, current.date == lastToday { return .openToday }
        if let onDisk, onDisk.updatedAt > current.updatedAt { return .load(onDisk) }
        return .nothing
    }
}
