# MacroDepth

iOS 17+ app that combines ARKit LiDAR depth with Gemini vision to estimate food portions and macros.

## Setup

```sh
brew install xcodegen
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # add your GEMINI_API_KEY
xcodegen generate
open MacroDepth.xcodeproj
```

The app builds and runs without a key. In that case Settings shows the configuration error, and the mock services keep working.

## Layout

| Folder | Contents |
| --- | --- |
| `MacroDepth/App` | Entry point, dependency container, root tab view |
| `MacroDepth/Domain` | Sendable value types, typed errors, SwiftData models, portion math |
| `MacroDepth/Services` | Service protocols plus live, mock and simulated implementations |
| `MacroDepth/Features` | View + `@Observable` view-model pairs (Scan, Log, Settings) |
| `MacroDepth/Support` | Configuration, formatters, concurrency helpers, sample scene |
| `MacroDepthTests` | Swift Testing suites |

## Conventions

- Carbohydrates are *available* carbs (fibre excluded), as on EU labels. Fibre counts 2 kcal/g in the Atwater check.
- Bounding boxes are normalized, top-left origin. Gemini's `box_2d` (`[ymin, xmin, ymax, xmax]`, 0–1000) is converted at the boundary.
- Grams are always computed on device (`PortionCalculator`). Gemini only suggests density, and that value is clamped to per-category bounds.
- ARKit delivers landscape sensor frames. `ARFrameConverter` rotates the image, depth, confidence, intrinsics and pose together to upright portrait, so they stay aligned. Never rotate just one of them.
- A scan has one or two photos but one depth map. Depth, intrinsics and bounding boxes all refer to the first (top-down) photo; the second (angled) photo is RGB context only.
- User notes can change Gemini's macros and density suggestions, but never measured volume. Pasted text is treated as data, not as instructions to the model.

## Security note

A key in `Secrets.xcconfig` ends up in the app bundle and can be extracted. That's fine for development. Before release, swap the Gemini client for a backend proxy.
