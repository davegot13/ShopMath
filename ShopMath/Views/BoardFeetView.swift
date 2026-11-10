// BoardFeetView.swift
//
// Board Feet tab. Works out board feet and cost for a board, or several of the same size, and
// keeps a lumber list with totals, a waste allowance, and cost with waste.
//
// How it's built: thickness, width and length are stored in @AppStorage as text under
// LengthField keys and parsed through the current UnitSystem into inches. Quantity, price per
// board foot and waste percent are stored under plain keys. The math is BoardFeet, LumberItem
// and LumberTotals from Core/ShopMath.swift. The list lives in LumberStore, which saves it to
// UserDefaults as JSON; ShopMathApp creates the store and passes it in as an environment object.

import SwiftUI

// MARK: - Lumber store

/// The saved lumber list. Items hold their sizes in inches, so the list displays correctly in
/// either unit system and never needs converting when the units change.
@MainActor
final class LumberStore: ObservableObject {
    // The dot in this key is harmless. Dotted keys are a problem only for values observed for
    // changes (see UnitSwitcher.legacyKeys), and this one is read once in init and written in save().
    private static let key = "lumber.items"

    /// Every change, including swipe to delete and Clear list, rewrites the whole list.
    @Published var items: [LumberItem] = [] {
        didSet { save() }
    }

    /// Loads the saved list. Missing or undecodable data leaves the list empty, and the next
    /// change overwrites it. Keep LumberItem's Codable shape backward compatible, or saved
    /// lists will be lost.
    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([LumberItem].self, from: data) {
            items = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Board Feet screen

/// The Board Feet tab: one board's board feet and cost, plus the saved lumber list.
struct BoardFeetView: View {
    // MARK: - Stored entries

    @EnvironmentObject private var store: LumberStore
    @AppStorage(Keys.units) private var unit: UnitSystem = .imperial
    // Board size, stored as the text typed in the current unit system. LengthField keys let the
    // in/mm toggle convert these entries; the imperial defaults are only fallbacks, because
    // UnitSwitcher.prepare stores every LengthField in the current units at launch.
    @AppStorage(LengthField.bfThickness.key) private var thicknessText = LengthField.bfThickness.imperialDefault
    @AppStorage(LengthField.bfWidth.key) private var widthText = LengthField.bfWidth.imperialDefault
    @AppStorage(LengthField.bfLength.key) private var lengthText = LengthField.bfLength.imperialDefault
    // A count, a price per board foot and a percent. None of them is a length, so they use plain
    // keys and the unit switch leaves them alone.
    @AppStorage("bf_quantity") private var quantity = 1
    @AppStorage("bf_price") private var priceText = "0"
    @AppStorage("bf_waste") private var wasteText = "20"
    // The name only matters until the board is added, so it isn't stored.
    @State private var name = ""
    @State private var confirmClear = false

    // MARK: - Parsed inputs

    /// Board size in inches.
    private struct Dims {
        let t: Double
        let w: Double
        let l: Double
    }

    /// Nil until all three sizes read as positive lengths, which hides the result section.
    private var dims: Dims? {
        guard let t = unit.inches(thicknessText), t > 0,
              let w = unit.inches(widthText), w > 0,
              let l = unit.inches(lengthText), l > 0 else { return nil }
        return Dims(t: t, w: w, l: l)
    }

    /// Price per board foot. Blank, unreadable or negative entries count as zero, which hides the
    /// cost rows.
    private var price: Double { max(0, number(priceText) ?? 0) }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MeasureField(label: "Thickness", text: $thicknessText)
                    MeasureField(label: "Width", text: $widthText)
                    MeasureField(label: "Length", text: $lengthText,
                                 caption: unit == .imperial ? "Inches, or feet like 8'" : "mm, or meters like 2.4 m")
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                    NumberField(label: "Price per board foot", text: $priceText, prefix: "$")
                } header: {
                    Text(unit == .imperial ? "Board, actual size in inches" : "Board, actual size in mm")
                }

                if let d = dims {
                    // Board feet for all pieces together. Metric entries are already inches here,
                    // so the same ÷ 144 formula applies.
                    let bf = BoardFeet.of(thickness: d.t, width: d.w, length: d.l, quantity: quantity)
                    Section {
                        BigResult(title: "Board feet",
                                  value: Format.decimal(bf, places: 2),
                                  detail: resultDetail(bf))
                        if price > 0 {
                            ResultRow(label: "Cost", value: Format.money(bf * price))
                        }
                        TextField("Name (optional), e.g. Maple", text: $name)
                        // The item keeps the parsed inches, not the typed text, so it stays
                        // correct after a unit switch.
                        Button {
                            store.items.append(LumberItem(
                                name: name.trimmingCharacters(in: .whitespaces),
                                thickness: d.t, width: d.w, length: d.l,
                                quantity: quantity, pricePerBoardFoot: price))
                            name = ""
                        } label: {
                            Label("Add to lumber list", systemImage: "plus.circle.fill")
                        }
                    } footer: {
                        Text(unit == .imperial
                             ? "Thickness × width × length in inches ÷ 144."
                             : "Sizes convert to inches, then thickness × width × length ÷ 144. One board foot is 0.00236 m³.")
                    }
                }

                listSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Board Feet")
            .settingsButton()
            .confirmationDialog("Clear the lumber list?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear list", role: .destructive) { store.items.removeAll() }
            }
        }
    }

    // MARK: - Lumber list

    /// Saved boards with totals. Hidden while the list is empty.
    @ViewBuilder private var listSection: some View {
        if !store.items.isEmpty {
            Section {
                ForEach(store.items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(item.name.isEmpty ? "Board" : item.name).font(.headline)
                            Spacer()
                            Text("\(Format.decimal(item.boardFeet, places: 2)) bf")
                                .font(.body.monospacedDigit())
                        }
                        HStack {
                            Text(describe(item))
                            Spacer()
                            if item.pricePerBoardFoot > 0 {
                                Text(Format.money(item.cost))
                            }
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
                .onDelete { store.items.remove(atOffsets: $0) }

                // Waste applies to the totals only. An unreadable entry counts as 0%, and
                // LumberTotals ignores negative values.
                NumberField(label: "Waste allowance", text: $wasteText, suffix: "%")
                let totals = LumberTotals.of(store.items, wastePercent: number(wasteText) ?? 0)
                ResultRow(label: "Total", value: "\(Format.decimal(totals.boardFeet, places: 2)) bf")
                ResultRow(label: "With waste", value: "\(Format.decimal(totals.boardFeetWithWaste, places: 2)) bf")
                // Board feet stay the main unit in both systems because the price is per board
                // foot. Metric adds the volume in cubic meters so the amount reads in familiar units.
                if unit == .metric {
                    ResultRow(label: "Volume with waste", value: Format.cubicMeters(boardFeet: totals.boardFeetWithWaste))
                }
                if totals.cost > 0 {
                    ResultRow(label: "Cost", value: Format.money(totals.cost))
                    ResultRow(label: "Cost with waste", value: Format.money(totals.costWithWaste))
                }
                Button("Clear list", role: .destructive) { confirmClear = true }
            } header: {
                Text("Lumber list")
            } footer: {
                Text("Swipe left on a board to remove it.")
            }
        }
    }

    // MARK: - Helpers

    /// Second line under the board feet result: per piece board feet when the quantity is more
    /// than one, and the volume in cubic meters in metric (board feet stay the headline because
    /// the price is per board foot). Nil, so no line, for one imperial board.
    private func resultDetail(_ bf: Double) -> String? {
        var parts: [String] = []
        if quantity > 1 { parts.append("\(Format.decimal(bf / Double(quantity), places: 2)) each") }
        if unit == .metric { parts.append(Format.cubicMeters(boardFeet: bf)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// One line summary of a saved board: its size converted from inches to the current units,
    /// then quantity and price when they matter. Imperial sizes always use 1/16 fractions here,
    /// not the precision setting.
    private func describe(_ item: LumberItem) -> String {
        var s = unit.dimensions([item.thickness, item.width, item.length], precision: 16)
        if item.quantity > 1 { s += "  ×\(item.quantity)" }
        if item.pricePerBoardFoot > 0 { s += "  @ \(Format.money(item.pricePerBoardFoot))" }
        return s
    }
}
