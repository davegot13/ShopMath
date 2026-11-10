// EndGrainView.swift
//
// End Grain tab. Plans an end grain cutting board from its finished size: how many strips to
// rip and how long, the first glue-up panel, how many slices to crosscut and at what width,
// the size after each glue-up, and how many board feet of rough lumber to buy.
//
// How it's built: every length (finished size, strip width, panel thickness, the flattening
// and trim allowances, and the shared kerf) is stored in @AppStorage as text under a
// LengthField key and parsed through the current UnitSystem into inches. Lumber yield is a
// percent under a plain key. EndGrainPlan.make from Core/ShopMath.swift does the planning, and
// lengths are formatted back through the UnitSystem.

import SwiftUI

/// The End Grain tab: cut list, glue-up steps, and lumber to buy for an end grain board.
struct EndGrainView: View {
    // MARK: - Stored entries

    // App wide settings. The kerf is the same entry as on the Cleats tab and the Settings sheet.
    @AppStorage(Keys.precision) private var precision = 32
    @AppStorage(Keys.kerf) private var kerfText = LengthField.kerf.imperialDefault
    @AppStorage(Keys.units) private var unit: UnitSystem = .imperial

    // Length entries, stored as the text typed in the current unit system. LengthField keys let
    // the in/mm toggle convert them; the imperial defaults are only fallbacks, because
    // UnitSwitcher.prepare stores every LengthField in the current units at launch.
    @AppStorage(LengthField.egLength.key) private var lengthText = LengthField.egLength.imperialDefault
    @AppStorage(LengthField.egWidth.key) private var widthText = LengthField.egWidth.imperialDefault
    @AppStorage(LengthField.egThickness.key) private var thicknessText = LengthField.egThickness.imperialDefault
    @AppStorage(LengthField.egStripWidth.key) private var stripWidthText = LengthField.egStripWidth.imperialDefault
    @AppStorage(LengthField.egPanel.key) private var panelText = LengthField.egPanel.imperialDefault
    @AppStorage(LengthField.egFlatten1.key) private var flatten1Text = LengthField.egFlatten1.imperialDefault
    @AppStorage(LengthField.egFlatten2.key) private var flatten2Text = LengthField.egFlatten2.imperialDefault
    @AppStorage(LengthField.egEdgeTrim.key) private var edgeTrimText = LengthField.egEdgeTrim.imperialDefault
    @AppStorage(LengthField.egEndTrim.key) private var endTrimText = LengthField.egEndTrim.imperialDefault
    // A percent, not a length, so it uses a plain key and is never converted.
    @AppStorage("eg_yield") private var yieldText = "55"

    // MARK: - Computed results

    /// The whole plan in inches, or nil when an entry can't be read or EndGrainPlan.make rejects
    /// the numbers (a size that isn't positive, a negative allowance, a panel no thicker than its
    /// flattening allowance, or a yield that isn't above 0 and at most 100).
    private var plan: EndGrainPlan? {
        guard let l = unit.inches(lengthText),
              let w = unit.inches(widthText),
              let t = unit.inches(thicknessText),
              let sw = unit.inches(stripWidthText),
              let p = unit.inches(panelText),
              let f1 = unit.inches(flatten1Text),
              let f2 = unit.inches(flatten2Text),
              let et = unit.inches(edgeTrimText),
              let nt = unit.inches(endTrimText),
              let y = number(yieldText) else { return nil }
        return EndGrainPlan.make(EndGrainInput(
            boardLength: l, boardWidth: w, boardThickness: t,
            stripWidth: sw, panelThickness: p,
            firstFlatten: f1, finalFlatten: f2,
            edgeTrim: et, endTrim: nt,
            // An unusable kerf falls back to 1/8"; KerfWarning in the form tells the user.
            kerf: kerfValue(kerfText, unit: unit), yieldPercent: y))
    }

    /// Formats a length in inches through the current unit system at the chosen precision.
    /// Despite the name, it returns millimeters when the units are metric.
    private func inch(_ v: Double) -> String { unit.length(v, precision: precision) }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MeasureField(label: "Length", text: $lengthText, caption: "Along each slice")
                    MeasureField(label: "Width", text: $widthText, caption: "Across the slices")
                    MeasureField(label: "Thickness", text: $thicknessText)
                } header: {
                    Text("Finished board")
                }

                Section {
                    MeasureField(label: "Strip width", text: $stripWidthText,
                                 caption: "Each strip's share of the first panel's width")
                    MeasureField(label: "Panel thickness", text: $panelText,
                                 caption: "First glue-up as glued, before flattening")
                } header: {
                    Text("First glue-up")
                }

                Section {
                    MeasureField(label: "Flatten first panel", text: $flatten1Text, caption: "Total removed")
                    MeasureField(label: "Flatten final board", text: $flatten2Text, caption: "Total removed on the drum sander")
                    MeasureField(label: "Edge trim", text: $edgeTrimText, caption: "Off each glue-up's edges, total")
                    MeasureField(label: "End squaring cut", text: $endTrimText)
                    MeasureField(label: "Blade kerf", text: $kerfText)
                    KerfWarning(text: kerfText)
                    NumberField(label: "Lumber yield", text: $yieldText, suffix: "%",
                                caption: "Usable share of rough stock after milling and defects")
                } header: {
                    Text("Allowances")
                }

                if let p = plan {
                    resultSections(p)
                } else {
                    // Names the two mistakes that are easy to make; the plan also fails on
                    // unreadable entries and the other checks listed on `plan`.
                    Section {
                        Callout(kind: .warning, text: "Check the inputs. Panel thickness has to be more than the flattening allowance, and yield has to be more than 0 and no more than 100.")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("End Grain Board")
            .settingsButton()
        }
    }

    // MARK: - Sections

    /// Cut list and numbered steps for a valid plan. Lengths go through the unit system; lumber
    /// amounts stay in board feet in both systems.
    @ViewBuilder private func resultSections(_ p: EndGrainPlan) -> some View {
        Section {
            BigResult(title: "Strips",
                      value: "\(p.strips) × \(inch(p.stripLength))",
                      detail: "\(inch(p.stripWidth)) wide by \(inch(p.stripHeight)) tall")
            // Net is the volume of the strips themselves. Rough divides it by the yield percent
            // to allow for milling waste and defects.
            ResultRow(label: "Net strip stock", value: "\(Format.decimal(p.netBoardFeet, places: 2)) bf")
            ResultRow(label: "Rough lumber to buy", value: "\(Format.decimal(p.roughBoardFeet, places: 2)) bf")
            // Board feet stay the main figure in both systems, matching the Board Feet tab, which
            // prices per board foot. Metric adds the rough volume in cubic meters as an extra row.
            if unit == .metric {
                ResultRow(label: "Rough lumber volume", value: Format.cubicMeters(boardFeet: p.roughBoardFeet))
            }
        } header: {
            Text("Cut list")
        }

        // The panel length already includes the end squaring cut and one kerf per slice, so the
        // step 2 panel is long enough for every slice in step 3.
        Section {
            step(1, "Rip \(p.strips) strips, each \(inch(p.stripLength)) long.")
            step(2, "Glue the first panel: \(inch(p.panelWidth)) wide × \(inch(p.panelLength)) long. Flatten to \(inch(p.sliceFace)).")
            step(3, "Square one end, then crosscut \(p.slices) slices at \(inch(p.sliceWidth)).")
            step(4, "Turn the slices end grain up and glue. As glued: \(inch(p.asGluedLength)) × \(inch(p.asGluedWidth)).")
            step(5, "Flatten and trim to \(inch(p.finishedLength)) × \(inch(p.finishedWidth)) × \(inch(p.finishedThickness)).")
        } header: {
            Text("Steps")
        } footer: {
            Text("Strip and slice counts round up, so the finished size can come out a little larger than the target. Trim to size, or drop a strip or slice.")
        }
    }

    // MARK: - Helpers

    /// One numbered step row.
    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            Text(text).font(.callout.monospacedDigit())
        }
    }
}
