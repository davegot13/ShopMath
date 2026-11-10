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
    /// Division by zero, a zero denominator, or a result that isn't finite (overflow).
    case divideByZero
    /// Two values with no operator between them, such as "2 3" or "2(3)".
    case missingOperator
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
            if c.isNumber || c == "." || c == "(" { throw MeasureError.missingOperator }
            throw MeasureError.unexpected(c)
        }
        // Division by zero is caught where it happens. This catches overflow from very large
        // values, which is reported under the same case.
        if !v.isFinite { throw MeasureError.divideByZero }
        return v
    }

    /// Maps typographic characters iOS keyboards insert to plain ones, so the grammar only has
    /// to know one form of each symbol. Also turns * and the letters x and X into ×, and a
    /// no-break space into a space. Commas go through `isThousandsComma`: a thousands separator
    /// is dropped (2,438 is 2438) and any other comma becomes a decimal point (2,5 is 2.5).
    private static func normalize(_ s: String) -> String {
        let chars = Array(s)
        var out = ""
        for (index, c) in chars.enumerated() {
            if c == "," {
                if !isThousandsComma(chars, at: index) { out.append(".") }
                continue
            }
            switch c {
            case "\u{2019}", "\u{2018}", "\u{2032}", "`": out.append("'")       // smart quote, prime
            case "\u{201C}", "\u{201D}", "\u{2033}": out.append("\"")           // smart double quote, double prime
            case "\u{2212}", "\u{2013}", "\u{2014}": out.append("-")            // minus sign, en and em dash
            case "*", "x", "X": out.append("×")
            case "\u{00A0}": out.append(" ")
            default: out.append(c)
            }
        }
        return out
    }

    /// True when the comma at `index` separates thousands, as in 2,438 or 1,250,000: it follows
    /// a digit, exactly three digits come after it, and the number it sits in doesn't start with
    /// 0. Anything else is a decimal comma, so 2,5 and 0,125 keep their European meaning. A US
    /// entry like 1,250 therefore reads as 1250, never 1.25.
    static func isThousandsComma(_ chars: [Character], at index: Int) -> Bool {
        guard index > 0, chars[index - 1].isNumber else { return false }
        var digitsAfter = 0
        var j = index + 1
        while j < chars.count, chars[j].isNumber { digitsAfter += 1; j += 1 }
        guard digitsAfter == 3 else { return false }
        // A decimal point can't come before a thousands separator (1.250,5 is not supported).
        var k = index - 1
        while k >= 0, chars[k].isNumber || chars[k] == "," { k -= 1 }
        if k >= 0, chars[k] == "." { return false }
        // The number's first digit: a leading 0 means a decimal comma (0,125).
        return chars[k + 1] != "0"
    }

    /// Reads a plain number entry with no units and no math (price, percent, degrees). Accepts an
    /// optional sign, digits, and one decimal point or decimal comma, plus thousands commas.
    /// Returns nil for anything else, including the "inf", "nan" and "1e3" that Double(_:) would
    /// accept.
    static func plainNumber(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
            if let f = parseUnitWord() { return v * f }
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
        if let f = parseUnitWord() { return q * f }
        if peek() == "'" {
            i += 1
            var total = q * 12
            let afterFeet = i
            // Carpenter notation 3'-4": a dash right after the feet mark, then a digit. With a
            // space before the dash this branch is skipped and the dash is left for subtraction.
            if peek() == "-", let n = peek(1), n.isNumber || n == "." {
                i += 1
                total += try parseQuantity()
                skipSpaces()
                if peek() == "\"" { i += 1 }
                return total * perInch
            }
            // 3' 4" or 3' 4 1/2: a number after the feet mark is inches, with or without the ".
            skipSpaces()
            if let n = peek(), n.isNumber || n == "." {
                total += try parseQuantity()
                skipSpaces()
                if peek() == "\"" { i += 1 }
                return total * perInch
            }
            // Feet alone. Give back any spaces skipped while looking for inches.
            i = afterFeet
            return total * perInch
        }
        i = save
        return q
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

    /// Reads mm, cm, m, in or ft at the cursor (any letter case) and returns the factor into
    /// the default unit. Leaves the cursor alone and returns nil if the letters there are not
    /// one of those words. Unlike the ' mark, "ft" takes no inches after it, so "7 ft 4" is an error.
    private mutating func parseUnitWord() -> Double? {
        let start = i
        var word = ""
        while let c = peek(), c.isLetter {
            word.append(Character(c.lowercased()))
            i += 1
        }
        switch word {
        case "mm": return perMM
        case "cm": return 10 * perMM
        case "m": return 1000 * perMM
        case "in": return perInch
        case "ft": return 12 * perInch
        default:
            i = start
            return nil
        }
    }

    /// The character `offset` places past the cursor, or nil past the end.
    private func peek(_ offset: Int = 0) -> Character? {
        let j = i + offset
        return j < chars.count ? chars[j] : nil
    }

    private mutating func skipSpaces() {
        while let c = peek(), c == " " || c == "\t" { i += 1 }
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
        String(format: "%.\(places)f", x)
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
