// ShopMath.swift
//
// The math behind the calculator tabs: French cleat bevel rips, board feet and lumber list
// totals, miter and bevel angles for frames and boxes, and the end grain cutting board planner.
// It imports only Foundation and knows nothing about SwiftUI or stored settings.
//
// The screens in Views/ parse what the user typed (Core/Measure.swift, Core/Units.swift),
// convert it to inches, call into this file, and format the results for the current unit system.
// So every length here is in inches and every angle is in degrees unless noted. Millimeters never
// reach this file.

import Foundation

// MARK: - Helpers

/// Degrees to radians. Foundation's trig functions take radians.
private func rad(_ deg: Double) -> Double { deg * .pi / 180 }
/// Radians to degrees.
private func deg(_ rad: Double) -> Double { rad * 180 / .pi }

// MARK: - French cleats on the table saw
//
// A French cleat pair comes from a bevel rip, normally at 45 degrees. The board lies flat on the
// table with the rip fence on one side of the blade, and the blade tilts either away from the
// fence or toward it. Everything below works in a cross section of the board, with these names:
//
//   t   board thickness
//   k   kerf, measured across the blade (the number on the blade's spec)
//   kh  the kerf's width along the table: k / cos(bevel)
//   r   the bevel's horizontal run through the thickness: t · tan(bevel)
//   a   the fence setting: fence to the fence side of the kerf, at the table

/// Which way the top of the blade leans relative to the rip fence. It decides which piece has its
/// wide face down on the table, so it changes the fence setting. Stored with @AppStorage through
/// its String raw value.
enum BladeTilt: String, CaseIterable, Identifiable, Codable {
    case awayFromFence
    case towardFence

    var id: String { rawValue }

    var label: String {
        switch self {
        case .awayFromFence: return "Away from fence"
        case .towardFence: return "Toward fence"
        }
    }
}

/// Geometry of one bevel rip. The fence distance is measured at the table surface from the
/// fence to the fence side of the kerf (the tooth nearest the fence where it leaves the throat plate).
///
/// Coordinates: x is distance from the fence, y is height above the table.
/// The fence side of the kerf is the line x = fence ± y·tan(bevel): plus when the blade tilts
/// away from the fence, minus when it tilts toward it.
/// Kerf width k is measured across the blade, so on the table it spans k / cos(bevel).
struct BevelRip {
    /// Width of the kerf along the table, or along any horizontal line, in inches. The blade's
    /// faces lean `bevel` degrees from vertical, so a horizontal line crosses the kerf at that
    /// angle and sees k / cos(bevel). At 45 degrees a 1/8" kerf spans about 0.177".
    static func horizontalKerf(_ kerf: Double, bevel: Double = 45) -> Double {
        kerf / cos(rad(bevel))
    }

    /// How far the cut line moves sideways while rising through `thickness`, in inches:
    /// t · tan(bevel). At 45 degrees it equals the thickness. Each beveled piece has one face
    /// this much wider than the other.
    static func run(_ thickness: Double, bevel: Double = 45) -> Double {
        thickness * tan(rad(bevel))
    }
}

/// The result of ripping one board into two French cleats with a single bevel cut. All lengths
/// are in inches.
struct CleatSplit {
    /// Fence to the fence side of the kerf, at the table.
    let fence: Double
    /// Wide face of each cleat (the face that goes against the wall or cabinet).
    let longFace: Double
    /// Narrow face of each cleat.
    let shortFace: Double
    /// Board width this was solved for.
    let boardWidth: Double
    /// Width of the fence side piece where it touches the table. Small values mean hands near the blade.
    let fencePieceOnTable: Double
    /// Height of the blade needed, measured straight up from the table, before tooth clearance.
    let verticalCut: Double

    /// Rip one board into two identical cleats with a single bevel cut.
    ///
    /// Width, thickness and kerf are in inches; bevel is the blade tilt in degrees from vertical.
    /// Returns nil when an input is out of range or the board is too narrow to leave material on
    /// both sides of the kerf.
    ///
    /// Why the cleats come out identical: each piece has a wide face and a narrow face r apart,
    /// and the fence is set so the two wide faces match. The narrow faces then match too, so both
    /// pieces have the same cross section. Either tilt gives the same faces; only the fence
    /// setting differs.
    static func fromBoard(width w: Double, thickness t: Double, kerf k: Double,
                          tilt: BladeTilt, bevel: Double = 45) -> CleatSplit? {
        let kh = BevelRip.horizontalKerf(k, bevel: bevel)
        let r = BevelRip.run(t, bevel: bevel)
        // Each cleat's narrow face works out to (w − r − kh) / 2 for either tilt, so it is above
        // zero only when w > r + kh.
        guard w > 0, t > 0, k >= 0, w > r + kh else { return nil }
        // At the table one piece shows its wide face and the other its narrow face, with the kerf
        // between them: wide + kh + (wide − r) = w. Solving for wide gives this.
        let longFace = (w + r - kh) / 2
        let fence: Double
        let onTable: Double
        switch tilt {
        case .awayFromFence:
            // The cut leans away from the fence, so the fence piece is a at the table and a + r on
            // top. The offcut's wide face is at the table: w − a − kh. Setting a + r equal to it
            // gives a = (w − r − kh) / 2.
            fence = (w - r - kh) / 2
            onTable = fence
        case .towardFence:
            // The cut leans over the fence piece, so it is a at the table and a − r on top. The
            // offcut's wide face is on top: w − a − kh + r. Setting a equal to it gives
            // a = (w + r − kh) / 2.
            fence = (w + r - kh) / 2
            onTable = fence
        }
        return CleatSplit(fence: fence, longFace: longFace, shortFace: longFace - r,
                          boardWidth: w, fencePieceOnTable: onTable, verticalCut: t)
    }

    /// Board width needed for a target cleat width (wide face).
    ///
    /// Inverts longFace = (w + r − kh) / 2 to get w = 2 · longFace − r + kh, then solves that
    /// board with fromBoard. Returns nil unless the wide face is wider than r, which is the same
    /// as the narrow face being above zero.
    static func fromCleat(longFace lw: Double, thickness t: Double, kerf k: Double,
                          tilt: BladeTilt, bevel: Double = 45) -> CleatSplit? {
        let kh = BevelRip.horizontalKerf(k, bevel: bevel)
        let r = BevelRip.run(t, bevel: bevel)
        guard lw > r, t > 0, k >= 0 else { return nil }
        return fromBoard(width: 2 * lw - r + kh, thickness: t, kerf: k, tilt: tilt, bevel: bevel)
    }

    /// After a test cut: how far to move the fence so both cleats match.
    /// Positive means move the fence away from the blade (widen the fence piece).
    ///
    /// Inputs are the measured wide faces of the two test pieces, in inches. Moving the fence by d
    /// adds d to the fence piece's wide face and takes d from the offcut's, so the difference
    /// between them changes by 2d. That is why the correction is half the measured difference.
    /// It holds for either tilt and doesn't depend on kerf or thickness, but it assumes the test
    /// piece is the same width as the real board.
    static func fenceCorrection(fencePieceLongFace: Double, offcutLongFace: Double) -> Double {
        (offcutLongFace - fencePieceLongFace) / 2
    }
}

/// The result of beveling one edge of a strip that is already ripped to cleat width. All lengths
/// are in inches. The kerf falls in the waste beyond the strip, so kerf doesn't enter the math.
struct CleatEdgeBevel {
    /// Fence to the fence side of the kerf, at the table.
    let fence: Double
    /// The full strip width, kept on one face.
    let longFace: Double
    /// Strip width minus r.
    let shortFace: Double
    /// Width of the strip where it touches the table.
    let fencePieceOnTable: Double

    /// Bevel one edge of a strip already ripped to width. The strip rides against the fence and keeps
    /// its full width on one face; the corner beyond the blade falls away as a small triangle.
    /// Returns nil unless the strip is wider than r.
    static func make(stripWidth s: Double, thickness t: Double, tilt: BladeTilt,
                     bevel: Double = 45) -> CleatEdgeBevel? {
        let r = BevelRip.run(t, bevel: bevel)
        guard s > r, t > 0 else { return nil }
        switch tilt {
        case .awayFromFence:
            // The cut leans away from the fence, so the strip is narrowest at the table. The kerf
            // meets the top far corner, leaving the full width on top: a + r = s. The waste
            // triangle comes off the bottom corner.
            return CleatEdgeBevel(fence: s - r, longFace: s, shortFace: s - r, fencePieceOnTable: s - r)
        case .towardFence:
            // The cut leans over the strip, so the face on the table is the wide one and keeps the
            // full width: a = s. The waste triangle comes off the top corner.
            return CleatEdgeBevel(fence: s, longFace: s, shortFace: s - r, fencePieceOnTable: s)
        }
    }
}

// MARK: - Board feet
//
// A board foot is 1" × 12" × 12", which is 144 cubic inches. With every dimension in inches,
// board feet = thickness × width × length / 144.

/// Board feet from dimensions in inches.
enum BoardFeet {
    /// Board feet for `quantity` pieces, each t × w × l inches.
    static func of(thickness t: Double, width w: Double, length l: Double, quantity q: Int = 1) -> Double {
        t * w * l / 144 * Double(q)
    }
}

/// One line on the Board Feet tab's lumber list. Dimensions are in inches. Codable so LumberStore
/// can save the list to UserDefaults as JSON.
struct LumberItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var thickness: Double
    var width: Double
    var length: Double
    var quantity: Int
    var pricePerBoardFoot: Double

    /// Board feet for all `quantity` pieces.
    var boardFeet: Double {
        BoardFeet.of(thickness: thickness, width: width, length: length, quantity: quantity)
    }

    /// Cost of all pieces, before any waste allowance.
    var cost: Double { boardFeet * pricePerBoardFoot }
}

/// Totals for the whole lumber list, with and without a waste allowance.
struct LumberTotals: Equatable {
    let boardFeet: Double
    let boardFeetWithWaste: Double
    let cost: Double
    let costWithWaste: Double

    /// Sums the list. The waste allowance scales board feet and cost by the same factor,
    /// 1 + wastePercent / 100. A negative waste percent counts as zero.
    static func of(_ items: [LumberItem], wastePercent: Double) -> LumberTotals {
        let bf = items.reduce(0) { $0 + $1.boardFeet }
        let cost = items.reduce(0) { $0 + $1.cost }
        let m = 1 + max(0, wastePercent) / 100
        return LumberTotals(boardFeet: bf, boardFeetWithWaste: bf * m, cost: cost, costWithWaste: cost * m)
    }
}

// MARK: - Miter and bevel angles
//
// Saw settings for frames and boxes with n equal sides. Each corner turns the outline by 360/n
// degrees and two pieces meet there, so each cut end takes 180/n degrees. How the board lies on
// the saw decides whether that angle goes into the miter, the bevel, or both.

/// Miter saw settings, in degrees.
struct SawSettings: Equatable {
    /// Miter saw table angle from the 0° (square) detent.
    let miter: Double
    /// Blade tilt from 0° (vertical).
    let bevel: Double
}

/// Miter and bevel settings for frames and boxes with n equal sides. Each returns nil for fewer
/// than 3 sides.
enum Angles {
    /// Flat frame with n sides (picture frame, octagon mirror): each end is a plain miter.
    /// The joint runs across the board's width, so all of 180/n goes into the miter.
    static func flatFrame(sides n: Int) -> SawSettings? {
        guard n >= 3 else { return nil }
        return SawSettings(miter: 180 / Double(n), bevel: 0)
    }

    /// Box with straight (vertical) sides and mitered corners, board lying flat on the saw: a plain bevel.
    /// The joint runs through the board's thickness, so all of 180/n goes into the bevel.
    static func straightBox(sides n: Int) -> SawSettings? {
        guard n >= 3 else { return nil }
        return SawSettings(miter: 0, bevel: 180 / Double(n))
    }

    /// Box or planter with n sides, each tilted outward by `tilt` degrees from vertical, board lying flat.
    /// bevel = asin(sin(180/n) · cos(tilt)), miter = atan(tan(180/n) · sin(tilt)).
    ///
    /// These blend the two cases above. At tilt 0 the sides stand straight and the formulas give
    /// bevel 180/n and miter 0, the same as straightBox. As tilt nears 90 the sides lie flat and
    /// they approach bevel 0 and miter 180/n, the same as flatFrame. For 4 sides tilted 45 degrees
    /// they give the standard table values, bevel 30 and miter 35.3. Returns nil unless tilt is at
    /// least 0 and under 90.
    static func compound(sides n: Int, tiltFromVertical tilt: Double) -> SawSettings? {
        guard n >= 3, tilt >= 0, tilt < 90 else { return nil }
        // a is the flat frame angle, 180/n, in radians.
        let a = rad(180 / Double(n))
        let t = rad(tilt)
        let bevel = deg(asin(sin(a) * cos(t)))
        let miter = deg(atan(tan(a) * sin(t)))
        return SawSettings(miter: miter, bevel: bevel)
    }

    /// Distance from the center of a regular n-gon to the middle of a side (the apothem), from
    /// the outside measurement a woodworker can take with a tape. In inches.
    ///
    /// Even n: the measurement is flat to flat, which is two apothems.
    /// Odd n: there is no opposite flat, so the measurement is flat to the opposite point. That is
    /// one apothem plus the circumradius, and the circumradius is apothem / cos(180/n), so
    /// d = a · (1 + 1 / cos(180/n)) and a = d · cos(180/n) / (1 + cos(180/n)).
    static func apothem(outside d: Double, sides n: Int) -> Double {
        let half = Double.pi / Double(n)
        if n % 2 == 0 { return d / 2 }
        return d * cos(half) / (1 + cos(half))
    }

    /// Edge length of a regular n-gon from its apothem: 2 · a · tan(180/n). For a frame or box,
    /// the outside edge (long point) uses the outside apothem, and the inside edge (short point)
    /// uses the outside apothem minus the stock width. Inputs and result are in inches.
    static func edgeLength(apothem a: Double, sides n: Int) -> Double {
        2 * a * tan(.pi / Double(n))
    }
}

// MARK: - End grain cutting board planner
//
// An end grain board takes two glue-ups, in this order:
//   1. Rip strips and glue them side by side into a first panel.
//   2. Flatten the panel. Its flattened thickness becomes the face of every slice.
//   3. Square one end of the panel, then crosscut it into slices. Each slice's crosscut width
//      becomes the board's thickness, plus the final flattening allowance.
//   4. Turn the slices end grain up and glue them side by side. Each slice is as long as the
//      first panel was wide, so the panel's width becomes the board's length, and the slices
//      stack across the board's width.
//   5. Flatten the board and trim its edges to final size.
// The planner works backward from the finished board to the strips, slices, and lumber to buy.

/// Inputs for EndGrainPlan.make. All lengths are in inches. "Length" is the finished board's
/// dimension along each slice and "width" is across the slices.
struct EndGrainInput {
    var boardLength: Double        // along each slice: strips × strip width
    var boardWidth: Double         // slices × slice face
    var boardThickness: Double     // final, after flattening
    var stripWidth: Double         // each strip's width across the first glue-up
    var panelThickness: Double     // first glue-up thickness as glued (strip height)
    var firstFlatten: Double       // removed flattening the first panel
    var finalFlatten: Double       // removed flattening the end grain board
    var edgeTrim: Double           // trimmed off the edges of each glue-up, total
    var endTrim: Double            // squaring cut on the panel end before slicing
    /// Crosscut kerf, taken once per slice.
    var kerf: Double
    /// Usable share of rough lumber after milling and defects, as a percent above 0 and up to 100.
    var yieldPercent: Double
}

/// The cut list and step sizes for an end grain board. All lengths are in inches. Board feet
/// cover the strips themselves; roughBoardFeet adds the yield allowance on top.
struct EndGrainPlan {
    /// Number of strips to rip.
    let strips: Int
    /// Each strip's width across the first panel, passed through from the input.
    let stripWidth: Double
    /// Each strip's height: the first panel's thickness as glued.
    let stripHeight: Double
    /// Target board thickness, passed through from the input.
    let finishedThickness: Double
    /// Length to cut each strip. Same as panelLength.
    let stripLength: Double
    /// Number of slices to crosscut from the first panel.
    let slices: Int
    let sliceWidth: Double         // crosscut setting for each slice
    let sliceFace: Double          // each slice's contribution to board width
    /// First panel width as glued: strips × stripWidth.
    let panelWidth: Double
    /// First panel length: the squaring cut plus each slice and its kerf.
    let panelLength: Double
    /// Final glue-up before flattening and trimming. Length equals panelWidth; width is
    /// slices × sliceFace.
    let asGluedLength: Double
    let asGluedWidth: Double
    /// Size after edge trim. Can come out larger than the target because counts round up.
    let finishedLength: Double
    let finishedWidth: Double
    /// Board feet of strip stock: panel thickness × panel width × panel length.
    let netBoardFeet: Double
    /// Rough lumber to buy: netBoardFeet divided by the yield.
    let roughBoardFeet: Double

    /// Plans the board. Returns nil if a finished dimension or the strip width isn't above zero,
    /// the panel isn't thicker than the first flattening allowance, an allowance or the kerf is
    /// negative, or the yield is outside 0 (exclusive) to 100.
    static func make(_ i: EndGrainInput) -> EndGrainPlan? {
        guard i.boardLength > 0, i.boardWidth > 0, i.boardThickness > 0,
              i.stripWidth > 0, i.panelThickness > i.firstFlatten,
              i.firstFlatten >= 0, i.finalFlatten >= 0, i.edgeTrim >= 0, i.endTrim >= 0,
              i.kerf >= 0, i.yieldPercent > 0, i.yieldPercent <= 100 else { return nil }

        // Step 1, strips: the first panel's width becomes the board's length, so use enough strips
        // to cover the finished length plus edge trim. Subtracting 1e-9 before ceil keeps an exact
        // fit from adding a strip when floating point rounding lands the quotient a hair above a
        // whole number.
        let strips = Int(ceil((i.boardLength + i.edgeTrim) / i.stripWidth - 1e-9))
        // Step 2, first panel: after flattening, its thickness is each slice's face.
        let sliceFace = i.panelThickness - i.firstFlatten
        // Step 3, slices: enough to cover the finished width plus edge trim, rounded the same way.
        let slices = Int(ceil((i.boardWidth + i.edgeTrim) / sliceFace - 1e-9))
        // Cut each slice thick enough to flatten down to the finished thickness.
        let sliceWidth = i.boardThickness + i.finalFlatten
        // The squaring cut, then one kerf per slice. No kerf is added for the squaring cut itself,
        // so endTrim has to cover it.
        let panelLength = i.endTrim + Double(slices) * (sliceWidth + i.kerf)
        let panelWidth = Double(strips) * i.stripWidth
        // Step 4, final glue-up: the slices stack across the board's width.
        let asGluedWidth = Double(slices) * sliceFace
        let net = BoardFeet.of(thickness: i.panelThickness, width: panelWidth, length: panelLength)
        return EndGrainPlan(
            strips: strips,
            stripWidth: i.stripWidth,
            stripHeight: i.panelThickness,
            finishedThickness: i.boardThickness,
            stripLength: panelLength,
            slices: slices,
            sliceWidth: sliceWidth,
            sliceFace: sliceFace,
            panelWidth: panelWidth,
            panelLength: panelLength,
            // Turning the slices end grain up makes the first panel's width the board's length.
            asGluedLength: panelWidth,
            asGluedWidth: asGluedWidth,
            // Step 5: edge trim comes off once in each direction.
            finishedLength: panelWidth - i.edgeTrim,
            finishedWidth: asGluedWidth - i.edgeTrim,
            netBoardFeet: net,
            // Dividing by the usable share turns strip stock into rough stock to buy.
            roughBoardFeet: net / (i.yieldPercent / 100)
        )
    }
}
