// PlannersView.swift
//
// Planners tab, added in 1.2 when the app outgrew five tabs. It lists the project planners (End
// Grain, Drawers, Shelf Sag, Spacing) and pushes the one the user picks. The open planner is saved
// under "planner_open", so the app comes back to it the way the tab bar comes back to its tab.
//
// The planners' screens don't have their own NavigationStack; this view's stack holds them, and
// their navigation titles and toolbar buttons attach to it.

import SwiftUI
import StoreKit

/// The planners on the Planners tab, in list order. The raw value is what "planner_open" stores.
enum Planner: String, CaseIterable, Identifiable, Hashable {
    case endGrain, drawer, shelf, spacing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .endGrain: return "End Grain Board"
        case .drawer: return "Drawer Sizer"
        case .shelf: return "Shelf Sag"
        case .spacing: return "Even Spacing"
        }
    }

    var subtitle: String {
        switch self {
        case .endGrain: return "Strips, slices, glue-ups and lumber to buy"
        case .drawer: return "Box size, parts, slide length and front"
        case .shelf: return "How much a loaded shelf will bow"
        case .spacing: return "Equal gaps for slats, balusters and holes"
        }
    }

    var icon: String {
        switch self {
        case .endGrain: return "square.grid.3x3"
        case .drawer: return "archivebox"
        case .shelf: return "books.vertical"
        case .spacing: return "ruler"
        }
    }
}

/// The Planners tab: a list of planners, each pushed on tap.
struct PlannersView: View {
    /// True for people who used a version before 1.2, until they open End Grain here.
    static let movedNoteKey = "planner_movedNote"

    @AppStorage("planner_open") private var openRaw = ""
    @AppStorage(PlannersView.movedNoteKey) private var showMovedNote = false
    @Environment(\.requestReview) private var requestReview

    /// The navigation path, kept to at most one planner and saved as its raw value.
    private var path: Binding<[Planner]> {
        Binding(
            get: { Planner(rawValue: openRaw).map { [$0] } ?? [] },
            set: { openRaw = $0.last?.rawValue ?? "" }
        )
    }

    var body: some View {
        NavigationStack(path: path) {
            List {
                Section {
                    ForEach(Planner.allCases) { planner in
                        row(planner)
                    }
                } footer: {
                    if showMovedNote {
                        Text("End Grain Board moved here from its own tab.")
                    }
                }
            }
            .navigationTitle("Planners")
            .navigationDestination(for: Planner.self) { planner in
                switch planner {
                case .endGrain: EndGrainView()
                case .drawer: DrawerView()
                case .shelf: ShelfSagView()
                case .spacing: SpacingView()
                }
            }
            // The list has no lengths, so it has no in/mm toggle, like the Fractions tab.
            .settingsButton(showsUnits: false)
        }
        .onChange(of: openRaw, initial: true) { old, new in
            if new == Planner.endGrain.rawValue { showMovedNote = false }
            // Coming back to the list from a planner is a finished task for the rating prompt.
            if !old.isEmpty && new.isEmpty { askForReviewIfDue(requestReview) }
        }
    }

    /// One planner row: icon, title and a line saying what it does.
    private func row(_ planner: Planner) -> some View {
        NavigationLink(value: planner) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(planner.title)
                    Text(planner.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: planner.icon)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.vertical, 4)
        }
    }
}
