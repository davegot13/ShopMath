// CleatView.swift
//
// French Cleats tab. Works out the table saw fence setting for ripping French cleats with the
// blade at 45°, either by splitting one board into two matching cleats or by beveling one edge
// of a strip that is already ripped to width. It also shows the wide and narrow face of each
// cleat, a cross section of the cut, safety warnings, and a test cut check that says how far
// to move the fence so both cleats come out the same.
//
// How it's built: every entry is stored in @AppStorage as text. Lengths (board width, target
// cleat width, strip width, thickness, and the two test cut measurements) use LengthField keys.
// The method and "start from" pickers use plain keys. Kerf, precision, blade tilt and units are
// the app wide settings from Keys. Lengths are parsed through the current UnitSystem into
// inches, solved with CleatSplit or CleatEdgeBevel from Core/ShopMath.swift, and formatted back
// through the UnitSystem for display. CleatDiagram, at the bottom of this file, draws the cross
// section with Canvas.

import SwiftUI

/// The French Cleats tab: fence setting, cleat faces, cross section, and test cut check.
struct CleatView: View {
    /// How the cleats are made. The raw value is both the picker label and what is stored under
    /// "cleat_method", so changing a label's text resets saved choices to the default.
    enum Method: String, CaseIterable, Identifiable {
        /// One bevel rip down a board makes two identical cleats.
        case split = "Rip board in half"
        /// One bevel rip along the edge of a strip that is already the cleat width.
        case edge = "Bevel one edge"
        var id: String { rawValue }
    }

    /// For the split method: whether the user enters the board width they have or the cleat
    /// width they want. Stored by raw value under "cleat_solveFrom", like Method.
    enum SolveFrom: String, CaseIterable, Identifiable {
        case board = "Board width"
        case cleat = "Cleat width"
        var id: String { rawValue }
    }

    // MARK: - Stored entries

    // App wide settings, also edited from the Settings sheet. The kerf is a LengthField, so the
    // in/mm toggle converts it like the entries below.
    @AppStorage(Keys.kerf) private var kerfText = LengthField.kerf.imperialDefault
    @AppStorage(Keys.precision) private var precision = 32
    @AppStorage(Keys.tilt) private var tilt: BladeTilt = .awayFromFence
    @AppStorage(Keys.units) private var unit: UnitSystem = .imperial

    // Picker choices. They aren't lengths, so they use plain keys and the unit switch leaves
    // them alone.
    @AppStorage("cleat_method") private var methodRaw = Method.split.rawValue
    @AppStorage("cleat_solveFrom") private var solveRaw = SolveFrom.board.rawValue
    // Length entries, stored as the text the user typed in the current unit system. Because
    // they use LengthField keys, UnitSwitcher.switchTo rewrites each one when the in/mm toggle
    // changes ("5 1/2" becomes "139.7") instead of the old text being read in the new unit.
    // The imperial default is only a fallback: UnitSwitcher.prepare stores every LengthField in
    // the current units at launch.
    @AppStorage(LengthField.cleatBoard.key) private var boardText = LengthField.cleatBoard.imperialDefault
    @AppStorage(LengthField.cleatTarget.key) private var targetText = LengthField.cleatTarget.imperialDefault
    @AppStorage(LengthField.cleatStrip.key) private var stripText = LengthField.cleatStrip.imperialDefault
    @AppStorage(LengthField.cleatThickness.key) private var thicknessText = LengthField.cleatThickness.imperialDefault
    // The test cut measurements are stored like the other lengths instead of being kept in
    // @State. That way switching units converts them along with everything else; @State text
    // would keep its old numbers and be read in the new unit.
    @AppStorage(LengthField.cleatTestFence.key) private var testFenceText = ""
    @AppStorage(LengthField.cleatTestOffcut.key) private var testOffcutText = ""

    // MARK: - Parsed inputs and results

    /// Falls back to the default when the stored text doesn't match a case.
    private var method: Method { Method(rawValue: methodRaw) ?? .split }
    private var solveFrom: SolveFrom { SolveFrom(rawValue: solveRaw) ?? .board }
    /// Kerf in inches. kerfValue uses 1/8" when the entry can't be read or isn't under 1";
    /// KerfWarning tells the user when that happens.
    private var kerf: Double { kerfValue(kerfText, unit: unit) }
    /// Stock thickness in inches, or nil if the entry can't be read.
    private var thickness: Double? { unit.inches(thicknessText) }

    /// Result for the split method, solved from whichever width the user chose to enter. Nil
    /// when an entry can't be read or the board is too narrow for the cut, which shows the
    /// warning section instead.
    private var split: CleatSplit? {
        guard let t = thickness else { return nil }
        switch solveFrom {
        case .board:
            guard let w = unit.inches(boardText) else { return nil }
            return CleatSplit.fromBoard(width: w, thickness: t, kerf: kerf, tilt: tilt)
        case .cleat:
            guard let c = unit.inches(targetText) else { return nil }
            return CleatSplit.fromCleat(longFace: c, thickness: t, kerf: kerf, tilt: tilt)
        }
    }

    /// Result for the edge bevel method. Nil when an entry can't be read or the strip is no
    /// wider than the bevel's run across the thickness.
    private var edge: CleatEdgeBevel? {
        guard let t = thickness, let s = unit.inches(stripText) else { return nil }
        return CleatEdgeBevel.make(stripWidth: s, thickness: t, tilt: tilt)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Method", selection: $methodRaw) {
                        ForEach(Method.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                inputSection
                resultSection

                // The test cut check compares the two pieces of a split, so it only applies to
                // that method.
                if method == .split {
                    testCutSection
                }

                Section("How to set the fence") {
                    Text("Tilt the blade to 45°. Hook a rule on the fence and measure to the fence side of a tooth right where it comes out of the throat plate, at table level. The fence scale is not reliable once the blade is tilted.")
                        .font(.footnote)
                    // At 45° the cut along the slope is the thickness times √2.
                    if let t = thickness {
                        Text("Raise the blade until the teeth clear the top of the board. The cut runs \(len(t * 2.0.squareRoot())) along the slope.")
                            .font(.footnote)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("French Cleats")
            .settingsButton()
        }
    }

    // MARK: - Formatting helpers

    /// Formats a length in inches for display in the current unit system at the chosen precision.
    private func len(_ inches: Double) -> String { unit.length(inches, precision: precision) }

    /// The 1" threshold used by warnings(onTable:), written in the current units.
    private var minPiece: String { unit == .imperial ? "1\"" : "25.4 mm" }

    /// Text for a fence correction. Imperial always rounds to 1/64, finer than the precision
    /// setting may be, and adds the decimal so a small move doesn't round away. Metric shows 0.1 mm.
    private func correction(_ inches: Double) -> String {
        switch unit {
        case .imperial: return "\(Format.inches(inches, denominator: 64)) (\(Format.decimal(inches, places: 3))\")"
        case .metric: return Format.mm(inches)
        }
    }

    // MARK: - Sections

    /// Stock entries. The split method asks for the board or cleat width, the edge method for the
    /// strip width. Thickness, kerf and blade tilt apply to both.
    @ViewBuilder private var inputSection: some View {
        Section {
            switch method {
            case .split:
                Picker("Start from", selection: $solveRaw) {
                    ForEach(SolveFrom.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                if solveFrom == .board {
                    MeasureField(label: "Board width", text: $boardText)
                } else {
                    MeasureField(label: "Cleat width", text: $targetText, caption: "Wide face of each cleat")
                }
            case .edge:
                MeasureField(label: "Strip width", text: $stripText, caption: "Already ripped to width")
            }
            MeasureField(label: "Thickness", text: $thicknessText,
                         caption: unit == .imperial
                            ? "Measure it. 3/4 plywood is often 23/32."
                            : "Measure it. Sheet goods often run under their nominal size.")
            // The kerf and tilt here are the shared settings, so changing them also changes the
            // Settings sheet (and the kerf on the End Grain tab).
            MeasureField(label: "Blade kerf", text: $kerfText)
            KerfWarning(text: kerfText)
            Picker("Blade tilts", selection: $tilt) {
                ForEach(BladeTilt.allCases) { Text($0.label).tag($0) }
            }
        } header: {
            Text("Stock")
        }
    }

    /// Fence setting, face widths, diagram and warnings for the current method, or a warning
    /// section when the inputs don't solve. All lengths are formatted through the unit system.
    @ViewBuilder private var resultSection: some View {
        switch method {
        case .split:
            if let r = split {
                Section {
                    BigResult(title: "Fence setting",
                              value: len(r.fence),
                              detail: unit.detail(r.fence, precision: precision))
                    if solveFrom == .cleat {
                        ResultRow(label: "Rip board to", value: len(r.boardWidth))
                    }
                    ResultRow(label: "Each cleat, wide face", value: len(r.longFace))
                    ResultRow(label: "Each cleat, narrow face", value: len(r.shortFace))
                    // Uses the solved board width, so the diagram also works when solving from
                    // the cleat width.
                    CleatDiagram(boardWidth: r.boardWidth, thickness: r.verticalCut,
                                 fence: r.fence, kerf: kerf, tilt: tilt)
                        .frame(height: 120)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    warnings(onTable: r.fencePieceOnTable)
                } header: {
                    Text("Result")
                } footer: {
                    Text("One cut makes two identical cleats. Flip one end for end to pair them.")
                }
            } else {
                invalidSection
            }
        case .edge:
            // CleatEdgeBevel doesn't carry the strip width or thickness, so they are parsed again
            // here for the diagram.
            if let r = edge, let s = unit.inches(stripText), let t = thickness {
                Section {
                    BigResult(title: "Fence setting",
                              value: len(r.fence),
                              detail: unit.detail(r.fence, precision: precision))
                    ResultRow(label: "Wide face", value: len(r.longFace))
                    ResultRow(label: "Narrow face", value: len(r.shortFace))
                    CleatDiagram(boardWidth: s, thickness: t, fence: r.fence, kerf: kerf, tilt: tilt)
                        .frame(height: 120)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    warnings(onTable: r.fencePieceOnTable)
                } header: {
                    Text("Result")
                } footer: {
                    Text("The kerf lands right at the far corner, so the strip keeps its full width on one face. Kerf does not change this setting.")
                }
            } else {
                invalidSection
            }
        }
    }

    /// Shown in place of the result when an entry can't be read or the geometry doesn't solve.
    /// The rule differs by method: a split has to leave room for the bevel run and the kerf, while
    /// an edge bevel only needs the strip wider than the bevel run (the kerf falls outside it).
    private var invalidSection: some View {
        Section {
            Callout(kind: .warning, text: method == .split
                    ? "Check the inputs. The board has to be wider than its thickness plus the kerf."
                    : "Check the inputs. The strip has to be wider than its thickness.")
        }
    }

    /// Safety callouts for both methods. onTable is the width of the piece between the fence and
    /// the blade at table level, in inches; under 1" puts hands close to the blade.
    @ViewBuilder private func warnings(onTable: Double) -> some View {
        if tilt == .towardFence {
            Callout(kind: .warning, text: "With the blade tilted toward the fence, the fence side piece is trapped under the blade. Move the fence to the other side of the blade if your saw allows it.")
        }
        if onTable < 1 {
            Callout(kind: .warning, text: "The piece between fence and blade is under \(minPiece) at the table. Use a push block and keep your hand off the blade side.")
        }
    }

    /// After a test rip at the computed setting, the user measures the wide face of both pieces.
    /// Moving the fence widens one piece and narrows the other by the same amount, so the fence
    /// moves half the difference (CleatSplit.fenceCorrection). Under 1/128" (about 0.2 mm) is
    /// treated as close enough.
    private var testCutSection: some View {
        Section {
            MeasureField(label: "Fence piece, wide face", text: $testFenceText)
            MeasureField(label: "Offcut, wide face", text: $testOffcutText)
            if let f = unit.inches(testFenceText), let o = unit.inches(testOffcutText) {
                // Positive means the fence piece came out narrower than the offcut, so the fence
                // moves away from the blade.
                let move = CleatSplit.fenceCorrection(fencePieceLongFace: f, offcutLongFace: o)
                if abs(move) < 1.0 / 128 {
                    Callout(kind: .info, text: unit == .imperial
                            ? "Within 1/128\". Leave the fence where it is."
                            : "Within 0.2 mm. Leave the fence where it is.")
                } else {
                    Callout(kind: .info, text: "Move the fence \(correction(abs(move))) \(move > 0 ? "away from" : "toward") the blade.")
                }
            }
        } header: {
            Text("Test cut check")
        } footer: {
            Text("Rip a scrap the same width as your board at the setting above, measure both wide faces, and this tells you how far to move the fence so the two cleats match.")
        }
    }
}

// MARK: - Cross section diagram

/// Cross section of the cut: fence on the left, table along the bottom, kerf shaded.
/// All inputs are in inches, so the drawing is the same in either unit system. The kerf is
/// drawn at a 45° bevel, the angle CleatView solves for.
struct CleatDiagram: View {
    let boardWidth: Double
    let thickness: Double
    /// Fence to the fence side of the kerf, at the table.
    let fence: Double
    let kerf: Double
    let tilt: BladeTilt

    var body: some View {
        Canvas { ctx, size in
            // Margins all round, room on the left for the fence, and 14 pt below the table line
            // for the fence dimension and its label.
            let margin: CGFloat = 12
            let fenceW: CGFloat = 10
            let usableW = size.width - 2 * margin - fenceW
            let usableH = size.height - 2 * margin - 14
            guard boardWidth > 0, thickness > 0, usableW > 0, usableH > 0 else { return }
            // One scale for both axes keeps the 45° bevel looking like 45°. The board fills
            // whichever direction runs out of room first.
            let scale = min(usableW / boardWidth, usableH / thickness)
            let left = margin + fenceW
            let bottom = size.height - margin - 14

            // Maps board coordinates to canvas points. x is inches from the fence face, y is
            // inches above the table (the same coordinates BevelRip uses). Canvas y grows
            // downward, so y is subtracted from the table line.
            func pt(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: left + CGFloat(x) * scale, y: bottom - CGFloat(y) * scale)
            }

            // Table
            var table = Path()
            table.move(to: CGPoint(x: margin / 2, y: bottom))
            table.addLine(to: CGPoint(x: size.width - margin / 2, y: bottom))
            ctx.stroke(table, with: .color(.secondary), lineWidth: 1)

            // Fence
            let fenceRect = CGRect(x: margin, y: bottom - CGFloat(thickness) * scale - 8,
                                   width: fenceW, height: CGFloat(thickness) * scale + 8)
            ctx.fill(Path(fenceRect), with: .color(.gray))

            // Board
            var board = Path()
            board.addRect(CGRect(origin: pt(0, thickness),
                                 size: CGSize(width: CGFloat(boardWidth) * scale, height: CGFloat(thickness) * scale)))
            ctx.fill(board, with: .color(Color(red: 0.86, green: 0.72, blue: 0.52)))

            // Kerf, clipped to the board. The kerf is a slanted band: it starts at the fence
            // setting on the table, is kh wide measured along the table, and shifts sideways by
            // the bevel run r on its way to the top of the board. s is 1 when the blade leans
            // away from the fence and -1 when it leans toward it. On an edge bevel the band runs
            // past the strip's far edge, so it is clipped to the board to shade only wood the
            // blade actually removes.
            let kh = BevelRip.horizontalKerf(kerf)
            let r = BevelRip.run(thickness)
            let s: Double = tilt == .awayFromFence ? 1 : -1
            var cut = Path()
            cut.move(to: pt(fence, 0))
            cut.addLine(to: pt(fence + kh, 0))
            cut.addLine(to: pt(fence + kh + s * r, thickness))
            cut.addLine(to: pt(fence + s * r, thickness))
            cut.closeSubpath()
            // GraphicsContext is a value type, so clipping this copy leaves ctx unclipped for the
            // outline and the dimension below.
            var clipped = ctx
            clipped.clip(to: board)
            clipped.fill(cut, with: .color(.red.opacity(0.75)))

            ctx.stroke(board, with: .color(.brown), lineWidth: 1)

            // Fence dimension under the table: from the fence face to the fence side of the
            // kerf, the distance the user sets.
            let y = bottom + 8
            var dim = Path()
            dim.move(to: CGPoint(x: left, y: y))
            dim.addLine(to: CGPoint(x: left + CGFloat(fence) * scale, y: y))
            ctx.stroke(dim, with: .color(.accentColor), lineWidth: 1.5)
            ctx.draw(Text("fence").font(.caption2).foregroundColor(.accentColor),
                     at: CGPoint(x: left + CGFloat(fence) * scale / 2, y: y + 7))
        }
        .accessibilityLabel("Cross section of the bevel cut")
    }
}
