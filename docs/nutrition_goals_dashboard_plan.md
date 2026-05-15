# Nutrition Goals + Dashboard Summary Plan

This plan extends the existing nutrition logging system with user nutrition goals, daily progress tracking, and a Dashboard nutrition summary card below Activity.

Current implementation already includes:

- Supabase-backed `nutrition_logs` and `nutrition_log_items`.
- `NutritionManager.loadedDayTotals` for confirmed meal totals.
- Stored macro fields for calories, protein, carbs, fat, fiber, sodium, and extra nutrients such as sugar when available.
- A Nutrition tab in `ContentView`.

## Product goals

1. Let users choose a nutrition goal style:
   - Low Carb
   - Mediterranean
   - Balanced
   - Custom
2. Track daily progress toward nutrition targets.
3. Include progress for:
   - Calories
   - Protein
   - Carbs
   - Fat
   - Sugar
   - Sodium / salt
4. Show a compact daily nutrition summary card on the Dashboard directly below the Activity card.
5. Keep Dashboard tap behavior simple: tapping the nutrition card opens the Nutrition tab.

## Data model

Add a per-user active nutrition goal in Supabase so goals sync across devices and stay aligned with the server-backed nutrition logs.

Suggested table: `nutrition_goals`

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | Primary key |
| `user_id` | uuid | References authenticated user |
| `goal_type` | text | `low_carb`, `mediterranean`, `balanced`, `custom` |
| `daily_calories` | numeric | Daily calorie target |
| `protein_g` | numeric | Daily protein target |
| `carb_g` | numeric | Daily carbohydrate target |
| `fat_g` | numeric | Daily fat target |
| `sugar_g` | numeric | Daily sugar limit or target |
| `sodium_mg` | numeric | Daily sodium limit or target |
| `fiber_g` | numeric nullable | Optional future tracker |
| `is_active` | boolean | Allows history later; only one active goal per user |
| `created_at` | timestamptz | Default now |
| `updated_at` | timestamptz | Maintained on update |

RLS should allow users to select, insert, update, and delete only their own rows.

Implement this directly with the Supabase table. Do not add a local-only `UserDefaults` goal store for v1.

## iOS models

Add goal models in `HealthTracker/NutritionModels.swift`.

Suggested shape:

```swift
enum NutritionGoalType: String, Codable, CaseIterable, Identifiable {
    case lowCarb = "low_carb"
    case mediterranean
    case balanced
    case custom
}

struct NutritionGoal: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var goalType: NutritionGoalType
    var dailyCalories: Double
    var proteinG: Double
    var carbG: Double
    var fatG: Double
    var sugarG: Double
    var sodiumMg: Double
    var fiberG: Double?
}

struct NutritionProgressItem: Identifiable, Hashable {
    enum Kind: String {
        case calories
        case protein
        case carbs
        case fat
        case sugar
        case sodium
    }

    let kind: Kind
    let current: Double
    let target: Double
    let unit: String

    var progress: Double {
        guard target > 0 else { return 0 }
        return current / target
    }
}
```

The UI can treat calories, protein, carbs, and fat as positive progress goals. Sugar and sodium should be displayed as limit-oriented goals where over-target is visually distinct.

## Goal presets

Preset values should be editable after selection. Exact numbers can be tuned later; these are product defaults, not medical advice.

| Preset | Calories | Protein | Carbs | Fat | Sugar | Sodium |
|---|---:|---:|---:|---:|---:|---:|
| Balanced | 2,000 kcal | 125 g | 225 g | 67 g | 50 g | 2,300 mg |
| Low Carb | 2,000 kcal | 150 g | 100 g | 110 g | 35 g | 2,300 mg |
| Mediterranean | 2,000 kcal | 110 g | 225 g | 75 g | 45 g | 2,000 mg |
| Custom | User-entered | User-entered | User-entered | User-entered | User-entered | User-entered |

Use sodium internally because `nutrition_log_items` already stores `sodium_mg`. If the product copy uses "salt", convert sodium to salt equivalent:

```swift
let saltG = sodiumMg * 2.5 / 1000
```

Recommended UI language:

- Detailed tracker: "Sodium"
- Friendly summary or tooltip: "Salt estimate"

## NutritionManager work

Extend `HealthTracker/NutritionManager.swift` with:

- `@Published private(set) var activeGoal: NutritionGoal?`
- `func loadActiveGoal() async`
- `func saveGoal(_ goal: NutritionGoal) async`
- `func dailyTotals(for date: Date) async`
- `func progress(for totals: NutritionDayTotals, goal: NutritionGoal) -> [NutritionProgressItem]`

The current `loadedDayTotals` depends on whichever logs are loaded in the Nutrition tab. Dashboard needs a date-specific loader for today so it does not accidentally reflect a different selected day.

Create a small totals model:

```swift
struct NutritionDayTotals: Hashable {
    var calories: Double
    var proteinG: Double
    var carbG: Double
    var fatG: Double
    var sugarG: Double
    var sodiumMg: Double
}
```

Sugar should use the existing nutrient extraction path from `NutritionLogItemRow.sugarGramsFromNutrients`. Sodium should sum `item.sodium_mg ?? 0`.

## Goal setup UI

Add a goal setup/edit surface inside the Nutrition tab.

Recommended flow:

1. User taps a goal chip or settings button.
2. A sheet opens with preset selection.
3. Preset fills editable fields.
4. User can adjust targets.
5. Save writes the active goal.

Fields:

- Daily calories
- Protein
- Carbs
- Fat
- Sugar
- Sodium

Use numeric fields with units. For sodium, store mg and display mg to avoid conversion ambiguity.

## Daily progress UI

Add a progress section in `NutritionView` using the shared `NutritionProgressItem` model.

Recommended layout:

- Calories as the primary row.
- Protein, carbs, and fat as macro progress rows.
- Sugar and sodium as limit rows.

Visual behavior:

- Under target: normal progress color.
- Near target for sugar/sodium: caution color.
- Over target for sugar/sodium: warning color and progress can clamp visually at 100% while text shows actual value.

## Dashboard summary card

Add a new `MiniNutritionCard.swift`, visually aligned with `MiniActivityCard.swift`.

Placement:

- In `DashboardView` inside `ContentView.swift`.
- Immediately below `MiniActivityCard`.
- Above the active challenge card.

Card behavior:

- Tap sets `selectedTab = 3` to open Nutrition.
- If no goal exists, show "Set a nutrition goal".
- If a goal exists and no meals are logged, show zero progress.
- If meals and a goal exist, show calories and compact macro progress.

Suggested compact card content:

- Title: "Nutrition Today"
- Main line: `1,420 / 2,000 kcal`
- Macro row: `Protein 72g`, `Carbs 110g`, `Fat 48g`
- Limit row: `Sugar 28g`, `Sodium 1,450mg`

Keep the card dense. Dashboard already has several sections, so this should feel like a glanceable status card rather than a full nutrition dashboard.

## Edge cases

- Logs without `sodium_mg`: count sodium as zero and avoid implying "unknown" unless all sodium values are missing.
- Logs without sugar in `nutrients`: count sugar as zero for v1, but consider a future "partial data" indicator.
- Custom goals with zero target values: avoid divide-by-zero and hide progress percentage for that tracker.
- Multiple active goals: enforce one active row in app logic; optionally add a database partial unique index on `(user_id) where is_active`.
- Date changes: reload Dashboard nutrition totals on `.NSCalendarDayChanged`, matching existing HealthKit refresh behavior.

## Files likely touched

| Area | File |
|---|---|
| Models | `HealthTracker/NutritionModels.swift` |
| Data loading + persistence | `HealthTracker/NutritionManager.swift` |
| Nutrition goal/edit UI | `HealthTracker/NutritionView.swift` or new `NutritionGoalSettingsView.swift` |
| Dashboard card | New `HealthTracker/MiniNutritionCard.swift` |
| Dashboard placement | `HealthTracker/ContentView.swift` |
| Supabase migration | New file under `supabase/migrations/` |
| Xcode project | `HealthTracker.xcodeproj/project.pbxproj` if adding new Swift files manually |

## Verification

After code changes, build for simulator:

```bash
xcodebuild build \
  -project HealthTracker.xcodeproj \
  -scheme HealthTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

There are no automated tests in this project; successful build is the required verification.

## Phase implementation

### Phase 1: Goal models and presets

- Add `NutritionGoalType`, `NutritionGoal`, `NutritionDayTotals`, and `NutritionProgressItem`.
- Add default preset values for Low Carb, Mediterranean, Balanced, and Custom.
- Add sugar and sodium to the progress model from the start.

Exit criteria: Models compile and presets can produce editable goal values.

### Phase 2: Persistence

- Add the Supabase `nutrition_goals` migration with RLS policies.
- Add `loadActiveGoal()` and `saveGoal(_:)` to `NutritionManager`.
- Ensure one active goal per user.

Exit criteria: A selected goal survives app restart and syncs from Supabase.

### Phase 3: Daily totals and progress calculations

- Add a date-specific nutrition totals loader for Dashboard.
- Sum calories, protein, carbs, fat, sugar, and sodium.
- Convert totals to progress items against the active goal.
- Treat sugar and sodium as limit-oriented trackers.

Exit criteria: Today’s progress is correct independent of the Nutrition tab’s selected day.

### Phase 4: Nutrition goal UI

- Add a goal settings sheet or screen inside the Nutrition tab.
- Support preset selection and custom overrides.
- Save active goal through `NutritionManager`.

Exit criteria: User can choose Low Carb, Mediterranean, Balanced, or Custom and edit all targets including sugar and sodium.

### Phase 5: Nutrition tab progress section

- Add daily goal progress rows to `NutritionView`.
- Show calories, macros, sugar, and sodium.
- Add sensible empty states for missing goals and missing logs.

Exit criteria: Nutrition tab clearly shows daily intake versus goal.

### Phase 6: Dashboard summary card

- Add `MiniNutritionCard.swift`.
- Load today’s totals and active goal.
- Insert card below `MiniActivityCard` in Dashboard.
- Tap card to navigate to the Nutrition tab.

Exit criteria: Dashboard shows a compact nutrition summary below Activity.

### Phase 7: Polish and validation

- Tune card spacing, colors, and progress behavior.
- Confirm sugar/sodium over-target states read clearly.
- Build the app and fix compiler errors.

Exit criteria: Simulator build succeeds and the UI handles no-goal, no-log, and over-target states.
