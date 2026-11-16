// Measure.swift
// Shop Math
//
// Reads what people type into length fields and turns it into a number, and turns numbers
// back into shop style text such as 2 9/32". MeasureParser handles whole numbers, decimals,
// fractions, mixed numbers, feet and inches marks, metric suffixes, and arithmetic with
// parentheses. Format holds the shared text formatters for fractions, decimals, angles and money.
//
// UnitSystem in Units.swift calls MeasureParser for every length field and adds the metric
// formatters to Format. FractionCalcView calls MeasureParser directly, always in inches, and
// uses Format.fraction, Format.trimmed and Format.roundingError for its display. AnglesView
// and BoardFeetView use Format.degrees and Format.money.

import Foundation

// MARK: - Measurement expressions
//
// Every length field in the app accepts the same input:
//   1.75   1 3/4   1-3/4   3/4   7'   7' 4 1/2"   7'-4"   (3 + 1/2) × 2   19 mm   14 cm   2.4 m
// The result is in the parser's default unit (inches or millimeters). A bare number is in the
// default unit; a suffix (' " mm cm m in ft) converts that one quantity into the default unit.
// Bare numbers are never scaled because the same number has to work as a length ("139.7" in
// metric) and as a count or divisor ("× 2", "÷ 3"). If bare numbers were read as inches and
// converted, "× 2" would become "× 50.8" in metric.
//
// Rules:
//   • A space or a tight dash between a whole number and a fraction makes a mixed number:
//     "1 3/4" and "1-3/4" are both 1.75. Put spaces around a minus to subtract: "4 - 1/2".
//     So "5-3/4" is 5 3/4, not 4 1/4. Plans often write mixed numbers with a dash, so a tight
//     dash between a whole number and a fraction like 3/4 is read that way. Anything else
//     around a tight dash is subtraction: "5-3" is 2 and "1.5-3/4" is 0.75.
//   • ' means feet, " means inches. A feet value followed by a number adds inches: 3' 4" = 40.
//     3'-4" is also 40 (carpenter notation). The dash has to touch the feet mark; with a space
//     before it, "3' -4" or "3' - 4" is a subtraction. The number after a feet mark is inches
//     even in metric mode, so 7' 4 is 88 inches converted to mm.
//   • × or * multiplies (so do x and X), ÷ divides, / is a fraction bar that also divides.
//   • Multiplication is plain arithmetic, not dimensional. Each quantity is converted to the
//     default unit on its own and the numbers are multiplied, so 2' × 3' is 24 × 36 = 864, not
//     6 square feet. Every field wants a single length, so the parser doesn't track units through
//     an expression; multiply a length by a bare count instead.

/// Why a measurement expression couldn't be read. Most callers use MeasureParser.value, which
/// turns any of these into nil.
enum MeasureError: Error, Equatable {
    /// The text was empty or only whitespace.
    case empty
    /// A character that doesn't fit the grammar where it appears.
    case unexpected(Character)
    /// The text ended where a number or a closing parenthesis was needed.
    case unexpectedEnd
    /// Division by zero or a zero denominator.
    case divideByZero
    /// A result too large to be a real measurement (not finite).
    case tooLarge
    /// Two values with no operator between them, such as "2 3" or "2(3)".
    case missingOperator

    /// Short text shown under a field that can't be read, so the user knows what to fix.
    var message: String {
        switch self {
        case .empty: return "Enter a value"
        case .unexpected("."): return "Too many decimal points"
        case .unexpected(let c): return "\u{201C}\(c)\u{201D} isn't understood"
        case .unexpectedEnd: return "Unfinished entry"
        case .divideByZero: return "Can't divide by zero"
        case .tooLarge: return "Number is too large"
        case .missingOperator: return "Add + \u{2212} \u{00D7} \u{00F7} between numbers"
        }
    }
}

/// Recursive descent parser for one measurement expression. It walks an array of characters
/// with a cursor `i`. Create it only through `value` or `evaluate`, which normalize the text
/// first and check that nothing is left over at the end.
///
/// Precedence from loosest to tightest: + and - (parseExpression), × ÷ / (parseTerm), unary
/// signs and parentheses (parseFactor), a quantity with its unit suffix (parseLength), and a
/// number, fraction or mixed number (parseQuantity).
struct MeasureParser {
    /// The unit a bare number is read in, which is also the unit of the result.
    enum Unit {
        case inch
        case millimeter

        /// How many of this unit make one inch: 1 for inches, 25.4 for millimeters.
        var perInch: Double { self == .inch ? 1 : 25.4 }
    }

    /// The input after `normalize`, as characters so the cursor can index it.
    private let chars: [Character]
    /// Cursor: index of the next character to read.
    private var i = 0
    /// Default units per inch, from `Unit.perInch`. Every inch or foot quantity is multiplied by it.
    private let perInch: Double
    /// Default units per millimeter: 1/25.4 when parsing inches, 1 when parsing millimeters.
    private var perMM: Double { perInch / 25.4 }

    private init(_ text: String, unit: Unit) {
        chars = Array(text)
        perInch = unit.perInch
    }

    /// Returns the value in `unit`, or nil if the text is empty or not a valid expression.
    /// `evaluate` does the same work but throws a MeasureError that says why.
    static func value(_ text: String, unit: Unit = .inch) -> Double? {
        try? evaluate(text, unit: unit)
    }

    /// Parses all of `text` and returns its value in `unit`. Throws if the text is empty, has
    /// characters left over after a complete expression, divides by zero, or overflows.
    static func evaluate(_ text: String, unit: Unit = .inch) throws -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw MeasureError.empty }
        var p = MeasureParser(normalize(trimmed), unit: unit)
        let v = try p.parseExpression()
        p.skipSpaces()
        // The parser stops at the first thing it can't use. A number or "(" there follows a
        // complete value, so the user most likely left out an operator.
        if p.i < p.chars.count {
            let c = p.chars[p.i]
            // An entry that stops at an operator or fraction bar ("7 1/", "5 +") is unfinished,
            // even though the parser read a value before it.
            if let last = p.chars.last(where: { $0 != " " }), "/+-×÷(.".contains(last) {
                throw MeasureError.unexpectedEnd
            }
            // A point right after a complete number is a second decimal point ("1.2.3").
            if c == ".", p.i > 0, p.chars[p.i - 1].isNumber { throw MeasureError.unexpected(".") }
            if c.isNumber || c == "." || c == "(" { throw MeasureError.missingOperator }
            throw MeasureError.unexpected(c)
        }
        // Division by zero is caught where it happens. This catches overflow from very large
        // values.
        if !v.isFinite { throw MeasureError.tooLarge }
        return v
    }

    /// Maps typographic characters iOS keyboards insert to plain ones, so the grammar only has
    /// to know one form of each symbol. Also turns * and the letters x and X into ×.
    /// Commas go through `isThousandsComma`: a thousands separator is dropped (2,438 is 2438)
    /// and any other comma becomes a decimal point (2,5 is 2.5).
    private static func normalize(_ s: String) -> String {
        let chars = Array(cleanCharacters(s))
        var out = ""
        for (index, c) in chars.enumerated() {
            if c == "," {
                if !isThousandsComma(chars, at: index) { out.append(".") }
                continue
            }
            switch c {
            case "*", "x", "X": out.append("×")
            default: out.append(c)
            }
        }
        return out
    }

    /// Single-character fractions that arrive by paste or dictation (1½, ¾"), written out so
    /// the grammar reads them as ordinary fractions.
    private static let vulgarFractions: [Character: String] = [
        "\u{00BD}": "1/2", "\u{2153}": "1/3", "\u{2154}": "2/3", "\u{00BC}": "1/4", "\u{00BE}": "3/4",
        "\u{2155}": "1/5", "\u{2156}": "2/5", "\u{2157}": "3/5", "\u{2158}": "4/5",
        "\u{2159}": "1/6", "\u{215A}": "5/6", "\u{215B}": "1/8", "\u{215C}": "3/8",
        "\u{215D}": "5/8", "\u{215E}": "7/8"
    ]

    /// First pass of normalize: one form for each symbol the grammar uses.
    /// - smart quotes and primes become ' and ", and two apostrophes in a row become " (3/4'')
    /// - minus signs and every kind of dash or hyphen become -
    /// - fraction slashes become /, and ½ style fractions are written out ("1½" is "1 1/2")
    /// - full-width digits become ASCII digits
    /// - any whitespace (tab, newline, thin or no-break space) becomes a plain space
    static func cleanCharacters(_ s: String) -> String {
        var out: [Character] = []
        for c in s {
            switch c {
            case "\u{2019}", "\u{2018}", "\u{2032}", "`":
                out.append("'")
            case "\u{201C}", "\u{201D}", "\u{2033}":
                out.append("\"")
            case "\u{2212}", "\u{2013}", "\u{2014}", "\u{2010}", "\u{2011}", "\u{2012}":
                out.append("-")
            case "\u{2044}", "\u{2215}":
                out.append("/")
            default:
                if let written = vulgarFractions[c] {
                    // A digit right before it makes a mixed number: 1½ is 1 1/2.
                    if let last = out.last, last.isNumber { out.append(" ") }
                    out.append(contentsOf: written)
                } else if let scalar = c.unicodeScalars.first, c.unicodeScalars.count == 1,
                          (0xFF10...0xFF19).contains(scalar.value),
                          let ascii = Unicode.Scalar(scalar.value - 0xFF10 + 0x30) {
                    out.append(Character(ascii))
                } else if c.isWhitespace {
                    out.append(" ")
                } else {
                    out.append(c)
                }
            }
            // Two apostrophes typed for inches (3/4'') mean one inch mark.
            if out.count >= 2, out[out.count - 1] == "'", out[out.count - 2] == "'" {
                out.removeLast(2)
                out.append("\"")
            }
        }
        return String(out)
    }

    /// True when the comma at `index` separates thousands. The whole run of digits and commas
    /// around it has to be well formed: a first group of 1 to 3 digits that doesn't start with 0,
    /// then groups of exactly 3 (2,438 or 1,250,000), with no decimal point before the run.
    /// A run that isn't well formed is read with decimal commas instead: one comma is a European
    /// decimal (2,5 and 0,125), and two or more give a number with several points, which the
    /// parser rejects (1,25,000 is an error, never 1.25). A US entry like 1,250 reads as 1250.
    static func isThousandsComma(_ chars: [Character], at index: Int) -> Bool {
        guard index > 0, chars[index - 1].isNumber else { return false }
        var start = index
        while start > 0, chars[start - 1].isNumber || chars[start - 1] == "," { start -= 1 }
        var end = index
        while end + 1 < chars.count, chars[end + 1].isNumber || chars[end + 1] == "," { end += 1 }
        // A decimal point can't come before a thousands separator (1.250,5 is not supported).
        if start > 0, chars[start - 1] == "." { return false }
        let groups = String(chars[start...end]).split(separator: ",", omittingEmptySubsequences: false)
        guard let first = groups.first, (1...3).contains(first.count), first.first != "0" else { return false }
        return groups.dropFirst().allSatisfy { $0.count == 3 }
    }

    /// Reads a plain number entry with no units and no math (price, percent, degrees). Accepts an
    /// optional sign, digits, and one decimal point or decimal comma, plus thousands commas.
    /// A leading $ or USD and a trailing $, %, ° or deg are ignored.
    /// Returns nil for anything else, including the "inf", "nan" and "1e3" that Double(_:) would
    /// accept.
    static func plainNumber(_ text: String) -> Double? {
        // Symbols people type out of habit: $12.50, 20%, 15°, 15 deg. They're dropped, not read.
        var trimmed = cleanCharacters(text).trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["usd", "$"] where trimmed.lowercased().hasPrefix(prefix) {
            trimmed = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        for suffix in ["percent", "degrees", "degree", "deg", "%", "\u{00B0}", "$"] where trimmed.lowercased().hasSuffix(suffix) {
            trimmed = String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        let chars = Array(trimmed)
        var clean = ""
        for (index, c) in chars.enumerated() {
            if c == "," {
                if !isThousandsComma(chars, at: index) { clean.append(".") }
            } else {
                clean.append(c)
            }
        }
        var body = Substring(clean)
        if body.first == "-" || body.first == "+" { body = body.dropFirst() }
        guard body.contains(where: { $0.isNumber }),
              body.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              body.filter({ $0 == "." }).count <= 1 else { return nil }
        return Double(clean)
    }

    // expression := term (('+' | '-') term)*
    // Left to right, so 10 - 2 - 1 is 7. A "-" reaching this loop is always subtraction. The
    // dash in a mixed number (1-3/4) or in carpenter notation (3'-4") is consumed further down.
    private mutating func parseExpression() throws -> Double {
        var value = try parseTerm()
        while true {
            skipSpaces()
            guard let c = peek() else { return value }
            if c == "+" {
                i += 1
                value += try parseTerm()
            } else if c == "-" {
                i += 1
                value -= try parseTerm()
            } else {
                return value
            }
        }
    }

    // term := factor (('×' | '÷' | '/') factor)*
    // A slash that reaches here is division, as in "3 / 4" or "6 1/2 / 2". A tight slash
    // between digits ("3/4") was already read as a fraction by parseQuantity.
    private mutating func parseTerm() throws -> Double {
        var value = try parseFactor()
        while true {
            skipSpaces()
            guard let c = peek() else { return value }
            if c == "×" {
                i += 1
                value *= try parseFactor()
            } else if c == "÷" || c == "/" {
                i += 1
                let d = try parseFactor()
                if d == 0 { throw MeasureError.divideByZero }
                value /= d
            } else {
                return value
            }
        }
    }

    // factor := '-' factor | '+' factor | '(' expression ')' [unit] | length
    // A leading sign applies to the whole length after it, so -1 3/4 is -1.75 and -7' 4" is -88.
    private mutating func parseFactor() throws -> Double {
        skipSpaces()
        guard let c = peek() else { throw MeasureError.unexpectedEnd }
        if c == "-" { i += 1; return -(try parseFactor()) }
        if c == "+" { i += 1; return try parseFactor() }
        if c == "(" {
            i += 1
            let v = try parseExpression()
            skipSpaces()
            guard peek() == ")" else {
                if let ch = peek() { throw MeasureError.unexpected(ch) }
                throw MeasureError.unexpectedEnd
            }
            i += 1
            // Allow a unit after a group: (2 + 1)' = 36". Unlike 3' 4", no inches can follow
            // the feet mark here. With no unit, the group is a bare number in the default unit.
            let save = i
            skipSpaces()
            if peek() == "'" { i += 1; return v * 12 * perInch }
            if peek() == "\"" { i += 1; return v * perInch }
            if let word = parseUnitWord() { return v * word.factor(perInch: perInch) }
            i = save
            return v
        }
        if c.isNumber || c == "." { return try parseLength() }
        throw MeasureError.unexpected(c)
    }

    // length := quantity [ "'" [ ['-'] quantity ['"'] ] ] | quantity '"' | quantity unitword
    // A suffix converts this one quantity into the default unit. Spaces are allowed before
    // the suffix ("19 mm", "3 '"). With no suffix the number is returned unscaled (see the
    // overview at the top of the file).
    private mutating func parseLength() throws -> Double {
        let q = try parseQuantity()
        let save = i
        skipSpaces()
        if peek() == "\"" { i += 1; return q * perInch }
        if let word = parseUnitWord() {
            // "7 ft 4 in" works like 7' 4": feet can be followed by inches.
            if case .foot = word { return try inchesAfterFeet(q) }
            return q * word.factor(perInch: perInch)
        }
        if peek() == "'" {
            i += 1
            return try inchesAfterFeet(q)
        }
        i = save
        return q
    }

    /// Called just past a feet mark or word, with the number of feet. Reads optional inches after
    /// it and returns the total in the default unit.
    private mutating func inchesAfterFeet(_ feet: Double) throws -> Double {
        var total = feet * 12
        let afterFeet = i
        // Carpenter notation 3'-4": a dash right after the feet mark, then a digit. With a
        // space before the dash this branch is skipped and the dash is left for subtraction.
        if peek() == "-", let n = peek(1), n.isNumber || n == "." {
            i += 1
            total += try parseQuantity()
            skipInchMark()
            return total * perInch
        }
        // 3' 4" or 3' 4 1/2 or 7 ft 4 in: a number after the feet is inches, with or without
        // an inch mark or word.
        skipSpaces()
        if let n = peek(), n.isNumber || n == "." {
            total += try parseQuantity()
            skipInchMark()
            return total * perInch
        }
        // Feet alone. Give back any spaces skipped while looking for inches.
        i = afterFeet
        return total * perInch
    }

    /// After the inches part of a feet and inches entry, consumes a " or an inch word if one is
    /// there. Anything else is left for the caller.
    private mutating func skipInchMark() {
        let save = i
        skipSpaces()
        if peek() == "\"" { i += 1; return }
        if let word = parseUnitWord(), case .inch = word { return }
        i = save
    }

    // quantity := number | number '/' number | int (' '+ | '-') int '/' int
    // A fraction or mixed number is one quantity, so a suffix applies to all of it:
    // 1 3/4" or 5 1/2 mm.
    private mutating func parseQuantity() throws -> Double {
        let (whole, wholeIsInt) = try parseNumber()

        // Tight fraction: 3/4. The slash must touch both numbers; "3 / 4" is left to parseTerm.
        if peek() == "/" , let n = peek(1), n.isNumber {
            i += 1
            let (den, _) = try parseNumber()
            if den == 0 { throw MeasureError.divideByZero }
            return whole / den
        }

        // Mixed number: "1 3/4" or "1-3/4". Only a whole number, then one dash or one or more
        // spaces, then int/int. If what follows doesn't match, rewind to just after the whole
        // number and leave the dash or spaces for the caller, where a dash means subtraction.
        if wholeIsInt {
            let save = i
            var sawSeparator = false
            if peek() == "-" {
                i += 1
                sawSeparator = true
            } else {
                while peek() == " " { i += 1; sawSeparator = true }
            }
            if sawSeparator, let n = peek(), n.isNumber {
                let start = i
                if let (num, numIsInt) = try? parseNumber(), numIsInt, peek() == "/",
                   let d = peek(1), d.isNumber {
                    i += 1
                    let (den, _) = try parseNumber()
                    if den == 0 { throw MeasureError.divideByZero }
                    return whole + num / den
                }
                i = start
            }
            i = save
        }
        return whole
    }

    /// Reads digits with at most one decimal point; a second point ends the number. Returns
    /// the value and whether it had no decimal point, which decides whether it can be part
    /// of a mixed number.
    private mutating func parseNumber() throws -> (Double, Bool) {
        let start = i
        var sawDot = false
        while let c = peek(), c.isNumber || (c == "." && !sawDot) {
            if c == "." { sawDot = true }
            i += 1
        }
        let text = String(chars[start..<i])
        guard !text.isEmpty, text != ".", let v = Double(text) else {
            if let c = peek() { throw MeasureError.unexpected(c) }
            throw MeasureError.unexpectedEnd
        }
        return (v, !sawDot)
    }

    /// A unit written as a word after a number.
    private enum UnitWord {
        case inch
        case foot
        /// Millimeters per unit: 1 for mm, 10 for cm, 1000 for m.
        case metric(Double)

        /// How many default units one of this unit is.
        func factor(perInch: Double) -> Double {
            switch self {
            case .inch: return perInch
            case .foot: return 12 * perInch
            case .metric(let mm): return mm * perInch / 25.4
            }
        }
    }

    /// Reads a unit word at the cursor, in any letter case and with an optional period
    /// ("in." or "ft."): mm, cm, m, in, ft, or spelled out (inch, inches, foot, feet,
    /// millimeter(s), millimetre(s), centimeter(s), centimetre(s), meter(s), metre(s)), which is
    /// how dictation writes them. Leaves the cursor alone and returns nil for any other letters.
    private mutating func parseUnitWord() -> UnitWord? {
        let start = i
        var word = ""
        while let c = peek(), c.isLetter {
            word.append(Character(c.lowercased()))
            i += 1
        }
        let unit: UnitWord
        switch word {
        case "mm", "millimeter", "millimeters", "millimetre", "millimetres": unit = .metric(1)
        case "cm", "centimeter", "centimeters", "centimetre", "centimetres": unit = .metric(10)
        case "m", "meter", "meters", "metre", "metres": unit = .metric(1000)
        case "in", "inch", "inches": unit = .inch
        case "ft", "foot", "feet": unit = .foot
        default:
            i = start
            return nil
        }
        // An abbreviation's period ("3/4 in.") is skipped, but not a decimal point ("2 in.5").
        if peek() == ".", !(peek(1)?.isNumber ?? false) { i += 1 }
        return unit
    }

    /// The character `offset` places past the cursor, or nil past the end.
    private func peek(_ offset: Int = 0) -> Character? {
        let j = i + offset
        return j < chars.count ? chars[j] : nil
    }

    private mutating func skipSpaces() {
        while let c = peek(), c == " " { i += 1 }
    }
}

// MARK: - Formatting

/// Text formatters shared across the app. Lengths are in inches. The metric formatters are in
/// an extension in Units.swift.
enum Format {
    /// Rounds inches to the nearest 1/`denominator` and returns a reduced fraction with no inch
    /// mark: 2.2866 at 32 gives "2 9/32", 0.5 gives "1/2", 3 gives "3". Halves round away from
    /// zero. Negative values get a leading minus, and a value that rounds to zero is "0", never
    /// "-0". `denominator` must be positive; the app passes 8, 16, 32 or 64. Values that aren't
    /// finite or are too large for Int arithmetic fall back to a decimal with 3 places.
    static func fraction(_ inches: Double, denominator: Int) -> String {
        guard inches.isFinite, abs(inches) * Double(denominator) < 1e15 else { return decimal(inches, places: 3) }
        let negative = inches < 0
        let units = Int((abs(inches) * Double(denominator)).rounded())
        let whole = units / denominator
        var num = units % denominator
        var den = denominator
        if num == 0 {
            return (negative && whole != 0 ? "-" : "") + "\(whole)"
        }
        let g = gcd(num, den)
        num /= g
        den /= g
        if whole == 0 {
            return (negative ? "-" : "") + "\(num)/\(den)"
        }
        return (negative ? "-" : "") + "\(whole) \(num)/\(den)"
    }

    /// Inches with the inch mark: 2 9/32"
    static func inches(_ inches: Double, denominator: Int) -> String {
        fraction(inches, denominator: denominator) + "\""
    }

    /// Signed difference between the rounded fraction and the true value, in inches. Positive
    /// means the fraction shown is longer than the true value. Returns 0 for values where
    /// `fraction` falls back to a decimal.
    static func roundingError(_ inches: Double, denominator: Int) -> Double {
        guard inches.isFinite, abs(inches) * Double(denominator) < 1e15 else { return 0 }
        let rounded = (inches * Double(denominator)).rounded() / Double(denominator)
        return rounded - inches
    }

    /// A note such as `rounded up 0.003"` saying how far the fraction shown is from the true
    /// value, or nil when the difference is under 0.0005", where it would print as 0.000.
    /// Used by UnitSystem.detail. FractionCalcView has its own copy without the inch mark.
    static func roundingNote(_ inches: Double, denominator: Int) -> String? {
        let err = roundingError(inches, denominator: denominator)
        if abs(err) < 0.0005 { return nil }
        let thou = String(format: "%.3f", abs(err))
        return err > 0 ? "rounded up \(thou)\"" : "rounded down \(thou)\""
    }

    /// Feet and inches with the inches rounded to 1/`denominator`: 62.25 gives 5' 2 1/4", and
    /// anything under a foot gives inches only. The total is rounded before splitting, so
    /// 11.999 at 32 gives 1' 0" rather than 12". No screen calls this at the moment.
    static func feetInches(_ inches: Double, denominator: Int) -> String {
        guard inches.isFinite, abs(inches) * Double(denominator) < 1e15 else { return decimal(inches, places: 3) + "\"" }
        let negative = inches < 0
        let units = Int((abs(inches) * Double(denominator)).rounded())
        let perFoot = 12 * denominator
        let feet = units / perFoot
        let remUnits = units % perFoot
        let rem = Double(remUnits) / Double(denominator)
        let sign = negative ? "-" : ""
        if feet == 0 { return sign + fraction(rem, denominator: denominator) + "\"" }
        return sign + "\(feet)' " + fraction(rem, denominator: denominator) + "\""
    }

    /// Fixed number of decimal places, trailing zeros kept: 1.500. See `trimmed` to drop them.
    static func decimal(_ x: Double, places: Int = 3) -> String {
        let s = String(format: "%.\(places)f", x)
        // -0 and tiny negatives print as "-0.0000". Drop the sign when nothing but zeros follow.
        if s.hasPrefix("-"), s.dropFirst().allSatisfy({ $0 == "0" || $0 == "." }) { return String(s.dropFirst()) }
        return s
    }

    /// Degrees to one decimal place with the degree sign: 22.5°.
    static func degrees(_ x: Double) -> String {
        String(format: "%.1f°", x)
    }

    /// Dollars and cents: $12.50.
    static func money(_ x: Double) -> String {
        String(format: "$%.2f", x)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = a, b = b
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }
}
