import Foundation

/// Table formulas, spec section 4. Same semantics as linux/src/formula.ts.
public enum FormulaError: String, Error, Equatable, Sendable {
    case ref = "#REF!"
    case div0 = "#DIV/0!"
    case cycle = "#CYCLE!"
    case err = "#ERR!"
}

public enum CellValue: Equatable, Sendable {
    case empty
    case number(Double)
    case text(String)
    case error(FormulaError)

    /// What the cell shows when not being edited.
    public var display: String {
        switch self {
        case .empty: return ""
        case .number(let n): return Formula.format(n)
        case .text(let s): return s
        case .error(let e): return e.rawValue
        }
    }

    public var number: Double? { if case .number(let n) = self { return n } else { return nil } }
}

public enum Formula {
    public static func isFormula(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespaces).hasPrefix("=")
    }

    /// Column letters: 0 -> A, 25 -> Z, 26 -> AA.
    public static func columnName(_ index: Int) -> String {
        var s = "", n = index + 1
        while n > 0 {
            let r = (n - 1) % 26
            s = String(UnicodeScalar(UInt8(65 + r))) + s
            n = (n - 1) / 26
        }
        return s
    }

    /// Inverse of `columnName`, case-insensitive. nil for anything but letters.
    public static func columnIndex(_ name: String) -> Int? {
        var n = 0
        for ch in name.uppercased().unicodeScalars {
            guard ch.value >= 65, ch.value <= 90 else { return nil }
            n = n * 26 + Int(ch.value - 64)
        }
        return n == 0 ? nil : n - 1
    }

    /// `B3` for row 2, column 1 (both zero-based).
    public static func address(row: Int, col: Int) -> String { "\(columnName(col))\(row + 1)" }

    /// Numbers in cells: whitespace trimmed, `,` thousands separators removed, `£ $ € %` prefix/suffix ignored.
    public static func parseNumber(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let marks: Set<Character> = ["£", "$", "€", "%"]
        var neg = false
        if s.hasPrefix("-") || s.hasPrefix("+") { neg = s.hasPrefix("-"); s.removeFirst() }
        while let f = s.first, marks.contains(f) { s.removeFirst() }
        while let l = s.last, marks.contains(l) { s.removeLast() }
        s = s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        if !neg, s.hasPrefix("-") || s.hasPrefix("+") { neg = s.hasPrefix("-"); s.removeFirst() }
        guard !s.isEmpty, s.range(of: #"^(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$"#, options: .regularExpression) != nil,
              let v = Double(s), v.isFinite else { return nil }
        return neg ? -v : v
    }

    /// Up to 4 decimals, trailing zeros trimmed, thousands separators for |x| >= 1000.
    public static func format(_ value: Double) -> String {
        guard value.isFinite else { return FormulaError.err.rawValue }
        let magnitude = abs(value)
        var intString: String, frac = ""
        if magnitude < 1e14 {
            let units = Int64((magnitude * 10_000).rounded())
            intString = String(units / 10_000)
            let f = String(units % 10_000)
            frac = String(repeating: "0", count: 4 - f.count) + f
            while frac.hasSuffix("0") { frac.removeLast() }
        } else {
            intString = String(format: "%.0f", magnitude)
        }
        if intString.count >= 4 { intString = grouped(intString) }
        let body = frac.isEmpty ? intString : "\(intString).\(frac)"
        return value < 0 && body != "0" ? "-\(body)" : body
    }

    static func grouped(_ digits: String) -> String {
        var out = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return String(out.reversed())
    }
}

/// Evaluates every cell of a table. Row 1 is the first row (the header), column A the first column.
public final class TableEvaluator {
    public let rows: [[String]]
    public let columnCount: Int
    private var memo: [Int: CellValue] = [:]
    private var visiting: Set<Int> = []

    public init(rows: [[String]]) {
        self.rows = rows
        self.columnCount = rows.map(\.count).max() ?? 0
    }

    public func raw(_ r: Int, _ c: Int) -> String {
        guard r >= 0, r < rows.count, c >= 0, c < rows[r].count else { return "" }
        return rows[r][c]
    }

    public func value(row r: Int, col c: Int) -> CellValue {
        (try? cell(r, c)) ?? .error(.ref)
    }

    public func display(row r: Int, col c: Int) -> String { value(row: r, col: c).display }

    /// Every cell, same shape as `rows`.
    public func evaluateAll() -> [[CellValue]] {
        rows.indices.map { r in rows[r].indices.map { c in value(row: r, col: c) } }
    }

    // MARK: Cells

    private func key(_ r: Int, _ c: Int) -> Int { r * 100_000 + c }

    fileprivate func cell(_ r: Int, _ c: Int) throws -> CellValue {
        guard r >= 0, c >= 0, r < rows.count, c < columnCount else { throw FormulaError.ref }
        let k = key(r, c)
        if let v = memo[k] { return v }
        if visiting.contains(k) { throw FormulaError.cycle }
        let raw = self.raw(r, c)
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let v: CellValue
        if trimmed.hasPrefix("=") {
            visiting.insert(k)
            do {
                var parser = try Parser(source: String(trimmed.dropFirst()), table: self)
                v = .number(try parser.run())
            } catch let e as FormulaError {
                v = .error(e)
            } catch {
                v = .error(.err)
            }
            visiting.remove(k)
        } else if trimmed.isEmpty {
            v = .empty
        } else if let n = Formula.parseNumber(raw) {
            v = .number(n)
        } else {
            v = .text(raw)
        }
        memo[k] = v
        return v
    }
}

private enum Token: Equatable {
    case number(Double)
    case ref(row: Int, col: Int)
    case ident(String)
    case op(Character)
}

private struct Parser {
    let tokens: [Token]
    let table: TableEvaluator
    var p = 0

    static let functions: Set<String> = ["SUM", "AVG", "AVERAGE", "MIN", "MAX", "COUNT"]

    init(source: String, table: TableEvaluator) throws {
        self.tokens = try Parser.tokenize(source)
        self.table = table
    }

    static func tokenize(_ src: String) throws -> [Token] {
        var out: [Token] = []
        let chars = Array(src)
        var i = 0
        func isDigit(_ c: Character) -> Bool { c >= "0" && c <= "9" }
        func isLetter(_ c: Character) -> Bool { (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") }
        while i < chars.count {
            let ch = chars[i]
            if ch.isWhitespace { i += 1; continue }
            if isDigit(ch) || ch == "." {
                var j = i, seenDot = false
                while j < chars.count, isDigit(chars[j]) || (chars[j] == "." && !seenDot) {
                    if chars[j] == "." { seenDot = true }
                    j += 1
                }
                if j < chars.count, chars[j] == "e" || chars[j] == "E" {
                    var k = j + 1
                    if k < chars.count, chars[k] == "+" || chars[k] == "-" { k += 1 }
                    if k < chars.count, isDigit(chars[k]) {
                        while k < chars.count, isDigit(chars[k]) { k += 1 }
                        j = k
                    }
                }
                guard let v = Double(String(chars[i..<j])) else { throw FormulaError.err }
                out.append(.number(v)); i = j; continue
            }
            if isLetter(ch) {
                var j = i
                while j < chars.count, isLetter(chars[j]) { j += 1 }
                let letters = String(chars[i..<j])
                var k = j
                while k < chars.count, isDigit(chars[k]) { k += 1 }
                if k > j {
                    guard letters.count <= 3, let col = Formula.columnIndex(letters), let row = Int(String(chars[j..<k])) else { throw FormulaError.err }
                    out.append(.ref(row: row - 1, col: col))
                } else {
                    out.append(.ident(letters.uppercased()))
                }
                i = k; continue
            }
            if "+-*/(),:".contains(ch) { out.append(.op(ch)); i += 1; continue }
            throw FormulaError.err
        }
        return out
    }

    mutating func run() throws -> Double {
        let v = try expr()
        guard p == tokens.count else { throw FormulaError.err }
        guard v.isFinite else { throw FormulaError.err }
        return v
    }

    var peek: Token? { p < tokens.count ? tokens[p] : nil }

    mutating func eat(_ c: Character) -> Bool {
        if case .op(c)? = peek { p += 1; return true }
        return false
    }

    mutating func expr() throws -> Double {
        var v = try term()
        while true {
            if eat("+") { v += try term() } else if eat("-") { v -= try term() } else { return v }
        }
    }

    mutating func term() throws -> Double {
        var v = try unary()
        while true {
            if eat("*") { v *= try unary() } else if eat("/") {
                let d = try unary()
                if d == 0 { throw FormulaError.div0 }
                v /= d
            } else { return v }
        }
    }

    mutating func unary() throws -> Double {
        if eat("-") { return -(try unary()) }
        if eat("+") { return try unary() }
        return try primary()
    }

    mutating func primary() throws -> Double {
        guard let t = peek else { throw FormulaError.err }
        switch t {
        case .number(let v): p += 1; return v
        case .ref(let r, let c):
            p += 1
            if case .op(":")? = peek { throw FormulaError.err } // ranges only inside functions
            return try Parser.arithmetic(table.cell(r, c))
        case .op("("):
            p += 1
            let v = try expr()
            guard eat(")") else { throw FormulaError.err }
            return v
        case .ident(let name):
            guard Parser.functions.contains(name) else { throw FormulaError.err }
            p += 1
            return try call(name)
        default:
            throw FormulaError.err
        }
    }

    /// Empty and text cells are 0 in arithmetic; errors propagate.
    static func arithmetic(_ v: CellValue) throws -> Double {
        switch v {
        case .number(let n): return n
        case .error(let e): throw e
        case .empty, .text: return 0
        }
    }

    mutating func call(_ name: String) throws -> Double {
        guard eat("(") else { throw FormulaError.err }
        var values: [CellValue] = []
        if !eat(")") {
            repeat { values += try argument() } while eat(",")
            guard eat(")") else { throw FormulaError.err }
        }
        for v in values { if case .error(let e) = v { throw e } }
        let nums = values.compactMap(\.number)
        switch name {
        case "SUM": return nums.reduce(0, +)
        case "AVG", "AVERAGE":
            guard !nums.isEmpty else { throw FormulaError.div0 }
            return nums.reduce(0, +) / Double(nums.count)
        case "MIN": return nums.min() ?? 0
        case "MAX": return nums.max() ?? 0
        case "COUNT": return Double(nums.count)
        default: throw FormulaError.err
        }
    }

    /// A range or a lone ref yields cell values (empties and text are skipped later); anything else is an expression.
    mutating func argument() throws -> [CellValue] {
        if case .ref(let r1, let c1)? = peek {
            let next: Token? = p + 1 < tokens.count ? tokens[p + 1] : nil
            if next == .op(":") {
                guard p + 2 < tokens.count, case .ref(let r2, let c2) = tokens[p + 2] else { throw FormulaError.err }
                p += 3
                var out: [CellValue] = []
                for r in min(r1, r2)...max(r1, r2) {
                    for c in min(c1, c2)...max(c1, c2) { out.append(try table.cell(r, c)) }
                }
                return out
            }
            if next == nil || next == .op(",") || next == .op(")") {
                p += 1
                return [try table.cell(r1, c1)]
            }
        }
        return [.number(try expr())]
    }
}

/// Column widths for table blocks (spec section 4).
public enum TableLayout {
    public static let minColumn = 40
    public static let maxFit = 480

    /// Stored widths when present (padded or trimmed to the column count), else the block width split evenly.
    public static func widths(for block: Block) -> [Int] {
        let cols = max(1, block.rows?.map(\.count).max() ?? 1)
        if let stored = block.colWidths, !stored.isEmpty {
            let fallback = stored.last ?? 120
            return (0..<cols).map { $0 < stored.count ? max(minColumn, stored[$0]) : max(minColumn, fallback) }
        }
        let each = max(minColumn, block.w / cols)
        return Array(repeating: each, count: cols)
    }

    /// Double-click fit: about 7.5 px per character + 20, clamped 40 to 480. Uses displayed values.
    public static func fitWidth(column c: Int, rows: [[String]]) -> Int {
        let eval = TableEvaluator(rows: rows)
        let longest = rows.indices.map { r -> Int in
            guard c < rows[r].count else { return 0 }
            let raw = rows[r][c]
            return Formula.isFormula(raw) ? eval.display(row: r, col: c).count : raw.count
        }.max() ?? 0
        let w = Int((7.5 * Double(longest) + 20).rounded())
        return min(maxFit, max(minColumn, w))
    }
}
