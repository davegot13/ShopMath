// AnglesView.swift
//
// Angles tab. Gives miter saw settings (miter and bevel) for three kinds of project: a flat
// frame, a box with straight sides and mitered corners, and a sloped box whose sides lean out.
// For flat frames and straight boxes it also works out the piece length from the outside size.
//
// How it's built: the project kind, side count and side tilt are stored in @AppStorage under
// plain keys because they aren't lengths. The outside size and stock width are LengthField
// entries stored as text and parsed through the current UnitSystem into inches. Angles from
// Core/ShopMath.swift does the math. Angles are shown with Format.degrees; piece lengths are
// formatted back through the UnitSystem.

import SwiftUI

/// The Angles tab: saw settings for regular polygons, and piece lengths for frames and boxes.
struct AnglesView: View {
    /// Which project the settings are for. The raw value is the picker label and is what gets
    /// stored under "angles_kind".
    enum Kind: String, CaseIterable, Identifiable {
        case frame = "Flat frame"
        case box = "Box"
        case sloped = "Sloped box"
        var id: String { rawValue }
    }

    // MARK: - Stored entries

    // Kind, side count and tilt aren't lengths, so they use plain keys and the in/mm toggle
    // leaves them alone. The tilt is in degrees and is parsed as a plain number.
    @AppStorage(Keys.precision) private var precision = 32
    @AppStorage("angles_kind") private var kindRaw = Kind.frame.rawValue
    @AppStorage("angles_sides") private var sides = 4
    @AppStorage("angles_tilt") private var tiltText = "15"
    // Lengths for the piece length section. LengthField keys let the unit switch convert them.
    // They start empty, so no piece lengths show until the user enters a size.
    @AppStorage(LengthField.anglesAcross.key) private var acrossText = ""
    @AppStorage(LengthField.anglesStock.key) private var stockText = ""
    @AppStorage(Keys.units) private var unit: UnitSystem = .imperial

    // MARK: - Computed results

    /// Falls back to a flat frame when the stored text doesn't match a case.
    private var kind: Kind { Kind(rawValue: kindRaw) ?? .frame }

    /// Saw settings for the current project. Only the sloped box can fail: a tilt that isn't a
    /// number, or isn't at least 0° and under 90°, gives nil and the warning section.
    private var settings: SawSettings? {
        switch kind {
        case .frame: return Angles.flatFrame(sides: sides)
        case .box: return Angles.straightBox(sides: sides)
        case .sloped:
            guard let t = number(tiltText) else { return nil }
            return Angles.compound(sides: sides, tiltFromVertical: t)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Project", selection: $kindRaw) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text(kindHelp)
                }

                Section {
                    Stepper("Sides: \(sides)", value: $sides, in: 3...24)
                    if kind == .sloped {
                        NumberField(label: "Side tilt", text: $tiltText, suffix: "°",
                                    caption: "From vertical. 0° is straight sides.")
                    }
                }

                if let s = settings {
                    Section {
                        BigResult(title: "Miter", value: Format.degrees(s.miter))
                        BigResult(title: "Bevel", value: Format.degrees(s.bevel))
                        // Interior angle of the regular polygon, seen from above.
                        ResultRow(label: "Angle between sides", value: Format.degrees(180 - 360 / Double(sides)))
                        if kind == .sloped, let t = number(tiltText), t > 0 {
                            Callout(kind: .info, text: "Rip the top and bottom edges of each side at a \(Format.degrees(t)) bevel so the box sits flat and the rim is level.")
                        }
                        if kind == .box {
                            Callout(kind: .info, text: "Cut with the board flat on the saw and the blade tilted. For narrow stock you can stand it on edge against the fence and use a \(Format.degrees(180 / Double(sides))) miter instead.")
                        }
                    } header: {
                        Text("Saw settings")
                    } footer: {
                        // Each side has two mitered ends, so an angle error repeats 2n times.
                        Text("Board flat on the saw table. Miter is the table angle from the 0° detent, bevel is the blade tilt from vertical. Cut a test pair before committing good stock; small errors multiply by \(sides * 2) cuts.")
                    }
                } else {
                    // Only the sloped box can get here, so the message is about the tilt.
                    Section {
                        Callout(kind: .warning, text: "Tilt must be between 0° and 90°.")
                    }
                }

                // The piece length math assumes vertical sides. A sloped side's length changes
                // with height, so the section is hidden for the sloped box.
                if kind != .sloped {
                    sizeSection
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Angles")
            .settingsButton()
        }
    }

    // MARK: - Sections

    /// Footer under the project picker saying what each kind covers.
    private var kindHelp: String {
        switch kind {
        case .frame: return "Picture frames, mirrors, and polygon trays lying flat."
        case .box: return "Boxes with straight sides and mitered corners."
        case .sloped: return "Planters, hoppers, and trays with sides leaning out."
        }
    }

    /// Piece length from the outside size. With an even number of sides that's flat to flat;
    /// with an odd number there is no opposite flat, so it's flat to the opposite point (the
    /// height of a triangle or pentagon sitting on one side). Angles.apothem turns either into
    /// the center to side distance, the stock width comes off that for the inside, and
    /// Angles.edgeLength turns each into an edge length.
    @ViewBuilder private var sizeSection: some View {
        Section {
            MeasureField(label: evenSides ? "Outside, flat to flat" : "Outside, flat to point", text: $acrossText)
            // On a box the side thickness plays the same part as a frame's stock width.
            MeasureField(label: kind == .frame ? "Frame stock width" : "Side thickness", text: $stockText)
            // Entries are parsed to inches and the results formatted back through the unit
            // system. The inside edge only shows when the stock leaves a positive inside size.
            if let d = unit.inches(acrossText), d > 0 {
                let a = Angles.apothem(outside: d, sides: sides)
                let outside = Angles.edgeLength(apothem: a, sides: sides)
                ResultRow(label: "Outside edge (long point)", value: unit.length(outside, precision: precision))
                if let w = unit.inches(stockText), w > 0, a - w > 0 {
                    let inside = Angles.edgeLength(apothem: a - w, sides: sides)
                    ResultRow(label: "Inside edge (short point)", value: unit.length(inside, precision: precision))
                }
            }
        } header: {
            Text("Piece length")
        } footer: {
            Text(evenSides
                 ? "Cut every piece to the same long point length. Measure flat to flat across the outside, not corner to corner."
                 : "Cut every piece to the same long point length. With an odd number of sides, measure from one outside flat straight across to the opposite point.")
        }
    }

    /// Even side counts have opposite flats; odd ones have a point opposite each flat.
    private var evenSides: Bool { sides % 2 == 0 }
}
