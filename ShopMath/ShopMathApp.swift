// ShopMathApp.swift
//
// The app entry point and the root tab view. Launch does two pieces of setup before any screen
// appears: it brings stored entries up to date (UnitSwitcher.prepare in Core/Units.swift) and
// installs a text field workaround (CursorToEnd, below). Each tab's screen lives in Views/, the
// shared entry and result components in Views/Components.swift, and the math in
// Core/ShopMath.swift.

import SwiftUI
import UIKit

/// The app. Runs startup prep in init and owns the lumber list (LumberStore), which it hands to
/// the tabs as an environment object.
@main
struct ShopMathApp: App {
    @StateObject private var lumber = LumberStore()

    init() {
        // This runs before any screen reads its @AppStorage entries. prepare() carries saved
        // values over from 1.0's dotted keys and writes every length entry that was never saved,
        // in the current unit system, so a default like "5 1/2" is never read as millimeters.
        // 1.2 moved End Grain from the fifth tab into the Planners tab, which took its place.
        // Anyone who used an earlier version sees a note on the Planners list until they open End
        // Grain. 1.1 saves every entry at launch, so a saved End Grain length means 1.1 ran. 1.0
        // saved only what the user changed, under dotted keys, so any of those means 1.0 ran.
        // This has to run before prepare(), which saves entries for new users too and removes
        // the dotted keys.
        let d = UserDefaults.standard
        if d.object(forKey: PlannersView.movedNoteKey) == nil {
            let returning = d.object(forKey: LengthField.egLength.key) != nil
                || UnitSwitcher.legacyKeys.contains { d.object(forKey: $0) != nil }
            d.set(returning, forKey: PlannersView.movedNoteKey)
        }
        UnitSwitcher.prepare()
        CursorToEnd.install()
        // Someone who left 1.1 on End Grain comes back to it instead of the list. This runs on
        // the first 1.2 launch only, so a new user who leaves the Planners list showing isn't
        // sent to End Grain later.
        if d.object(forKey: "planner_migrated") == nil {
            if d.integer(forKey: "app_tab") == 4, d.object(forKey: "planner_open") == nil {
                d.set(Planner.endGrain.rawValue, forKey: "planner_open")
            }
            d.set(true, forKey: "planner_migrated")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(lumber)
        }
    }
}

/// The root tab view. The selected tab's tag (0 to 4) is saved under "app_tab", so the app reopens
/// on the tab the user left. Each day the app comes to the foreground counts as a day of use for
/// the rating prompt (see Core/ReviewPrompt.swift).
struct ContentView: View {
    @AppStorage("app_tab") private var tab = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $tab) {
            CleatView()
                .tabItem { Label("Cleats", systemImage: "square.split.diagonal") }
                .tag(0)
            BoardFeetView()
                .tabItem { Label("Board Feet", systemImage: "cube") }
                .tag(1)
            FractionCalcView()
                .tabItem { Label("Fractions", systemImage: "plus.forwardslash.minus") }
                .tag(2)
            AnglesView()
                .tabItem { Label("Angles", systemImage: "angle") }
                .tag(3)
            PlannersView()
                .tabItem { Label("Planners", systemImage: "square.grid.2x2") }
                .tag(4)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { ReviewPrompt.recordUse() }
        }
    }
}

/// Puts the cursor after the text whenever a field starts editing, so tapping a number lets you
/// backspace or add to it right away instead of landing in front of it.
///
/// SwiftUI's TextField has no way to set the selection on iOS 17, so this works at the UIKit
/// level: it observes every UITextField in the app (object: nil), which is what SwiftUI's
/// TextField uses on iOS. Only number fields are moved (the numbers and punctuation keyboard);
/// a text field such as a board's name keeps the normal tap to place behavior. Call install()
/// once at launch.
enum CursorToEnd {
    /// The observer token. A non-nil token means the observer is already installed, so a second
    /// install() call does nothing.
    private static var observer: NSObjectProtocol?

    static func install() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UITextField.textDidBeginEditingNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let field = note.object as? UITextField else { return }
            // UIKit places the cursor at the tap point after this notification, so a move made
            // here would be overwritten. Dispatching to the next pass of the main queue runs after
            // UIKit has placed it.
            DispatchQueue.main.async {
                // The compiler doesn't know this closure is main actor isolated, so it won't allow
                // touching UITextField, a main actor type, directly. The closure does run on the
                // main queue, so assumeIsolated is safe: it states what is already true and traps
                // at runtime if it ever isn't.
                MainActor.assumeIsolated {
                    guard field.keyboardType == .numbersAndPunctuation else { return }
                    let end = field.endOfDocument
                    field.selectedTextRange = field.textRange(from: end, to: end)
                }
            }
        }
    }
}
