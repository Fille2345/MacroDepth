# MacroDepth

iOS 17+ app that combines ARKit LiDAR depth with Gemini vision to estimate food portions and macros.

## Setup

```sh
brew install xcodegen
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # add your GEMINI_API_KEY
xcodegen generate
open MacroDepth.xcodeproj
```

The app builds and runs without a key. In that case Settings shows the configuration error, and scans use sample data, labelled as such on the review screen.

To check your key and the request format against the real API, using a few tokens:

```sh
TEST_RUNNER_MACRODEPTH_LIVE_GEMINI=1 xcodebuild test -scheme MacroDepth \
  -destination 'platform=iOS Simulator,name=<simulator>' \
  -only-testing:MacroDepthTests/GeminiLiveTests
```

## Layout

| Folder | Contents |
| --- | --- |
| `MacroDepth/App` | Entry point, dependency container, root tab view |
| `MacroDepth/Domain` | Sendable value types, typed errors, SwiftData models, portion math |
| `MacroDepth/Services` | Service protocols plus live, mock and simulated implementations |
| `MacroDepth/Features` | View + `@Observable` view-model pairs (Dashboard, Progress, Scan, ManualTracking, Recipes, Log, Settings, Onboarding) |
| `MacroDepth/Support` | Configuration, formatters, concurrency helpers, sample scene |
| `MacroDepthTests` | Swift Testing suites |

## Conventions

- Carbohydrates are *available* carbs (fibre excluded), as on EU labels. Fibre counts 2 kcal/g in the Atwater check.
- Bounding boxes are normalized, top-left origin. Gemini's `box_2d` (`[ymin, xmin, ymax, xmax]`, 0–1000) is converted at the boundary.
- Grams are always computed on device (`PortionCalculator`). Gemini only suggests density, and that value is clamped to per-category bounds.
- `VolumeCalculatorService` measures each item's footprint and height above a plane fitted to the plate, then applies its category's `FoodShape`. Any item it can't measure falls back to Gemini's photo estimate on its own. One view can't see a dome's far side, so piles read low when the phone is tilted. It needs a surface the food rests on, so food held in a hand falls back too.
- ARKit delivers landscape sensor frames. `ARFrameConverter` rotates the image, depth, confidence, intrinsics and pose together to upright portrait, so they stay aligned. Never rotate just one of them.
- Daily targets come from `UserProfileDraft.targets` (Mifflin-St Jeor, then the goal's adjustment). Calculated and manual targets are both clamped to `TargetLimits`.
- View models learn about new data from `PersistenceServiceProtocol.changes()` rather than `@Query`, so SwiftData stays behind the service.
- A scan has one or two photos but one depth map. Depth, intrinsics and bounding boxes all refer to the first (top-down) photo; the second (angled) photo is RGB context only.
- Manual tracking finds foods through `FoodLookupServiceProtocol`, using `OpenFoodFactsService` in the live app and `MockFoodLookupService` in previews and tests. Open Food Facts allows 10 searches and 15 product reads a minute, so search runs on submit, never per keystroke. Its data is ODbL, so the UI credits it.
- Food search is hybrid. `GenericFoodCatalog` (USDA values, English and Swedish names) filters as you type with no network, and its results come first. Open Food Facts results follow after the user submits, and a failure there leaves the whole foods in place.
- ARKit and `BarcodeCameraController` can't share the camera. `ScanViewModel` pauses the AR session before the barcode camera starts, and restarts it when the sheet closes.
- A `SavedMeal` is a template. Logging one copies its components into a new `MealEntry`, so editing or deleting a template never changes past days. Every record owns its own photo file.
- New stored properties must be optional or have a default, so existing stores migrate automatically. `SavedMealMigrationTests` keeps a copy of the previous schema to check this.
- User notes can change Gemini's macros and density suggestions, but never measured volume. Pasted text is treated as data, not as instructions to the model.

## Security note

A key in `Secrets.xcconfig` ends up in the app bundle and can be extracted. That's fine for development. Before release, swap the Gemini client for a backend proxy.
