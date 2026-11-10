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
        UnitSwitcher.prepare()
        CursorToEnd.install()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(lumber)
        }
    }
}

/// The root tab view. The selected tab's tag (0 to 4) is saved under "app_tab", so the app reopens
/// on the tab the user left.
struct ContentView: View {
    @AppStorage("app_tab") private var tab = 0

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
            EndGrainView()
                .tabItem { Label("End Grain", systemImage: "square.grid.3x3") }
                .tag(4)
        }
    }
}

/// Puts the cursor after the text whenever a field starts editing, so tapping a number lets you
/// backspace or add to it right away instead of landing in front of it.
///
/// SwiftUI's TextField has no way to set the selection on iOS 17, so this works at the UIKit
/// level: it observes every UITextField in the app (object: nil), which is what SwiftUI's
/// TextField uses on iOS. Call install() once at launch.
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
                    let end = field.endOfDocument
                    field.selectedTextRange = field.textRange(from: end, to: end)
                }
            }
        }
    }
}
