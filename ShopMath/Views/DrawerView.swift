// DrawerView.swift
//
// Drawer Sizer planner. From a cabinet opening and the kind of slides, works out the drawer box
// size, the parts to cut for it, the slide length to buy, and the drawer front.
//
// How it's built: every size is a LengthField entry parsed through the current UnitSystem. The
// slide type and front style are enums under plain keys. DrawerPlan in Core/Planners.swift does
// the math. In metric the planner uses metric slide lengths.

import SwiftUI

/// The Drawer Sizer planner.
struct DrawerView: View {
    @AppStorage(Keys.precision) private var precision = 32
    @AppStorage(Keys.units) private var unit: UnitSystem = .imperial
    @AppStorage(LengthField.drWidth.key) private var widthText = LengthField.drWidth.imperialDefault
    @AppStorage(LengthField.drHeight.key) private var heightText = LengthField.drHeight.imperialDefault
    @AppStorage(LengthField.drDepth.key) private var depthText = LengthField.drDepth.imperialDefault
    @AppStorage(LengthField.drOverlay.key) private var overlayText = LengthField.drOverlay.imperialDefault
    @AppStorage(LengthField.drGap.key) private var gapText = LengthField.drGap.imperialDefault
    @AppStorage(LengthField.drFrontThickness.key) private var frontThicknessText = LengthField.drFrontThickness.imperialDefault
    @AppStorage(LengthField.drSide.key) private var sideText = LengthField.drSide.imperialDefault
    @AppStorage(LengthField.drGroove.key) private var grooveText = LengthField.drGroove.imperialDefault
    @AppStorage(LengthField.drCustomSide.key) private var customSideText = LengthField.drCustomSide.imperialDefault
    @AppStorage(LengthField.drCustomHeight.key) private var customHeightText = LengthField.drCustomHeight.imperialDefault
    @AppStorage("dr_slide") private var slide: SlideType = .sideMount
    @AppStorage("dr_front") private var frontStyle: DrawerFrontStyle = .overlay
    @AppStorage("dr_cabinet") private var cabinet: CabinetType = .faceFrame

    /// All entries parsed, or nil when one the current choices need is blank or unreadable.
    private var input: DrawerInput? {
        guard let w = unit.inches(widthText), let h = unit.inches(heightText), let d = unit.inches(depthText),
              let side = unit.inches(sideText), let groove = unit.inches(grooveText) else { return nil }
        let reveal: Double
        switch frontStyle {
        case .overlay:
            guard let o = unit.inches(overlayText) else { return nil }
            reveal = o
        case .inset:
            guard let g = unit.inches(gapText) else { return nil }
            reveal = g
        }
        // Front thickness only matters for inset fronts in a frameless cabinet.
        var frontThickness = 0.0
        if needsFrontThickness {
            guard let t = unit.inches(frontThicknessText) else { return nil }
            frontThickness = t
        }
        var customSide = 0.5, customHeight = 0.5
        if slide == .custom {
            guard let cs = unit.inches(customSideText), let ch = unit.inches(customHeightText) else { return nil }
            customSide = cs
            customHeight = ch
        }
        return DrawerInput(openingWidth: w, openingHeight: h, openingDepth: d, slide: slide,
                           customSideClearance: customSide, customHeightClearance: customHeight,
                           frontStyle: frontStyle, cabinet: cabinet, frontReveal: reveal, frontThickness: frontThickness,
                           sideThickness: side, grooveDepth: groove, metricSlides: unit == .metric)
    }

    private var plan: DrawerPlan? { input.flatMap(DrawerPlan.make) }

    private var needsFrontThickness: Bool { frontStyle == .inset && cabinet == .frameless }

    private func fmt(_ v: Double) -> String { unit.length(v, precision: precision) }
    private func dims(_ v: [Double]) -> String { unit.dimensions(v, precision: precision) }

    var body: some View {
        Form {
            Section {
                Picker("Cabinet", selection: $cabinet) {
                    ForEach(CabinetType.allCases) { Text($0.label).tag($0) }
                }
                .adaptivePickerStyle()
                MeasureField(label: "Width", text: $widthText)
                MeasureField(label: "Height", text: $heightText)
                MeasureField(label: "Depth", text: $depthText,
                             caption: cabinet == .faceFrame
                                ? "Back of the face frame to the cabinet back"
                                : "Front edge of the cabinet to the back")
            } header: {
                Text("Opening")
            }

            Section {
                Picker("Type", selection: $slide) {
                    ForEach(SlideType.allCases) { Text($0.label).tag($0) }
                }
                if slide == .custom {
                    MeasureField(label: "Clearance per side", text: $customSideText, caption: "From the slide's instructions")
                    MeasureField(label: "Height clearance", text: $customHeightText, caption: "Opening height minus box height")
                }
            } header: {
                Text("Slides")
            } footer: {
                Text(slideNote)
            }

            Section {
                Picker("Front", selection: $frontStyle) {
                    ForEach(DrawerFrontStyle.allCases) { Text($0.label).tag($0) }
                }
                .adaptivePickerStyle()
                if frontStyle == .overlay {
                    MeasureField(label: "Overlay", text: $overlayText, caption: "How far the front laps past the opening, each side")
                } else {
                    MeasureField(label: "Gap", text: $gapText, caption: "Around the front, each side")
                    if needsFrontThickness {
                        MeasureField(label: "Front thickness", text: $frontThicknessText,
                                     caption: "The front sits inside the cabinet, so it takes up depth")
                    }
                }
            } header: {
                Text("Drawer front")
            }

            Section {
                MeasureField(label: "Side thickness", text: $sideText, caption: "Also the front and back")
                MeasureField(label: "Bottom groove depth", text: $grooveText,
                             caption: "How deep the groove is cut into the sides")
            } header: {
                Text("Box")
            }

            if let p = plan {
                results(p)
            } else if let problem {
                Section { Callout(kind: .warning, text: problem) }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Drawer Sizer")
        .settingsButton()
    }

    /// What the selected slide type assumes.
    private var slideNote: String {
        switch slide {
        case .sideMount:
            return unit == .imperial
                ? "Ball bearing slides up to about 100 lb take 1/2\" per side; the box allows 1/64\" more each side for an easy fit. The box is 1/2\" shorter than the opening."
                : "Ball bearing slides up to about 45 kg take 12.7 mm per side; the box allows 0.4 mm more each side for an easy fit. The box is 12.7 mm shorter than the opening."
        case .heavySideMount:
            return "Heavy duty slides, \(unit == .imperial ? "150 lb" : "68 kg") and up, take about \(fmt(0.75)) per side."
        case .undermount:
            return unit == .imperial
                ? "Concealed slides like Blum Tandem: the inside of the box is 1 21/32\" narrower than the opening and the box 13/16\" shorter, with sides 5/8\" thick or less. They need the bottom recessed 1/2\" and notches and holes at the back, so follow the slide's drilling template."
                : "Concealed slides like Blum Tandem: the inside of the box is 42 mm narrower than the opening and the box 21 mm shorter, with sides 16 mm thick or less. They need the bottom recessed 13 mm and notches and holes at the back, so follow the slide's drilling template."
        case .custom:
            return "Enter the clearances your slide's instructions call for."
        }
    }

    /// Why there's no plan, when the entries are readable. Nil while one is blank or unreadable;
    /// the field says what's wrong.
    private var problem: String? {
        guard let i = input else { return nil }
        if i.openingWidth <= 0 || i.openingHeight <= 0 || i.openingDepth <= 0 { return "The opening sizes have to be more than 0." }
        if i.sideThickness <= 0 { return "Side thickness has to be more than 0." }
        if i.grooveDepth < 0 || i.frontReveal < 0 || i.frontThickness < 0 { return "Sizes can't be negative." }
        if i.grooveDepth >= i.sideThickness { return "The bottom groove has to be shallower than the sides are thick." }
        let c = DrawerPlan.clearances(i)
        if i.slide == .undermount && i.sideThickness > DrawerPlan.maxUndermountSide(metric: i.metricSlides) + 1e-9 {
            return "Sides this thick don't fit undermount slides. Use \(unit == .imperial ? "5/8\"" : "16 mm") or thinner."
        }
        if c.side < 0 || c.height < 0 { return "Clearances can't be negative." }
        if i.openingWidth - 2 * c.side - 2 * i.sideThickness <= 0 { return "The opening is too narrow for the slides and sides." }
        if i.openingHeight - c.height <= 0 { return "The opening is too short for the slides." }
        if i.frontStyle == .inset && (i.openingWidth <= 2 * i.frontReveal || i.openingHeight <= 2 * i.frontReveal) {
            return "The gap leaves no room for the front."
        }
        if let slideFits = DrawerPlan.longestSlide(i.slide, metric: i.metricSlides,
                                                   availableDepth: i.openingDepth - DrawerPlan.insetDepthLoss(i)),
           slideFits <= 2 * i.sideThickness {
            return "The sides are too thick for a box this short."
        }
        let shortest = DrawerPlan.standardSlides(for: i.slide, metric: i.metricSlides).first ?? 0
        let needed = shortest + DrawerPlan.rearAllowance(for: i.slide, length: shortest) + DrawerPlan.insetDepthLoss(i)
        return "No standard slide fits. The shortest, \(fmt(shortest)), needs at least \(fmt(needed)) of depth."
    }

    @ViewBuilder private func results(_ p: DrawerPlan) -> some View {
        let h = p.boxHeight
        Section {
            BigResult(title: "Drawer box", value: dims([p.boxWidth, h, p.boxDepth]),
                      detail: "Width × height × depth, outside")
            ResultRow(label: "Slide length", value: fmt(p.slideLength))
        }

        Section {
            ResultRow(label: "Sides (2)", value: dims([p.sideLength, h]))
            ResultRow(label: "Front and back (2)", value: dims([p.frontBackLength, h]))
            ResultRow(label: "Bottom (1)", value: dims([p.bottomWidth, p.bottomDepth]))
            ResultRow(label: "Drawer front (1)", value: dims([p.frontWidth, p.frontHeight]))
        } header: {
            Text("Cut list")
        } footer: {
            Text("Sides, front and back are length × height, and the drawer front is width × height. The bottom is width × depth, \(fmt(DrawerPlan.bottomPlay)) smaller each way than groove to groove so it can move. The box's front and back fit between the sides; for dovetails or other joints that lap, add the joint to their length.")
        }
    }
}
