// ShelfSagView.swift
//
// Shelf Sag planner. Estimates how much a shelf will bow under a load spread along it, compares
// that with the usual 0.02" per foot target, and gives the load the shelf can carry within it.
// An optional solid wood edging strip on the front stiffens the shelf.
//
// How it's built: sizes are LengthField entries parsed through the current UnitSystem. The load
// is a WeightField, typed in pounds or kilograms. Materials are enums under plain keys. ShelfSag
// in Core/Planners.swift does the math.

import SwiftUI

/// The Shelf Sag planner.
struct ShelfSagView: View {
    @AppStorage(Keys.units) private var unit: UnitSystem = .imperial
    @AppStorage(LengthField.shSpan.key) private var spanText = LengthField.shSpan.imperialDefault
    @AppStorage(LengthField.shDepth.key) private var depthText = LengthField.shDepth.imperialDefault
    @AppStorage(LengthField.shThickness.key) private var thicknessText = LengthField.shThickness.imperialDefault
    @AppStorage(LengthField.shEdgeThickness.key) private var edgeThicknessText = LengthField.shEdgeThickness.imperialDefault
    @AppStorage(LengthField.shEdgeHeight.key) private var edgeHeightText = LengthField.shEdgeHeight.imperialDefault
    @AppStorage(WeightField.shelfLoad.key) private var loadText = WeightField.shelfLoad.imperialDefault
    @AppStorage("sh_material") private var material: ShelfMaterial = .plywood
    @AppStorage("sh_edgeMaterial") private var edgeMaterial: ShelfMaterial = .hardMaple

    private var weightUnit: String { unit == .imperial ? "lb" : "kg" }

    /// Edging size in inches: (0, 0) when both fields are blank, nil when only one is filled or a
    /// non-blank entry can't be read or is negative.
    private var edging: (t: Double, h: Double)? {
        let tBlank = edgeThicknessText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hBlank = edgeHeightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if tBlank && hBlank { return (0, 0) }
        if tBlank != hBlank { return nil }
        guard let t = unit.inches(edgeThicknessText), let h = unit.inches(edgeHeightText),
              t >= 0, h >= 0 else { return nil }
        return (t, h)
    }

    private var hasEdging: Bool {
        guard let e = edging else { return false }
        return e.t > 0 && e.h > 0
    }

    private var result: ShelfSag? {
        guard let l = unit.inches(spanText), let b = unit.inches(depthText), let h = unit.inches(thicknessText),
              let load = WeightField.pounds(loadText, unit: unit), let e = edging else { return nil }
        return ShelfSag.make(span: l, depth: b, thickness: h, material: material, load: load,
                             edgeThickness: e.t, edgeHeight: e.h, edgeMaterial: edgeMaterial)
    }

    /// A small length like sag: 0.104" or 2.6 mm. Fractions would round these to nothing.
    private func small(_ inches: Double) -> String {
        unit == .imperial ? Format.decimal(inches, places: 3) + "\"" : Format.mmNumber(inches, places: 1) + " mm"
    }

    /// Sag per foot in imperial, per meter in metric. The verdict uses the exact value, the same
    /// in both units. When the sag is over the target but rounds to it or below, this says "Just
    /// over" instead, so the figure never reads "0.020" per foot" next to "More than 0.020" per foot".
    private func perRun(_ s: ShelfSag) -> String {
        let shown: String
        let limit: Double
        if unit == .imperial {
            shown = Format.decimal(s.sagPerFoot, places: 3)
            limit = 0.02
        } else {
            shown = Format.decimal(s.sagPerFoot * 25.4 / 0.3048, places: 2)
            limit = 1.67
        }
        if !s.meetsTarget, let v = Double(shown), v <= limit { return "Just over " + targetText }
        return shown + (unit == .imperial ? "\" per foot" : " mm per m")
    }

    private var targetText: String { unit == .imperial ? "0.020\" per foot" : "1.67 mm per m" }

    /// A load, rounded down so the figure shown never puts the shelf over the target.
    private func weight(_ pounds: Double) -> String {
        let v = unit == .imperial ? pounds : pounds * kilogramsPerPound
        let places = v < 10 ? 1 : 0
        let scale = places == 1 ? 10.0 : 1.0
        return Format.trimmed((v * scale).rounded(.down) / scale, places: places) + " " + weightUnit
    }

    var body: some View {
        Form {
            Section {
                MeasureField(label: "Span", text: $spanText, caption: "Between the supports")
                MeasureField(label: "Depth", text: $depthText, caption: "Front to back")
                MeasureField(label: "Thickness", text: $thicknessText)
                Picker("Material", selection: $material) {
                    ForEach(ShelfMaterial.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Shelf")
            }

            Section {
                NumberField(label: "Total load", text: $loadText, suffix: weightUnit,
                            caption: unit == .imperial
                                ? "Spread along the shelf. Books weigh about 20 lb per foot of shelf."
                                : "Spread along the shelf. Books weigh about 30 kg per meter of shelf.",
                            reader: { WeightField.pounds($0, unit: unit) },
                            invalidMessage: "Enter a weight, like \(unit == .imperial ? "60" : "27")")
            } header: {
                Text("Load")
            }

            Section {
                MeasureField(label: "Edging thickness", text: $edgeThicknessText, caption: "Front to back", optional: true)
                MeasureField(label: "Edging height", text: $edgeHeightText, caption: "Top to bottom, flush with the shelf top", optional: true)
                if hasEdging {
                    Picker("Edging wood", selection: $edgeMaterial) {
                        ForEach(ShelfMaterial.solidWoods) { Text($0.label).tag($0) }
                    }
                }
            } header: {
                Text("Front edging (optional)")
            } footer: {
                Text("A solid wood strip glued to the front edge. Leave both blank for none. A strip taller than the shelf is thick stiffens it the most.")
            }

            if let s = result {
                results(s)
            } else if let problem {
                // A half-filled edging is usually mid-entry, so it gets a gentle note, not a warning.
                let halfEdging = problem.hasPrefix("Enter both edging")
                Section { Callout(kind: halfEdging ? .info : .warning, text: problem) }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Shelf Sag")
        .settingsButton()
    }

    /// Why there's no result when the entries are readable but out of range.
    private var problem: String? {
        let tBlank = edgeThicknessText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hBlank = edgeHeightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if tBlank != hBlank { return "Enter both edging sizes, or leave both blank." }
        if edging == nil, let t = unit.inches(edgeThicknessText), let h = unit.inches(edgeHeightText), t < 0 || h < 0 {
            return "Edging sizes can't be negative."
        }
        guard let l = unit.inches(spanText), let b = unit.inches(depthText), let h = unit.inches(thicknessText),
              let load = WeightField.pounds(loadText, unit: unit) else { return nil }
        if l <= 0 || b <= 0 || h <= 0 { return "Span, depth and thickness have to be more than 0." }
        if load < 0 { return "The load can't be negative." }
        return nil
    }

    @ViewBuilder private func results(_ s: ShelfSag) -> some View {
        Section {
            BigResult(title: "Sag", value: small(s.sag), detail: perRun(s))
            if s.meetsTarget {
                Callout(kind: .info, text: "Within the usual target of \(targetText). Sag this small is hard to see.")
            } else {
                Callout(kind: .warning, text: "More than \(targetText), enough to notice. A shorter span, a thicker or stiffer shelf, or a front edging strip will help.")
            }
            ResultRow(label: "After a few years", value: small(s.longTermSag))
            ResultRow(label: "Most load within target", value: weight(s.loadForTarget))
        } footer: {
            Text("For a shelf resting on supports at each end with the load spread evenly. Shelves keep sagging slowly under a steady load: about half again for solid wood, about double for plywood, and more for MDF and particleboard. A shelf fixed in dadoes sags a little less. Stiffness figures are averages, so real shelves vary.")
        }
    }
}
