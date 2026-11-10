# Shop Math

iPhone and iPad app with five shop tools:

1. **Cleats**: table saw fence setting for 45° French cleats. Rip one board into two matching cleats, or bevel one edge of a strip. Accounts for kerf and blade tilt direction, solves from board width or target cleat width, and has a test cut check that tells you how far to bump the fence.
2. **Board Feet**: actual dimensions in inches (length also takes feet, like 8'), quantity, price per board foot, and a saved lumber list with a waste allowance.
3. **Fractions**: shop calculator keypad. Feet, inches, mixed fractions, rounding to 1/8 through 1/64, decimal and mm.
4. **Angles**: flat frames, straight sided boxes, and sloped sided boxes (compound miter and bevel), plus long point and short point lengths.
5. **End Grain**: strip count, strip length, slice width, glue-up sizes, and board feet for an end grain cutting board.

Every length field accepts `1.75`, `1 3/4`, `1-3/4`, `7' 4 1/2"`, `7'-4"`, and math like `(3 + 1/2) × 2`.

## Imperial and metric

Tap the **in / mm** button at the top of any tab to switch. Everything you've entered converts (5 1/2 becomes 139.7 and back again), and the choice is also in Settings.

- Metric fields are in millimeters and show results to 0.1 mm. They also take `14 cm`, `2.4 m`, and inch or foot entries like `5 1/2"` or `8'`.
- Imperial fields also take metric entries like `19 mm`.
- Board feet stays the main number in both modes. Metric mode adds cubic meters as a second line.
- Fraction precision (1/8 to 1/64) applies to imperial only.

## Open and run

1. Unzip and double click **ShopMath.xcodeproj**.
2. Click the **ShopMath** project at the top of the left sidebar, select the **ShopMath** target, and open **Signing & Capabilities**. Choose your developer team.
3. Pick your iPhone (or a simulator) as the run destination and press ⌘R.

Uploading to TestFlight is covered in the Shop Math TestFlight Guide.

## Project layout

A standard Xcode iOS app project (iOS 17 and later, iPhone and iPad). The `ShopMath` folder is a synchronized folder: any file added to it on disk is part of the app, with no project file edits.

- `ShopMath/ShopMathApp.swift`: app entry point and tabs
- `ShopMath/Core/Measure.swift`: measurement parser and fraction formatting
- `ShopMath/Core/ShopMath.swift`: all the math (cleats, board feet, angles, end grain planner)
- `ShopMath/Core/Units.swift`: imperial and metric handling and saved entries
- `ShopMath/Views/`: one SwiftUI screen per tool, plus shared components and settings
- `ShopMath/Assets.xcassets`: app icon and accent color
- `ShopMath/Info.plist`: only `ITSAppUsesNonExemptEncryption = NO`, so App Store Connect doesn't ask the encryption question on each upload. Everything else is generated from build settings.

Version and build numbers are in the target's **General** tab (Version and Build). Bundle ID: `com.marigottlieb.shopmath`.

## The cleat math

Fence distance `a` is measured at the table from the fence to the fence side of the kerf. Board width `W`, thickness `t`, kerf `k` (across the blade, so `k·√2` on the table at 45°).

| Method | Blade tilt | Fence setting | Cleat wide face |
| --- | --- | --- | --- |
| Rip in half | Away from fence | (W − t − k√2) / 2 | (W + t − k√2) / 2 |
| Rip in half | Toward fence | (W + t − k√2) / 2 | (W + t − k√2) / 2 |
| Bevel one edge of strip S | Away from fence | S − t | S |
| Bevel one edge of strip S | Toward fence | S | S |

Board width for a target cleat width C: `2C − t + k√2`.

Compound angles for n sides tilted T from vertical, board flat on the saw: bevel = asin(sin(180/n) · cos T), miter = atan(tan(180/n) · sin T).
