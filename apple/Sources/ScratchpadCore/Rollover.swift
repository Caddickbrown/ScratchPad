import Foundation

/// Midnight rule from the components board: open and deferred rows copy to the new pad, done rows stay.
/// Deferred means "carry to tomorrow", so a carried row arrives as open. createdAt is kept so overdue
/// still counts from the day the row was first written.
public enum Rollover {
    public static func carried(from previous: Pad, into target: Pad) -> Pad {
        var next = target
        let carry = previous.todos
            .filter { !$0.text.isEmpty && $0.status != .done }
            .map { Todo(id: UUID().uuidString, text: $0.text, status: .open, createdAt: $0.createdAt, carriedFrom: previous.id) }
        next.todos = carry + next.todos
        return next
    }

    /// Picks the dated pad before `day` to roll over from. Pinned pads never roll.
    public static func source(for day: String, among pads: [Pad]) -> Pad? {
        pads.filter { $0.date != nil && $0.date! < day && !$0.pinned }
            .max { $0.date! < $1.date! }
    }
}
