// FractionCalcView.swift
//
// Fractions tab. A keypad calculator for tape measure math: add, subtract, multiply and divide
// fractions, mixed numbers and feet, and read the answer as a fraction rounded to the chosen
// precision, with the decimal and how far rounding moved it.
//
// How it's built: the whole expression is one string in @AppStorage ("calc_expression"), so it
// survives leaving the tab or closing the app. It is evaluated with MeasureParser from
// Core/Measure.swift, the same parser the length fields use, and shown with Format. The
// precision picker edits the app wide Keys.precision setting, so it also changes the other tabs.

import SwiftUI

/// A plain fraction calculator. It has no units: you know what you're measuring in, and the
/// in/mm setting on the other tabs never changes it. ' still multiplies by 12 so tape readings
/// like 7' 4 1/2 add up.
///
/// The expression is always parsed in MeasureParser's inch mode, where a bare number stays as
/// typed (the keypad has no letters, so unit words like mm can't be entered). That is also why
/// "calc_expression" is not a LengthField: the unit switch must never rewrite it.
struct FractionCalcView: View {
    // MARK: - State

    @AppStorage(Keys.precision) private var precision = 32
    @AppStorage("calc_expression") private var expression = ""
    /// True right after =, so the next digit starts a new calculation. It is @State, not stored,
    /// so after a relaunch a digit appends to the saved result instead.
    @State private var justEvaluated = false

    /// The expression's value, or nil while it is empty or incomplete (for example, ending in an
    /// operator).
    private var result: Double? { MeasureParser.value(expression) }

    /// Keypad layout, row by row. "−" is the Unicode minus sign, which MeasureParser normalizes
    /// to "-". "space" is drawn as ␣ and types the space between a whole number and its fraction.
    private let rows: [[String]] = [
        ["C", "(", ")", "⌫"],
        ["7", "8", "9", "÷"],
        ["4", "5", "6", "×"],
        ["1", "2", "3", "−"],
        ["0", ".", "/", "+"],
        ["'", "\"", "space", "="]
    ]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    display
                    PrecisionPicker(precision: $precision)
                    keypad
                }
                .padding()
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Fractions")
            .navigationBarTitleDisplayMode(.inline)
            // No in/mm toggle on this tab, since the calculator has no unit.
            .settingsButton(showsUnits: false)
        }
    }

    // MARK: - Display

    /// The expression (or a gray example when it's empty), then the result as a fraction, its
    /// decimal to 4 places, and a rounding note. Shows … while the expression can't be evaluated.
    private var display: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(expression.isEmpty ? "1 3/4 + 5/8" : expression)
                .font(.title3.monospacedDigit())
                .foregroundStyle(expression.isEmpty ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .trailing)

            if let v = result {
                Text(Format.fraction(v, denominator: precision))
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(Format.trimmed(v, places: 4))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let note = roundingNote(v) {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            } else if !expression.isEmpty {
                Text("…").font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .bottomTrailing)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    /// How far the fraction shown is from the exact result, when it isn't exact. Same 0.0005
    /// threshold as Format.roundingNote, but without the inch mark because the calculator has no unit.
    private func roundingNote(_ v: Double) -> String? {
        let err = Format.roundingError(v, denominator: precision)
        if abs(err) < 0.0005 { return nil }
        return (err > 0 ? "rounded up " : "rounded down ") + Format.decimal(abs(err), places: 3)
    }

    // MARK: - Keypad

    /// One bordered button per key in `rows`. Each key's label string is passed to tap(_:).
    private var keypad: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        Button {
                            tap(key)
                        } label: {
                            Text(key == "space" ? "␣" : key)
                                .font(.title2.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 54)
                        }
                        .buttonStyle(.bordered)
                        .tint(tint(for: key))
                        .accessibilityLabel(spoken(key))
                    }
                }
            }
        }
    }

    private func tint(for key: String) -> Color {
        switch key {
        case "=": return .accentColor
        case "÷", "×", "−", "+": return .orange
        case "C", "⌫": return .red
        default: return .gray
        }
    }

    /// VoiceOver labels for keys whose symbols don't read well aloud.
    private func spoken(_ key: String) -> String {
        switch key {
        case "'": return "feet"
        case "\"": return "inches"
        case "/": return "fraction bar"
        case "space": return "space"
        case "⌫": return "delete"
        case "C": return "clear"
        default: return key
        }
    }

    // MARK: - Key handling

    /// Applies one key press to the stored expression.
    private func tap(_ key: String) {
        switch key {
        case "C":
            expression = ""
        case "⌫":
            // Trailing spaces are trimmed before and after the deleted character, so one press
            // removes an operator along with its padding (" + " goes at once) and the user never
            // has to delete invisible spaces.
            while expression.hasSuffix(" ") { expression.removeLast() }
            expression = String(expression.dropLast())
            while expression.hasSuffix(" ") { expression.removeLast() }
        case "=":
            // Writes the result back as the new expression so the user can keep going from it.
            // Format.inchEntry gives an exact 1/64 fraction when the value is one (to within
            // 0.00003), otherwise a decimal to 6 places. Either way the expression keeps the
            // full value, not the fraction rounded to the precision setting, so chained
            // calculations don't pile up rounding error. Returns early so justEvaluated stays true.
            if let v = result {
                expression = Format.inchEntry(v)
                justEvaluated = true
            }
            return
        case "÷", "×", "−", "+":
            // Operators get a space on each side. MeasureParser reads a tight dash between
            // numbers as a mixed number ("4-1/2" is 4 1/2), so the spaces make "4 − 1/2"
            // subtract. Trailing spaces are trimmed first so a space key press doesn't double up.
            // On an empty expression only − does anything, and it goes in tight as a negative
            // sign. After =, an operator continues from the result.
            while expression.hasSuffix(" ") { expression.removeLast() }
            // A second operator replaces the first instead of stacking, since "1 + ×" can't
            // be worked out. This also clears a lone leading negative sign.
            if let last = expression.last, "+×÷−-".contains(last) {
                expression.removeLast()
                while expression.hasSuffix(" ") { expression.removeLast() }
            }
            if expression.isEmpty && key != "−" { break }
            expression += expression.isEmpty ? "-" : " \(key) "
        case "space":
            // Separates a whole number from its fraction, as in 1 3/4. Never leads or doubles up.
            if !expression.isEmpty && !expression.hasSuffix(" ") { expression += " " }
        default:
            // A digit, decimal point or ( right after = starts a new calculation. Other keys
            // (/, ', ", and ) ) append to the result.
            if justEvaluated, key.first?.isNumber == true || key == "." || key == "(" {
                expression = ""
            }
            expression += key
        }
        justEvaluated = false
    }
}
