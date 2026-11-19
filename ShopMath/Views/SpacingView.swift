// SpacingView.swift
//
// Even Spacing planner. Spaces a number of identical pieces (slats, balusters, pickets, shelf pin
// holes) evenly along a length and lists where to mark each one.
//
// How it's built: the length and piece width are LengthField entries parsed through the current
// UnitSystem. The count is a whole number and the layout an enum, both under plain keys.
// EvenSpacing in Core/Planners.swift does the math.

import SwiftUI

/// The Even Spacing planner.
struct SpacingView: View {
    @AppStorage(Keys.precision) private var precision = 32
    @AppStorage(Keys.units) private var unit: UnitSystem = .imperial
    @AppStorage(LengthField.spLength.key) private var lengthText = LengthField.spLength.imperialDefault
    @AppStorage(LengthField.spWidth.key) private var widthText = LengthField.spWidth.imperialDefault
    @AppStorage("sp_count") private var countText = "5"
    @AppStorage("sp_layout") private var layout: SpacingLayout = .gapsAtEnds

    /// Reads a count: digits only (5 or 5.0), no symbols. Nil for anything else.
    nonisolated static func readCount(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              let v = Double(t), v.isFinite, v == v.rounded() else { return nil }
        return v
    }

    /// The count as a whole number from 1 to EvenSpacing.maxCount, or nil.
    private var count: Int? {
        guard let v = Self.readCount(countText), v >= 1, v <= Double(EvenSpacing.maxCount) else { return nil }
        return Int(v)
    }

    private var length: Double? { unit.inches(lengthText) }
    private var width: Double? { unit.inches(widthText) }

    private var spacing: EvenSpacing? {
        guard let l = length, let w = width, let n = count else { return nil }
        return EvenSpacing.make(length: l, count: n, pieceWidth: w, layout: layout)
    }

    private func fmt(_ v: Double) -> String { unit.length(v, precision: precision) }

    var body: some View {
        Form {
            Section {
                MeasureField(label: "Total length", text: $lengthText, caption: "The space between the two ends")
                NumberField(label: "Number of pieces", text: $countText,
                            caption: "Up to \(EvenSpacing.maxCount)",
                            reader: Self.readCount, invalidMessage: "Enter a whole number, like 5")
                MeasureField(label: "Piece width", text: $widthText, caption: "Use 0 to space holes or marks")
            } header: {
                Text("Space and pieces")
            }

            Section {
                Picker("Layout", selection: $layout) {
                    ForEach(SpacingLayout.allCases) { Text($0.label).tag($0) }
                }
                .adaptivePickerStyle()
            } footer: {
                Text(layout == .gapsAtEnds
                     ? "The same gap between every piece and at both ends, like balusters between posts."
                     : "The first and last pieces sit tight against the ends, like hooks spread across a rail.")
            }

            if let s = spacing {
                results(s)
            } else if let problem {
                Section { Callout(kind: .warning, text: problem) }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Even Spacing")
        .settingsButton()
    }

    /// Why there is no result, when the entries are readable but don't work together. Nil while an
    /// entry is blank or unreadable; the field itself says what's wrong.
    private var problem: String? {
        if count == nil {
            return Self.readCount(countText) == nil ? nil : "Enter a whole number of pieces from 1 to \(EvenSpacing.maxCount)."
        }
        guard let l = length, let w = width else { return nil }
        let n = count ?? 0
        if l <= 0 { return "The total length has to be more than 0." }
        if w < 0 { return "The piece width can't be negative." }
        if layout == .flushEnds && n < 2 { return "Flush at ends needs at least 2 pieces." }
        if Double(n) * w > l {
            // Rounded to the precision, a near miss could read as "36" together, more than the 36"
            // space". Show more decimals then.
            var total = fmt(Double(n) * w), space = fmt(l)
            if total == space {
                let mark = unit == .imperial ? "\"" : " mm"
                total = Format.decimal(Double(n) * w * (unit == .imperial ? 1 : 25.4), places: 3) + mark
                space = Format.decimal(l * (unit == .imperial ? 1 : 25.4), places: 3) + mark
            }
            return "\(n) pieces at \(fmt(w)) need \(total) together, more than the \(space) space."
        }
        return nil
    }

    @ViewBuilder private func results(_ s: EvenSpacing) -> some View {
        let w = width ?? 0
        Section {
            BigResult(title: w > 0 ? "Gap" : "Spacing",
                      value: fmt(w > 0 ? s.gap : s.centerToCenter),
                      detail: unit.detail(w > 0 ? s.gap : s.centerToCenter, precision: precision))
            if w > 0 && s.centers.count > 1 {
                ResultRow(label: "Center to center", value: fmt(s.centerToCenter))
            }
            if layout == .gapsAtEnds && w == 0 {
                ResultRow(label: "From each end", value: fmt(s.gap))
            }
            // At the fraction precision, very small spacing rounds to 0 and marks repeat.
            if unit == .imperial, s.centerToCenter > 0, s.centerToCenter < 1.0 / Double(precision) {
                Callout(kind: .warning, text: "The spacing is under 1/\(precision)\", so some marks below round to the same number.")
            }
        }

        Section {
            ForEach(Array(s.leftEdges.enumerated()), id: \.offset) { index, edge in
                LabeledContent {
                    // Two right-aligned columns so the numbers line up from row to row.
                    HStack(spacing: 12) {
                        if w > 0 {
                            Text(fmt(edge)).frame(minWidth: 80, alignment: .trailing)
                        }
                        Text(fmt(s.centers[index])).frame(minWidth: 80, alignment: .trailing)
                    }
                    .font(.callout.monospacedDigit())
                } label: {
                    Text("\(index + 1)")
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(w > 0
                    ? "Piece \(index + 1). Near edge \(fmt(edge)). Center \(fmt(s.centers[index]))."
                    : "Mark \(index + 1). \(fmt(s.centers[index])).")
            }
        } header: {
            if w > 0 {
                HStack(spacing: 12) {
                    Text("From the start")
                    Spacer()
                    Text("Edge").frame(minWidth: 80, alignment: .trailing)
                    Text("Center").frame(minWidth: 80, alignment: .trailing)
                }
            } else {
                Text("Marks from the start")
            }
        } footer: {
            Text(unit == .imperial
                 ? "Marks round to the nearest 1/\(precision)\". Measure every mark from the same end to keep rounding from adding up."
                 : "Measure every mark from the same end to keep rounding from adding up.")
        }
    }
}
