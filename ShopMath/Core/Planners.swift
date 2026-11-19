// Planners.swift
// Shop Math
//
// Math for the three planners added in 1.2: even spacing, drawer sizing, and shelf sag. Like the
// rest of the core, every length is in inches and nothing here imports SwiftUI, so it can be
// tested on its own. The screens that use it are SpacingView, DrawerView and ShelfSagView.

import Foundation

// MARK: - Even spacing

/// How the pieces sit in the space.
enum SpacingLayout: String, CaseIterable, Identifiable, Codable {
    /// Equal gaps everywhere, including between the end pieces and each end of the space.
    /// Balusters, slats in a frame, shelf pins with equal margins.
    case gapsAtEnds
    /// The first and last pieces sit tight against the ends; only the gaps between pieces count.
    /// Pickets between two posts that also act as the first and last picket, hooks on a rail.
    case flushEnds

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gapsAtEnds: return "Gaps at ends"
        case .flushEnds: return "Flush at ends"
        }
    }
}

/// Equal spacing for a number of identical pieces in a fixed length. A piece width of 0 spaces
/// points instead, such as holes or screw marks.
struct EvenSpacing: Equatable {
    /// The gap between neighboring pieces (and at the ends for gapsAtEnds).
    let gap: Double
    /// Distance from one piece's center to the next.
    let centerToCenter: Double
    /// Each piece's near edge, measured from the start of the space.
    let leftEdges: [Double]
    /// Each piece's center, measured from the start of the space.
    let centers: [Double]

    /// Most pieces the planner accepts. Keeps the position list a sensible size.
    static let maxCount = 500

    /// Returns nil when the pieces can't fit or the inputs don't make sense: a length that isn't
    /// positive, a negative width, a count outside 1...maxCount, flushEnds with fewer than two
    /// pieces, or pieces that together are wider than the space.
    static func make(length l: Double, count n: Int, pieceWidth w: Double, layout: SpacingLayout) -> EvenSpacing? {
        guard l.isFinite, w.isFinite, l > 0, w >= 0, n >= 1, n <= maxCount else { return nil }
        let free = l - Double(n) * w
        // Allow a hair of rounding error so pieces that exactly fill the space give a gap of 0.
        guard free >= -1e-9 else { return nil }
        let gaps: Int
        switch layout {
        case .gapsAtEnds: gaps = n + 1
        case .flushEnds:
            guard n >= 2 else { return nil }
            gaps = n - 1
        }
        let gap = max(0, free) / Double(gaps)
        let first = layout == .gapsAtEnds ? gap : 0
        let edges = (0..<n).map { first + Double($0) * (w + gap) }
        return EvenSpacing(gap: gap, centerToCenter: w + gap,
                           leftEdges: edges, centers: edges.map { $0 + w / 2 })
    }
}

// MARK: - Drawer sizing

/// The kind of drawer slide, which sets how much narrower and shorter the box is than the opening.
enum SlideType: String, CaseIterable, Identifiable, Codable {
    /// Ball bearing slides on the drawer sides, up to about 100 lb. 1/2" per side, plus 1/64" so a
    /// box that glues up a hair wide still fits (the spec is 1/2" +1/32" −0).
    case sideMount
    /// Heavy duty side mount slides, 150 lb and up. 3/4" per side.
    case heavySideMount
    /// Concealed undermount slides like Blum Tandem or Movento. The box's inside width is 42 mm
    /// (about 1 21/32") less than the opening, whatever the side thickness.
    case undermount
    /// The user enters the clearances from the slide's instructions.
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sideMount: return "Side mount"
        case .heavySideMount: return "Heavy duty side mount"
        case .undermount: return "Undermount"
        case .custom: return "Custom"
        }
    }
}

/// How the drawer front relates to the opening.
enum DrawerFrontStyle: String, CaseIterable, Identifiable, Codable {
    /// The front covers the opening and laps onto the face frame or cabinet sides.
    case overlay
    /// The front sits inside the opening, flush with the face.
    case inset

    var id: String { rawValue }
    var label: String { self == .overlay ? "Overlay" : "Inset" }
}

/// How the cabinet is built, which decides where the depth is measured from.
enum CabinetType: String, CaseIterable, Identifiable, Codable {
    /// Depth is measured from the back of the face frame. An inset front sits inside the face
    /// frame, so it takes no depth from the box.
    case faceFrame
    /// Depth is measured from the front edge of the cabinet sides. An inset front sits inside the
    /// cabinet, so its thickness comes off the depth.
    case frameless

    var id: String { rawValue }
    var label: String { self == .faceFrame ? "Face frame" : "Frameless" }
}

/// Everything the drawer planner needs, in inches.
struct DrawerInput {
    var openingWidth: Double
    var openingHeight: Double
    /// Inside depth of the cabinet: from the back of the face frame to the cabinet back, or on a
    /// frameless cabinet from the front edge to the back.
    var openingDepth: Double
    var slide: SlideType
    /// Used only for .custom: total width taken by both slides is twice this.
    var customSideClearance: Double = 0.5
    /// Used only for .custom: opening height minus box height.
    var customHeightClearance: Double = 0.5
    var frontStyle: DrawerFrontStyle
    var cabinet: CabinetType = .faceFrame
    /// Overlay: how far the front laps past the opening on each side. Inset: the gap around the
    /// front on each side.
    var frontReveal: Double
    /// Thickness of the drawer front. Inset fronts in a frameless cabinet take this much depth
    /// from the box.
    var frontThickness: Double
    /// Thickness of the box sides, front and back.
    var sideThickness: Double
    /// Depth of the groove the bottom panel sits in.
    var grooveDepth: Double
    /// True to size the slide and box from metric slide lengths.
    var metricSlides: Bool = false
}

/// Box, parts, slide length and front size for one drawer.
struct DrawerPlan: Equatable {
    /// Outside size of the box.
    let boxWidth: Double
    let boxHeight: Double
    let boxDepth: Double
    /// Longest standard slide that fits, in inches. The box depth equals it.
    let slideLength: Double
    /// Two sides run the full box depth.
    let sideLength: Double
    /// Front and back fit between the sides.
    let frontBackLength: Double
    /// Bottom panel, already 1/16" smaller each way than the grooves so it can move.
    let bottomWidth: Double
    let bottomDepth: Double
    /// Drawer front.
    let frontWidth: Double
    let frontHeight: Double
    /// Width the slides take on each side, as used.
    let sideClearance: Double
    /// Opening height minus box height, as used.
    let heightClearance: Double

    /// Slide lengths sold in each system, in inches. Side mount slides come in 2" steps; most
    /// undermount slides in 3" steps. Metric lines run in 50 mm steps, plus Blum's 270 mm.
    static func standardSlides(for slide: SlideType, metric: Bool) -> [Double] {
        if metric {
            let mm: [Double] = slide == .undermount
                ? [250, 270, 300, 350, 400, 450, 500, 550, 600]
                : [250, 300, 350, 400, 450, 500, 550, 600, 650, 700]
            return mm.map { $0 / 25.4 }
        }
        // Blum Tandem stops at 21".
        return slide == .undermount
            ? [9, 12, 15, 18, 21]
            : [10, 12, 14, 16, 18, 20, 22, 24, 26, 28]
    }

    /// Room the slide needs behind the box: rear brackets for side mount, the locking devices and
    /// rear hooks for undermount. Blum's shortest runner (9", 250 mm) needs more, about 10 15/32"
    /// of cabinet depth.
    static func rearAllowance(for slide: SlideType, length: Double? = nil) -> Double {
        guard slide == .undermount else { return 0.5 }
        if let length, length < 10 { return 1.5 }
        return 1
    }

    /// Clearance per side and total height clearance for a slide type, in inches.
    static func clearances(_ i: DrawerInput) -> (side: Double, height: Double) {
        switch i.slide {
        case .sideMount: return (0.5 + 1.0 / 64, 0.5)
        case .heavySideMount: return (0.75, 0.5)
        case .undermount:
            // The inside of the box is 42 mm (1 21/32") narrower than the opening, so the clearance
            // per side depends on how thick the sides are: about 3/16" with 5/8" sides. The box is
            // 21 mm (13/16") shorter than the opening: room under it for the slide and 7 mm above.
            return ((42 / 25.4 - 2 * i.sideThickness) / 2, 21 / 25.4)
        case .custom: return (i.customSideClearance, i.customHeightClearance)
        }
    }

    /// Depth an inset front takes from the box: its thickness in a frameless cabinet, where it
    /// sits inside the cabinet sides. In a face frame cabinet it sits inside the face frame, in
    /// front of where the depth is measured.
    static func insetDepthLoss(_ i: DrawerInput) -> Double {
        i.frontStyle == .inset && i.cabinet == .frameless ? i.frontThickness : 0
    }

    /// The longest standard slide that fits `availableDepth` (cabinet depth less any inset front)
    /// with its rear allowance, or nil.
    static func longestSlide(_ slide: SlideType, metric: Bool, availableDepth: Double) -> Double? {
        standardSlides(for: slide, metric: metric)
            .last(where: { $0 + rearAllowance(for: slide, length: $0) <= availableDepth + 1e-9 })
    }

    /// Thickest drawer side undermount slides take.
    static func maxUndermountSide(metric: Bool) -> Double { metric ? 16 / 25.4 : 0.625 }

    /// Bottom panel play: the panel is cut this much smaller than groove to groove, each way.
    static let bottomPlay = 1.0 / 16

    /// Returns nil when the opening is too small for the slides and box, the depth doesn't fit any
    /// standard slide, or an entry is out of range (sizes not positive, negative allowances, or an
    /// inset gap that leaves no front).
    static func make(_ i: DrawerInput) -> DrawerPlan? {
        let values = [i.openingWidth, i.openingHeight, i.openingDepth, i.customSideClearance,
                      i.customHeightClearance, i.frontReveal, i.frontThickness, i.sideThickness, i.grooveDepth]
        guard values.allSatisfy({ $0.isFinite }),
              i.openingWidth > 0, i.openingHeight > 0, i.openingDepth > 0,
              i.sideThickness > 0, i.grooveDepth >= 0, i.frontReveal >= 0, i.frontThickness >= 0 else { return nil }
        let c = clearances(i)
        guard c.side >= 0, c.height >= 0 else { return nil }
        // Undermount slides take sides up to 5/8" (16 mm). Thicker sides leave no room for them.
        if i.slide == .undermount && i.sideThickness > maxUndermountSide(metric: i.metricSlides) + 1e-9 { return nil }

        let boxWidth = i.openingWidth - 2 * c.side
        let boxHeight = i.openingHeight - c.height
        let innerWidth = boxWidth - 2 * i.sideThickness
        // The box needs some inside room, and the groove can't go deeper than the sides are thick.
        guard innerWidth > 0, boxHeight > 0, i.grooveDepth < i.sideThickness else { return nil }

        let available = i.openingDepth - insetDepthLoss(i)
        guard let slide = longestSlide(i.slide, metric: i.metricSlides, availableDepth: available) else { return nil }
        let boxDepth = slide
        let innerDepth = boxDepth - 2 * i.sideThickness
        guard innerDepth > 0 else { return nil }

        let frontWidth: Double
        let frontHeight: Double
        switch i.frontStyle {
        case .overlay:
            frontWidth = i.openingWidth + 2 * i.frontReveal
            frontHeight = i.openingHeight + 2 * i.frontReveal
        case .inset:
            frontWidth = i.openingWidth - 2 * i.frontReveal
            frontHeight = i.openingHeight - 2 * i.frontReveal
        }
        guard frontWidth > 0, frontHeight > 0 else { return nil }

        return DrawerPlan(
            boxWidth: boxWidth, boxHeight: boxHeight, boxDepth: boxDepth,
            slideLength: slide,
            sideLength: boxDepth,
            frontBackLength: innerWidth,
            bottomWidth: innerWidth + 2 * i.grooveDepth - bottomPlay,
            bottomDepth: innerDepth + 2 * i.grooveDepth - bottomPlay,
            frontWidth: frontWidth, frontHeight: frontHeight,
            sideClearance: c.side, heightClearance: c.height)
    }
}

// MARK: - Shelf sag

/// Shelf and edging materials with their stiffness (modulus of elasticity) in psi.
///
/// Solid woods are the average for clear, straight grained wood at 12% moisture from the USDA
/// Forest Products Laboratory's Wood Handbook, table 5-3b. Red oak is northern red oak and Douglas
/// fir is coast Douglas fir. Sheet goods vary a lot by maker and grade, so they use the low end of
/// published figures: ANSI A208.2 grade 130 MDF, common industrial particleboard, and 3/4"
/// veneer core hardwood plywood along the face grain. MDF core plywood should be entered as MDF.
enum ShelfMaterial: String, CaseIterable, Identifiable, Codable {
    case plywood, mdf, particleboard
    case redOak, whiteOak, hardMaple, cherry, walnut, ash, birch, poplar, douglasFir, pine

    var id: String { rawValue }

    var label: String {
        switch self {
        case .plywood: return "Plywood (hardwood veneer)"
        case .mdf: return "MDF"
        case .particleboard: return "Particleboard or melamine"
        case .redOak: return "Red oak"
        case .whiteOak: return "White oak"
        case .hardMaple: return "Hard maple"
        case .cherry: return "Cherry"
        case .walnut: return "Walnut"
        case .ash: return "Ash"
        case .birch: return "Yellow birch"
        case .poplar: return "Poplar"
        case .douglasFir: return "Douglas fir"
        case .pine: return "White pine"
        }
    }

    /// Modulus of elasticity, psi.
    var modulus: Double {
        switch self {
        case .plywood: return 800_000
        case .mdf: return 313_000
        case .particleboard: return 290_000
        case .redOak: return 1_820_000
        case .whiteOak: return 1_780_000
        case .hardMaple: return 1_830_000
        case .cherry: return 1_490_000
        case .walnut: return 1_680_000
        case .ash: return 1_740_000
        case .birch: return 2_010_000
        case .poplar: return 1_580_000
        case .douglasFir: return 1_950_000
        case .pine: return 1_240_000
        }
    }

    /// The solid woods, for the edging picker.
    static var solidWoods: [ShelfMaterial] { allCases.filter { !$0.isSheetGood } }

    var isSheetGood: Bool { self == .plywood || self == .mdf || self == .particleboard }

    /// How much more a shelf sags after carrying its load for years. Seasoned solid wood adds
    /// about half again; panels creep more, about double (the NDS uses 2.0 for wood panels), and
    /// MDF and particleboard more than that.
    var creepFactor: Double {
        switch self {
        case .plywood: return 2.0
        case .mdf, .particleboard: return 2.5
        default: return 1.5
        }
    }
}

/// Sag of a shelf that rests on supports at each end and carries a load spread evenly along it.
/// Lengths in inches, load in pounds.
struct ShelfSag: Equatable {
    /// Sag at the middle when the load goes on.
    let sag: Double
    /// Sag per foot of span, the figure the 0.02" rule uses.
    let sagPerFoot: Double
    /// Expected sag after the shelf has carried the load for a long time. Wood keeps creeping
    /// under a steady load; see ShelfMaterial.creepFactor.
    let longTermSag: Double
    /// Total load at which the initial sag reaches the target.
    let loadForTarget: Double

    /// The usual target: 0.02" of sag per foot of span. Less than that is hard to see.
    static let targetPerFoot = 0.02

    /// Whether the initial sag is within the target. A small tolerance keeps a result that prints
    /// as exactly the target from being called over it.
    var meetsTarget: Bool { sagPerFoot <= Self.targetPerFoot + 1e-9 }

    /// Bending stiffness E·I in lb·in² of a rectangular shelf with an optional edging strip at the
    /// front whose top is flush with the shelf top. Edging thickness runs front to back; its height
    /// runs up and down and may be more than the shelf's thickness (an apron below).
    static func stiffness(depth b: Double, thickness h: Double, modulus e1: Double,
                          edgeThickness te: Double = 0, edgeHeight he: Double = 0, edgeModulus e2: Double = 0) -> Double {
        let a1 = b * h, y1 = h / 2
        guard te > 0, he > 0, e2 > 0 else { return e1 * b * h * h * h / 12 }
        let a2 = te * he, y2 = he / 2
        // Neutral axis of the combined section, weighting each part's area by its stiffness.
        let yBar = (e1 * a1 * y1 + e2 * a2 * y2) / (e1 * a1 + e2 * a2)
        let i1 = b * h * h * h / 12 + a1 * (y1 - yBar) * (y1 - yBar)
        let i2 = te * he * he * he / 12 + a2 * (y2 - yBar) * (y2 - yBar)
        return e1 * i1 + e2 * i2
    }

    /// Returns nil for a span, depth or thickness that isn't positive, a negative load or edging
    /// size, or values that aren't finite. A load of 0 gives 0 sag.
    static func make(span l: Double, depth b: Double, thickness h: Double, material: ShelfMaterial,
                     load: Double, edgeThickness te: Double = 0, edgeHeight he: Double = 0,
                     edgeMaterial: ShelfMaterial = .hardMaple) -> ShelfSag? {
        let values = [l, b, h, load, te, he]
        guard values.allSatisfy({ $0.isFinite }), l > 0, b > 0, h > 0, load >= 0, te >= 0, he >= 0 else { return nil }
        let ei = stiffness(depth: b, thickness: h, modulus: material.modulus,
                           edgeThickness: te, edgeHeight: he, edgeModulus: edgeMaterial.modulus)
        guard ei > 0, ei.isFinite else { return nil }
        // Simply supported beam with a uniform load w (lb per inch): sag = 5 w L^4 / (384 E I).
        let w = load / l
        let sag = 5 * w * l * l * l * l / (384 * ei)
        let target = targetPerFoot * l / 12
        // Sag is proportional to load, so the load that gives the target sag scales directly.
        let loadForTarget = 384 * ei * target / (5 * l * l * l)
        guard sag.isFinite, loadForTarget.isFinite else { return nil }
        return ShelfSag(sag: sag, sagPerFoot: sag / (l / 12), longTermSag: sag * material.creepFactor,
                        loadForTarget: loadForTarget)
    }
}

/// Pounds per kilogram, exact by definition of the pound.
let kilogramsPerPound = 0.45359237
