// Components.swift
//
// Building blocks shared by every tab: the settings keys, kerf parsing, the entry rows
// (MeasureField and NumberField, both laid out by FieldRow), the result views (BigResult,
// ResultRow, Callout), the Settings sheet, and the toolbar modifier that adds the in/mm toggle and
// the settings gear. The screens in Views/ are built from these so every tab looks and behaves
// the same.
//
// Length entries are stored as the text the user typed, in the current unit system, and turned
// into inches with UnitSystem.inches (Core/Units.swift) whenever a value is needed.

import SwiftUI
import UIKit

// MARK: - Shared settings

/// UserDefaults keys for settings that more than one screen reads. The kerf key comes from
/// LengthField, so switching units converts the stored kerf along with every other length entry.
enum Keys {
    static let kerf = LengthField.kerf.key
    /// Fraction denominator for imperial results: 8, 16, 32, or 64.
    static let precision = "settings_precision"
    static let tilt = "settings_tilt"
    static let units = UnitSwitcher.unitKey
}

/// Parses a stored kerf entry to inches, falling back to 1/8" if it can't be used.
/// Usable means it parses in the current unit system and is at least 0 and under 1".
func kerfValue(_ text: String, unit: UnitSystem) -> Double {
    if let v = unit.inches(text), v >= 0, v < 1 { return v }
    return 0.125
}

/// Shown under a kerf field when the entry can't be used.
/// It uses the same test as kerfValue, so it appears exactly when the 1/8" fallback is in effect,
/// and draws nothing otherwise.
struct KerfWarning: View {
    let text: String
    @AppStorage(Keys.units) private var unit: UnitSystem = .imperial

    var body: some View {
        if let v = unit.inches(text), v >= 0, v < 1 {
            EmptyView()
        } else {
            Callout(kind: .warning, text: unit == .imperial
                    ? "Kerf must be under 1\". Using 1/8\" until it's fixed."
                    : "Kerf must be under 25.4 mm. Using 3.2 mm until it's fixed.")
        }
    }
}

// MARK: - Input

/// A length field that accepts fractions, feet and inches, metric units, and simple math.
/// It binds to the raw text; callers parse it with unit.inches(text). Under the field it shows how
/// the entry was read, in both units, so the user can catch a misread before using the result.
struct MeasureField: View {
    let label: String
    @Binding var text: String
    var caption: String? = nil
    @AppStorage(Keys.units) private var unit: UnitSystem = .imperial

    /// A read-back of the entry in both units, a gray prompt when empty, or a red error.
    /// The Bool is true for the error.
    private var status: (String, Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return ("Enter a value", false) }
        guard let v = unit.inches(trimmed) else { return ("Can't read that", true) }
        switch unit {
        case .imperial:
            return (Format.decimal(v, places: 4) + "\" · " + Format.mm(v), false)
        case .metric:
            return (Format.mmNumber(v, places: 2) + " mm · " + Format.inches(v, denominator: 32), false)
        }
    }

    var body: some View {
        FieldRow(label: label, caption: caption, status: status.0, statusIsError: status.1,
                 suffix: unit == .metric ? "mm" : "") {
            // Entries mix digits with / ' " ( ) and unit words like mm or ft, so use the
            // punctuation keyboard and keep autocorrect and capitalization from changing them.
            TextField("0", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.body.monospacedDigit())
        }
    }
}

/// A plain number field (degrees, percent, dollars).
/// Callers parse the text with number(_:). There is no unit conversion and no math.
struct NumberField: View {
    let label: String
    @Binding var text: String
    var prefix: String = ""
    var suffix: String = ""
    var caption: String? = nil

    /// A gray prompt when empty, a red error when the text isn't a number, and nil (no note)
    /// when it is valid. The prefix or suffix already says what the number means.
    private var status: (String, Bool)? {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return ("Enter a number", false) }
        return number(text) == nil ? ("Enter a number", true) : nil
    }

    var body: some View {
        FieldRow(label: label, caption: caption, status: status?.0, statusIsError: status?.1 ?? false,
                 prefix: prefix, suffix: suffix) {
            TextField("0", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
        }
    }
}

/// Shared layout for entry rows (MeasureField, NumberField).
///
/// The label and a filled entry box share the top line. The caption and the read-back sit on
/// their own line below at full width, caption on the left and read-back on the right. Captions
/// used to sit beside the field, where they were truncated on narrow screens; below the row they
/// get the whole width and can wrap.
///
/// Tapping the label, the gap, or the caption starts editing; the entry box keeps its own
/// text gestures (caret placement, double tap selection, the loupe) untouched. At accessibility
/// text sizes the entry box drops below its label so long values never clip.
struct FieldRow<Field: View>: View {
    let label: String
    let caption: String?
    /// Read-back or error text shown under the entry box. nil hides it.
    let status: String?
    /// Shows `status` in red instead of gray.
    let statusIsError: Bool
    /// Text beside the entry box, such as "$" before it or "%", "°", or "mm" after it.
    var prefix: String = ""
    let suffix: String
    @ViewBuilder let field: () -> Field

    /// Bound to the text field so taps elsewhere in the row can focus it.
    @FocusState private var focused: Bool
    /// Narrowest the entry box gets. Scales with Dynamic Type so a larger font still fits a value.
    @ScaledMetric(relativeTo: .body) private var minFieldWidth: CGFloat = 90
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes the label and box don't fit side by side, so stack them.
        // AnyLayout swaps the container without changing the children's identity, so the text
        // field keeps its focus and state when the text size changes.
        let stacked = typeSize.isAccessibilitySize
        let top = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))

        VStack(alignment: .leading, spacing: 4) {
            top {
                // The tap to focus gestures sit on the label, the spacer, and the notes, never on
                // the text field or a parent of it. A parent tap gesture competes with the field's
                // own gestures and can break caret dragging and double tap selection.
                // contentShape makes each whole frame tappable, including the spacer's empty area.
                // The label's layout priority makes the entry box give up width first, down to
                // minFieldWidth, before the label truncates.
                Text(label)
                    .layoutPriority(1)
                    .contentShape(Rectangle())
                    .onTapGesture { focused = true }
                // In the stacked layout a Spacer would only add vertical space, so leave it out.
                if !stacked {
                    Spacer(minLength: 8)
                        .contentShape(Rectangle())
                        .onTapGesture { focused = true }
                }
                entry
            }
            notes
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
        }
        .padding(.vertical, 2)
    }

    /// The entry box: optional prefix, the field on a filled rounded rectangle, optional suffix.
    private var entry: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if !prefix.isEmpty {
                Text(prefix).foregroundStyle(.secondary)
            }
            // The visible label and caption are separate views, so pass them to VoiceOver here.
            // A TextField takes all the width it's offered; maxWidth keeps it a compact box.
            field()
                .focused($focused)
                .accessibilityLabel(label)
                .accessibilityHint(caption ?? "")
                .frame(minWidth: minFieldWidth, maxWidth: 180)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 7))
            if !suffix.isEmpty {
                Text(suffix).foregroundStyle(.secondary)
            }
        }
    }

    /// Caption and read-back on one line when they fit, otherwise caption first (wrapping)
    /// and the read-back on its own line at the right.
    ///
    /// ViewThatFits measures each option at its ideal width and uses the first that fits. The
    /// one line option's ideal width includes the whole caption, so it is chosen only when the
    /// caption fits without truncating; otherwise the wrapping option takes over.
    @ViewBuilder private var notes: some View {
        if caption != nil || status != nil {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    captionText(wrapping: false)
                    Spacer(minLength: 12)
                    statusText
                }
                VStack(alignment: .leading, spacing: 3) {
                    captionText(wrapping: true)
                    statusText
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    /// The caption, kept to one line for the side by side option or allowed to wrap. When
    /// wrapping, fixedSize lets it grow as tall as it needs inside a List row.
    @ViewBuilder private func captionText(wrapping: Bool) -> some View {
        if let caption {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(wrapping ? nil : 1)
                .fixedSize(horizontal: false, vertical: wrapping)
        }
    }

    /// The read-back or error, right aligned, wrapping rather than truncating.
    @ViewBuilder private var statusText: some View {
        if let status {
            Text(status)
                .font(.caption.monospacedDigit())
                .foregroundStyle(statusIsError ? Color.red : Color.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Parses a plain number entry (NumberField): no units and no math. See
/// MeasureParser.plainNumber for the comma rules and what it rejects.
func number(_ text: String) -> Double? {
    MeasureParser.plainNumber(text)
}

// MARK: - Output

/// The headline number on each screen, sized to read from across the bench.
/// A long value shrinks to as little as half size to stay on one line. VoiceOver reads the title,
/// value, and detail as one element.
struct BigResult: View {
    let title: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.accentColor)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A secondary result: label on the left, value on the right in monospaced digits.
struct ResultRow: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .font(.body.monospacedDigit().weight(.medium))
                .foregroundStyle(.primary)
        }
    }
}

/// An inline note with an icon: `.info` for tips and fence moves, `.warning` for bad inputs and
/// safety notes.
struct Callout: View {
    enum Kind { case info, warning }
    let kind: Kind
    let text: String

    var body: some View {
        Label {
            Text(text).font(.footnote)
        } icon: {
            Image(systemName: kind == .warning ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(kind == .warning ? Color.orange : Color.accentColor)
        }
    }
}

// MARK: - Settings

/// The sheet behind the gear button: units and fraction precision, blade kerf and tilt, and help
/// for typing measurements. Every value lives in @AppStorage, so the tabs pick up changes at once.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Keys.kerf) private var kerf = LengthField.kerf.imperialDefault
    @AppStorage(Keys.precision) private var precision = 32
    @AppStorage(Keys.tilt) private var tilt: BladeTilt = .awayFromFence
    @AppStorage(Keys.units) private var unit: UnitSystem = .imperial

    /// Routes the Units picker through UnitSwitcher so a switch also converts every stored length
    /// entry. Writing the unit key directly would leave "5 1/2" to be read as 5.5 mm.
    private var unitBinding: Binding<UnitSystem> {
        Binding(get: { unit }, set: { UnitSwitcher.switchTo($0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Units", selection: unitBinding) {
                        ForEach(UnitSystem.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    // Metric results always show to 0.1 mm, so precision only matters for fractions.
                    if unit == .imperial {
                        PrecisionPicker(precision: $precision)
                    }
                } header: {
                    Text("Units")
                } footer: {
                    Text(unit == .imperial
                         ? "Fractions round to the size above. Switching units converts everything you've entered."
                         : "Results show to 0.1 mm. Switching units converts everything you've entered.")
                }

                Section {
                    MeasureField(label: "Blade kerf", text: $kerf,
                                 caption: unit == .imperial
                                    ? "Full kerf is about 1/8, thin kerf about 3/32. Use your blade's spec."
                                    : "Full kerf is about 3.2, thin kerf about 2.4. Use your blade's spec.")
                    KerfWarning(text: kerf)
                    Picker("Blade tilts", selection: $tilt) {
                        ForEach(BladeTilt.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Table saw")
                } footer: {
                    Text("Most jobsite saws, Skil included, tilt left. With the fence right of the blade that is away from the fence.")
                }

                Section {
                    Text(unit == .imperial
                         ? "Length fields take 1.75, 1 3/4, 1-3/4, 7' 4 1/2\", 7'-4\", 19 mm, and math like (3 + 1/2) × 2. Put spaces around a minus to subtract."
                         : "Length fields are in mm and take 139.7, 14 cm, 2.4 m, 5 1/2\", 8', and math like (450 + 18) × 2. Put spaces around a minus to subtract.")
                        .font(.footnote)
                } header: {
                    Text("Entering measurements")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Picks the fraction denominator that imperial results round to. The tags are the denominators.
/// Used in Settings and on the Fractions tab.
struct PrecisionPicker: View {
    @Binding var precision: Int

    var body: some View {
        Picker("Precision", selection: $precision) {
            Text("1/8").tag(8)
            Text("1/16").tag(16)
            Text("1/32").tag(32)
            Text("1/64").tag(64)
        }
        .pickerStyle(.segmented)
    }
}

/// Adds the in/mm toggle and the settings gear to a screen's toolbar.
/// Apply it with .settingsButton().
struct SettingsButton: ViewModifier {
    /// The Fractions tab passes false. Its calculator has no units, so the toggle would change
    /// nothing on that screen while it converted the stored entries on the other tabs.
    var showsUnits = true
    @State private var showing = false
    /// Drives the toggle's label. The tap handler reads the stored value instead (see unitButton).
    @AppStorage(Keys.units) private var unit: UnitSystem = .imperial

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if showsUnits {
                        unitButton
                    }

                    Button {
                        showing = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showing) {
                SettingsView()
            }
    }

    private var unitButton: some View {
        Button {
            // Read the unit from UserDefaults, not this view's @AppStorage copy. switchTo converts
            // from the stored unit and does nothing when the target matches it. The copy can lag a
            // view update behind the store, and if it were stale its `other` would equal the stored
            // unit, so the tap would do nothing.
            UnitSwitcher.switchTo(UnitSwitcher.current().other)
        } label: {
            Text(unit.symbol)
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1.5))
        }
        .accessibilityLabel("Units: \(unit.name). Switch to \(unit.other.name).")
    }
}

extension View {
    /// Adds the settings gear, and the in/mm toggle unless `showsUnits` is false.
    func settingsButton(showsUnits: Bool = true) -> some View {
        modifier(SettingsButton(showsUnits: showsUnits))
    }
}
