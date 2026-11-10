// Units.swift
// Shop Math
//
// Imperial and metric support. The app does all of its math in inches; the unit system only
// changes how length entries are read and how results are shown. This file has three parts:
// UnitSystem, which reads entries and formats results for the current setting; the metric
// formatters added to Format; and the stored entry registry (LengthField) with UnitSwitcher,
// which rewrites saved entries when the setting changes and migrates keys saved by version 1.0.
//
// It builds on MeasureParser and Format in Measure.swift. Views read the setting with
// @AppStorage(Keys.units) (Keys is in Components.swift), store their length entries under
// LengthField keys, and parse and format through UnitSystem. The in/mm toolbar button and the
// Settings picker in Components.swift call UnitSwitcher.switchTo. ShopMathApp calls
// UnitSwitcher.prepare at launch.

import Foundation

// MARK: - Unit system
//
// All math runs in inches. The unit system only decides how entries are read and how results
// are shown. Metric entries are read as millimeters. Headline results show to 0.1 mm and the
// detail line under them to 0.01 mm.

/// The user's choice of units for entering and showing lengths. Stored as its raw value under
/// UnitSwitcher.unitKey. Change it only through UnitSwitcher.switchTo so saved entries are
/// converted along with it.
enum UnitSystem: String, CaseIterable, Identifiable, Codable {
    case imperial
    case metric

    var id: String { rawValue }

    /// Short label for the toolbar button.
    var symbol: String { self == .imperial ? "in" : "mm" }

    /// Full name for the Settings picker and accessibility labels.
    var name: String { self == .imperial ? "Inches" : "Millimeters" }

    var other: UnitSystem { self == .imperial ? .metric : .imperial }

    /// The unit a bare number is read in: inches in imperial, millimeters in metric.
    private var parseUnit: MeasureParser.Unit { self == .imperial ? .inch : .millimeter }

    /// Reads a length entry typed in this unit system and returns inches, or nil if the entry
    /// is empty or can't be read. Only bare numbers depend on the system; suffixed values such
    /// as 5 1/2" or 19 mm mean the same length in both.
    func inches(_ text: String) -> Double? {
        guard let v = MeasureParser.value(text, unit: parseUnit) else { return nil }
        return self == .imperial ? v : v / 25.4
    }

    /// A result for display: 2 9/32" or 57.9 mm. `precision` is the fraction denominator from
    /// the precision setting and only applies in imperial; metric always shows 0.1 mm.
    func length(_ inches: Double, precision: Int) -> String {
        switch self {
        case .imperial: return Format.inches(inches, denominator: precision)
        case .metric: return Format.mm(inches)
        }
    }

    /// A length list like 3/4 × 5 1/2 × 96" or 19.1 × 139.7 × 2438.4 mm, with one unit mark at
    /// the end. `precision` applies in imperial only, as in `length`.
    func dimensions(_ values: [Double], precision: Int) -> String {
        switch self {
        case .imperial:
            return values.map { Format.fraction($0, denominator: precision) }.joined(separator: " × ") + "\""
        case .metric:
            return values.map { Format.mmNumber($0) }.joined(separator: " × ") + " mm"
        }
    }

    /// Second line under a headline result. Imperial: the decimal inches, the mm equivalent,
    /// and a rounding note when the fraction isn't exact. Metric: mm to 0.01 and the inch
    /// equivalent to 1/32. Metric ignores `precision` because SettingsView only offers the
    /// precision setting in imperial.
    func detail(_ inches: Double, precision: Int) -> String {
        switch self {
        case .imperial:
            var s = Format.decimal(inches, places: 3) + "\" · " + Format.mm(inches)
            if let note = Format.roundingNote(inches, denominator: precision) { s += " · " + note }
            return s
        case .metric:
            return Format.mmNumber(inches, places: 2) + " mm · " + Format.inches(inches, denominator: 32)
        }
    }

    /// Text for an input field that reads back as the same length in this unit system. See
    /// Format.inchEntry and Format.mmEntry for how much precision each keeps.
    func entryText(_ inches: Double) -> String {
        switch self {
        case .imperial: return Format.inchEntry(inches)
        case .metric: return Format.mmEntry(inches)
        }
    }

    /// Rewrites an entry typed in this unit system as the same length in `target`.
    /// Text that is empty or can't be read is left as it is. An expression is replaced by its
    /// value: "(3 + 1/2) × 2" in imperial becomes "177.8" in metric.
    func convert(_ text: String, to target: UnitSystem) -> String {
        if target == self { return text }
        guard let v = inches(text) else { return text }
        return target.entryText(v)
    }
}

// MARK: - Metric formatting

// Metric formatters and the entry text writers used when converting saved entries. Like the
// rest of Format, they all take inches.
extension Format {
    /// Exact by definition.
    static let mmPerInch = 25.4
    /// A board foot is 144 cubic inches (12" × 12" × 1"), and an inch is 0.0254 m.
    static let cubicMetersPerBoardFoot: Double = 144 * 0.0254 * 0.0254 * 0.0254

    /// Inches as millimeters, a bare number rounded to `places` with trailing zeros trimmed:
    /// 139.7, 140, or 3.18 with places: 2.
    static func mmNumber(_ inches: Double, places: Int = 1) -> String {
        trimmed(inches * mmPerInch, places: places)
    }

    /// Inches as millimeters to 0.1 mm with the unit: 57.9 mm.
    static func mm(_ inches: Double) -> String {
        mmNumber(inches) + " mm"
    }

    /// Board feet as cubic meters to 4 places: 0.0094 m³.
    static func cubicMeters(boardFeet: Double) -> String {
        String(format: "%.4f m³", boardFeet * cubicMetersPerBoardFoot)
    }

    /// Entry text in mm, kept to 0.001 mm so a converted fraction converts back exactly
    /// (see inchEntry for why 0.001 mm is enough).
    static func mmEntry(_ inches: Double) -> String {
        trimmed(inches * mmPerInch, places: 3)
    }

    /// Entry text in inches that MeasureParser reads back as the same value. Used when
    /// converting saved entries to imperial and by the Fractions calculator's = key.
    ///
    /// A value within 0.002/64" (about 0.00003") of a multiple of 1/64" becomes a reduced
    /// fraction like "5 1/2". Anything else becomes a decimal to 6 places, fine enough that
    /// converting it back to metric gives the same 0.001 mm entry.
    static func inchEntry(_ inches: Double) -> String {
        guard inches.isFinite else { return "0" }
        // The tolerance absorbs a trip through mm. mmEntry rounds to 0.001 mm, which moves a
        // value at most 0.0005 mm, about 0.0013 of a 64th, so it is still inside 0.002 here.
        // For example 1/64" becomes "0.397" mm, which reads back as 0.0156299", and the snap
        // turns that into "1/64" again instead of "0.01563". The tolerance is small enough
        // that real decimals such as 0.748031 (19 mm) are not pulled to a fraction. The size
        // limit keeps the value in range for the Int math in fraction().
        let sixtyFourths = inches * 64
        if abs(inches) < 1e9, abs(sixtyFourths - sixtyFourths.rounded()) < 0.002 {
            return fraction(inches, denominator: 64)
        }
        return trimmed(inches, places: 6)
    }

    /// Rounds `x` to `places` decimals, half away from zero (19.05 → 19.1), then trims trailing
    /// zeros and a trailing decimal point. A value that rounds to zero prints as "0", not "-0".
    /// Very large values print as whole numbers and values that aren't finite print as "0".
    static func trimmed(_ x: Double, places: Int) -> String {
        guard x.isFinite, abs(x) < 1e12 else { return x.isFinite ? String(format: "%.0f", x) : "0" }
        var scale = 1.0
        for _ in 0..<max(0, places) { scale *= 10 }
        // Round the magnitude by adding a half and flooring. The extra 1e-7 (in units of the
        // last place kept) covers binary error: 3/4" × 25.4 comes out as 19.049999999999997,
        // which %.1f alone would print as 19.0. The nudge makes it 19.1.
        let magnitude = (abs(x) * scale + 0.5 + 1e-7).rounded(.down) / scale
        var s = String(format: "%.\(places)f", x < 0 ? -magnitude : magnitude)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        if s == "-0" { s = "0" }
        return s
    }
}

// MARK: - Stored entries

/// Every length entry the app remembers, with its default in inches. The raw value is the
/// UserDefaults key the screen's @AppStorage uses. Keys use underscores, never dots (see
/// UnitSwitcher.legacyKeys).
///
/// UnitSwitcher converts every case here when the units change, so a new length field must be
/// added here. Otherwise it keeps its old text after a switch and is read in the wrong unit.
/// Entries that aren't lengths, such as prices, quantities, percentages and angles, use their
/// own keys and are never converted.
///
/// The Fractions calculator's expression ("calc_expression") is deliberately not a case. The
/// calculator has no units and always parses in inches, so converting its text to mm would
/// change its value.
enum LengthField: String, CaseIterable {
    case kerf = "settings_kerf"
    case cleatBoard = "cleat_board"
    case cleatTarget = "cleat_target"
    case cleatStrip = "cleat_strip"
    case cleatThickness = "cleat_thickness"
    case cleatTestFence = "cleat_testFence"
    case cleatTestOffcut = "cleat_testOffcut"
    case bfThickness = "bf_thickness"
    case bfWidth = "bf_width"
    case bfLength = "bf_length"
    case anglesAcross = "angles_across"
    case anglesStock = "angles_stock"
    case egLength = "eg_length"
    case egWidth = "eg_width"
    case egThickness = "eg_thickness"
    case egStripWidth = "eg_stripWidth"
    case egPanel = "eg_panel"
    case egFlatten1 = "eg_flatten1"
    case egFlatten2 = "eg_flatten2"
    case egEdgeTrim = "eg_edgeTrim"
    case egEndTrim = "eg_endTrim"

    var key: String { rawValue }

    /// The starting value, written in imperial entry syntax. Views pass it as their
    /// @AppStorage default, but UnitSwitcher.ensureStored saves a converted copy at launch, so
    /// in metric the view reads the saved mm text instead. An empty string means the field
    /// starts blank.
    var imperialDefault: String {
        switch self {
        case .kerf: return "1/8"
        case .cleatBoard: return "5 1/2"
        case .cleatTarget: return "3"
        case .cleatStrip: return "3"
        case .cleatThickness: return "3/4"
        case .cleatTestFence, .cleatTestOffcut, .anglesAcross, .anglesStock: return ""
        case .bfThickness: return "1"
        case .bfWidth: return "6"
        case .bfLength: return "96"
        case .egLength: return "16"
        case .egWidth: return "12"
        case .egThickness: return "1 1/2"
        case .egStripWidth: return "1 1/2"
        case .egPanel: return "1 3/4"
        case .egFlatten1, .egFlatten2: return "1/8"
        case .egEdgeTrim, .egEndTrim: return "1/2"
        }
    }
}

/// Owns the unit setting and keeps saved entries consistent with it. Change units through
/// switchTo, never by writing the setting directly, or saved entries would be read in the
/// wrong unit.
enum UnitSwitcher {
    /// UserDefaults key for the UnitSystem raw value. Keys.units in Components.swift points here.
    static let unitKey = "settings_units"

    /// Keys from version 1.0, which used dots. iOS doesn't reliably report UserDefaults changes
    /// for keys with dots to @AppStorage (the observation treats a dot as a key path separator),
    /// so a view could keep showing old text after switchTo rewrote it. The keys were renamed
    /// with underscores, and migrateLegacyKeys carries saved values across. Every key the app
    /// stores now avoids dots for the same reason.
    static let legacyKeys = [
        "angles.across", "angles.kind", "angles.sides", "angles.stock", "angles.tilt", "app.tab",
        "bf.length", "bf.price", "bf.quantity", "bf.thickness", "bf.waste", "bf.width",
        "calc.expression", "cleat.board", "cleat.method", "cleat.solveFrom", "cleat.strip",
        "cleat.target", "cleat.thickness", "eg.edgeTrim", "eg.endTrim", "eg.flatten1",
        "eg.flatten2", "eg.length", "eg.panel", "eg.stripWidth", "eg.thickness", "eg.width",
        "eg.yield", "settings.kerf", "settings.precision", "settings.tilt"
    ]

    /// Copies each 1.0 value to its new key (unless the new key already has one) and removes the old key.
    /// Runs on every launch and does nothing once the old keys are gone.
    static func migrateLegacyKeys(_ d: UserDefaults = .standard) {
        for old in legacyKeys {
            guard let value = d.object(forKey: old) else { continue }
            let new = old.replacingOccurrences(of: ".", with: "_")
            if d.object(forKey: new) == nil { d.set(value, forKey: new) }
            d.removeObject(forKey: old)
        }
    }

    /// Run once at launch, before any screen reads its entries.
    static func prepare(_ d: UserDefaults = .standard) {
        // Order matters. ensureStored fills every missing key with a default, and
        // migrateLegacyKeys never overwrites a key that has a value, so running ensureStored
        // first would replace a 1.0 user's saved entries with defaults.
        migrateLegacyKeys(d)
        ensureStored(d)
    }

    /// The saved unit system, or imperial when nothing valid is saved. That matches the
    /// .imperial default the views give @AppStorage(Keys.units).
    static func current(_ d: UserDefaults = .standard) -> UnitSystem {
        UnitSystem(rawValue: d.string(forKey: unitKey) ?? "") ?? .imperial
    }

    /// Writes the default for any entry that has never been saved, converted to the current
    /// unit system.
    ///
    /// When a key is missing, the view falls back to `imperialDefault` and parses it in
    /// whatever the unit setting is. In metric an unsaved "5 1/2" would be read as 5.5 mm.
    /// With every key written, that fallback is never used, and switchTo has a saved value
    /// to convert for every field.
    static func ensureStored(_ d: UserDefaults = .standard) {
        let unit = current(d)
        for field in LengthField.allCases where d.string(forKey: field.key) == nil {
            d.set(UnitSystem.imperial.convert(field.imperialDefault, to: unit), forKey: field.key)
        }
    }

    /// Converts every stored entry to `target` and makes it the current unit system.
    static func switchTo(_ target: UnitSystem, _ d: UserDefaults = .standard) {
        let from = current(d)
        guard from != target else { return }
        // Save any missing defaults in the old units first so they are converted with the rest.
        ensureStored(d)
        for field in LengthField.allCases {
            if let text = d.string(forKey: field.key) {
                d.set(from.convert(text, to: target), forKey: field.key)
            }
        }
        d.set(target.rawValue, forKey: unitKey)
    }
}
