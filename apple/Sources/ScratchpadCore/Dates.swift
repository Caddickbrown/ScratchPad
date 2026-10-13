import Foundation

/// Calendar arithmetic on `YYYY-MM-DD` day keys. Works in a fixed UTC Gregorian calendar so DST never
/// shifts a day; the local timezone only matters when turning "now" into today's key (`DayKey`).
public enum DayMath {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    public struct Parts: Equatable, Sendable { public var year: Int, month: Int, day: Int }

    public static func parts(_ key: String) -> Parts? {
        let bits = key.split(separator: "-")
        guard bits.count == 3, bits[0].count == 4, let y = Int(bits[0]), let m = Int(bits[1]), let d = Int(bits[2]) else { return nil }
        return valid(year: y, month: m, day: d) ? Parts(year: y, month: m, day: d) : nil
    }

    public static func key(year: Int, month: Int, day: Int) -> String? {
        guard valid(year: year, month: month, day: day) else { return nil }
        return format(year, month, day)
    }

    static func format(_ y: Int, _ m: Int, _ d: Int) -> String {
        func pad(_ v: Int, _ n: Int) -> String { let s = String(v); return String(repeating: "0", count: max(0, n - s.count)) + s }
        return "\(pad(y, 4))-\(pad(m, 2))-\(pad(d, 2))"
    }

    public static func valid(year: Int, month: Int, day: Int) -> Bool {
        guard (1...9999).contains(year), (1...12).contains(month), day >= 1 else { return false }
        return day <= daysIn(year: year, month: month)
    }

    public static func daysIn(year: Int, month: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    static func date(_ key: String) -> Date? {
        guard let p = parts(key) else { return nil }
        return calendar.date(from: DateComponents(year: p.year, month: p.month, day: p.day, hour: 12))
    }

    static func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return format(c.year!, c.month!, c.day!)
    }

    public static func add(days n: Int, to key: String) -> String? {
        guard let d = date(key), let r = calendar.date(byAdding: .day, value: n, to: d) else { return nil }
        return self.key(r)
    }

    /// Days from `a` to `b` (b - a).
    public static func distance(from a: String, to b: String) -> Int? {
        guard let da = date(a), let db = date(b) else { return nil }
        return calendar.dateComponents([.day], from: da, to: db).day
    }

    /// 0 = Monday ... 6 = Sunday.
    public static func weekdayMondayFirst(_ key: String) -> Int? {
        guard let d = date(key) else { return nil }
        return (calendar.component(.weekday, from: d) + 5) % 7
    }
}

/// English labels used by the sidebar, the header and the exports.
public enum DayLabel {
    public static let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    public static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    static func short(_ s: String) -> String { String(s.prefix(3)) }

    /// `12 Oct`.
    public static func shortDate(_ key: String) -> String {
        guard let p = DayMath.parts(key) else { return key }
        return "\(p.day) \(short(months[p.month - 1]))"
    }

    /// `Mon 12 Oct 2026`, or "Pinned" for nil.
    public static func longDate(_ key: String?) -> String {
        guard let key, let p = DayMath.parts(key), let wd = DayMath.weekdayMondayFirst(key) else { return "Pinned" }
        return "\(short(weekdays[wd])) \(p.day) \(short(months[p.month - 1])) \(p.year)"
    }

    /// `Mon 12 Oct`.
    public static func mediumDate(_ key: String) -> String {
        guard let p = DayMath.parts(key), let wd = DayMath.weekdayMondayFirst(key) else { return key }
        return "\(short(weekdays[wd])) \(p.day) \(short(months[p.month - 1]))"
    }

    /// Sidebar group label: Today, Yesterday, Tomorrow, weekday name within 6 days back, else `ddd d MMM`.
    public static func group(_ key: String, today: String) -> String {
        guard let diff = DayMath.distance(from: key, to: today) else { return key }
        switch diff {
        case 0: return "Today"
        case 1: return "Yesterday"
        case -1: return "Tomorrow"
        case 2...6:
            if let wd = DayMath.weekdayMondayFirst(key) { return weekdays[wd] }
            return mediumDate(key)
        default: return mediumDate(key)
        }
    }

    /// `October 2026` for the picker header.
    public static func monthTitle(year: Int, month: Int) -> String { "\(months[month - 1]) \(year)" }
}

/// Typed input in the date picker (spec section 2).
public enum DatePhrase {
    static let weekdayNames = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    static let monthNames = DayLabel.months.map { $0.lowercased() }

    /// Returns a `YYYY-MM-DD` key for the phrase, relative to `today` (a day key), or nil.
    /// Accepts: today, tomorrow, yesterday, weekday names or 3+ letter prefixes (next occurrence, today counts),
    /// `15 oct`, `oct 15`, `15/10` (day/month), `2026-10-15`, `+3`, `-2`. A year may follow the day-month forms.
    public static func parse(_ input: String, today: String) -> String? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: ",", with: "")
        guard !s.isEmpty, let base = DayMath.parts(today) else { return nil }
        switch s {
        case "today": return today
        case "tomorrow": return DayMath.add(days: 1, to: today)
        case "yesterday": return DayMath.add(days: -1, to: today)
        default: break
        }
        if let m = match(#"^([+-])\s?(\d{1,4})$"#, s), let n = Int(m[2]) {
            return DayMath.add(days: m[1] == "-" ? -n : n, to: today)
        }
        if s.count >= 3, s.allSatisfy({ $0.isLetter }), let wd = weekdayNames.firstIndex(where: { $0.hasPrefix(s) }),
           let todayWD = DayMath.weekdayMondayFirst(today) {
            return DayMath.add(days: (wd - todayWD + 7) % 7, to: today)
        }
        if let m = match(#"^(\d{4})-(\d{1,2})-(\d{1,2})$"#, s) {
            return DayMath.key(year: Int(m[1])!, month: Int(m[2])!, day: Int(m[3])!)
        }
        if let m = match(#"^(\d{1,2})[/.](\d{1,2})(?:[/.](\d{2}|\d{4}))?$"#, s) {
            return DayMath.key(year: year(m[3], base.year), month: Int(m[2])!, day: Int(m[1])!)
        }
        if let m = match(#"^(\d{1,2})(?:st|nd|rd|th)? ([a-z]+)(?: (\d{4}))?$"#, s), let mon = month(m[2]) {
            return DayMath.key(year: year(m[3], base.year), month: mon, day: Int(m[1])!)
        }
        if let m = match(#"^([a-z]+) (\d{1,2})(?:st|nd|rd|th)?(?: (\d{4}))?$"#, s), let mon = month(m[1]) {
            return DayMath.key(year: year(m[3], base.year), month: mon, day: Int(m[2])!)
        }
        return nil
    }

    static func year(_ s: String, _ fallback: Int) -> Int {
        guard !s.isEmpty, let y = Int(s) else { return fallback }
        return s.count == 2 ? 2000 + y : y
    }

    static func month(_ s: String) -> Int? {
        guard s.count >= 3, let i = monthNames.firstIndex(where: { $0.hasPrefix(s) }) else { return nil }
        return i + 1
    }

    /// Capture groups of the first match; missing groups are "".
    static func match(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }
}

/// Month grid for the date picker: weeks of 7, Monday first, nil outside the month.
public enum MonthGrid {
    public static func weeks(year: Int, month: Int) -> [[String?]] {
        guard let first = DayMath.key(year: year, month: month, day: 1), let lead = DayMath.weekdayMondayFirst(first) else { return [] }
        var cells: [String?] = Array(repeating: nil, count: lead)
        for d in 1...DayMath.daysIn(year: year, month: month) { cells.append(DayMath.key(year: year, month: month, day: d)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// (year, month) shifted by `delta` months.
    public static func shift(year: Int, month: Int, by delta: Int) -> (year: Int, month: Int) {
        let total = year * 12 + (month - 1) + delta
        return (total / 12, total % 12 + 1)
    }
}
