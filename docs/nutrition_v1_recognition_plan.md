# V1 recognition plan — Nutrition

This document turns **roadmap item “V1 recognition”** from [nutrition_tracking_plan.md](./nutrition_tracking_plan.md) into a concrete checklist.

**V1 scope (from roadmap):**

- **Photo path** — capture or pick image → server-side recognition → ranked food candidates → user confirms portion → save.
- **Barcode path** — live scan → product lookup → user confirms portion → save.
- **Shared confirmation UI** — same grams scaling + macro preview + save for search, barcode, and photo.
- **Storage for photo logs** — meal photo stored in Supabase Storage when the user saves a photo-sourced meal.

---

## Current implementation status (repo)


| Area                | Status  | Where                                                                                                                                             |
| ------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Text search (MVP)   | Shipped | `LogFoodSheet` → `lookupSearch` → `food-lookup` `mode: "search"`                                                                                  |
| Barcode scan        | Shipped | `BarcodeScannerView` (AVFoundation metadata) → `lookupBarcode`                                                                                    |
| Photo pick + camera | Shipped | PhotosPicker + `ImagePickerRepresentable` → resize JPEG → `lookupPhoto`                                                                           |
| Confirmation + save | Shipped | `ConfirmFoodSheet` → `NutritionManager.saveMeal`                                                                                                  |
| Photo upload        | Shipped | `meal-photos` bucket path `{user_id}/{log_id}.jpg` after log insert                                                                               |
| Edge function       | In repo | `[supabase/functions/food-lookup/](../supabase/functions/food-lookup/)` — barcode (OFF), search (USDA if key else OFF), photo (OpenAI + USDA/OFF) |


So **most of V1 is already coded**. The plan below is about **shipping it reliably** and **closing known gaps** so you can call V1 “done.”

---

## Phase A — Backend & config (blockers)

These are required for recognition to work in production (not just local dev).

1. **Database** — Migration applied: `[supabase/migrations/20260407120000_nutrition.sql](../supabase/migrations/20260407120000_nutrition.sql)` (`nutrition_logs`, `nutrition_log_items`, `meal-photos` policies).
2. **Deploy `food-lookup`** — Function live on the same Supabase project as the app (`AuthManager` URL).
3. **Secrets** (Supabase project → Edge Function secrets):
  - `**OPENAI_API_KEY`** — Required for **photo** path to return candidates (without it, function returns empty `candidates` + explanatory `notice`).
  - `**USDA_API_KEY`** — Optional; improves **search** and **photo** follow-up food matching vs Open Food Facts alone.
4. **JWT** — Keep `**verify_jwt` enabled** on the function; the app sends `Authorization: Bearer <access_token>` (session refresh path is already used in `NutritionManager`).

**Exit criteria:** Barcode lookup returns a product for a known UPC on-device; photo lookup returns candidates for a simple single-food image with `OPENAI_API_KEY` set.

---

## Phase B — Barcode V1 quality bar

Goal: predictable scans on real packaging, clear failures.


| Task                          | Notes                                                                                                                                          |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| **Symbology coverage**        | Confirm common retail formats work (EAN-13, EAN-8, UPC-E, Code 128 where needed). Adjust `metadataObjectTypes` if a target product type fails. |
| **Debounce / single fire**    | Scanner already stops session after first code; verify no double-save or double API call if the delegate fires twice on some devices.          |
| **Empty / unknown barcode**   | Surface `notice` from API in the log sheet (not only `errorMessage`) so “not in Open Food Facts” is visible.                                   |
| **Optional: torch**           | Add torch toggle on scanner UI for low light (nice-to-have for V1).                                                                            |
| **Optional: GTIN validation** | Edge function could validate check digit for 12/13-digit codes before calling OFF (reduces junk lookups).                                      |


**Exit criteria:** Scan 5 diverse packaged items (US + import if possible); at least clear UX when lookup misses.

---

## Phase C — Photo V1 quality bar


| Task                 | Notes                                                                                                                                                                                        |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Payload size**     | Large photos → base64 JSON can hit Edge / gateway limits. Current resize (~800px, JPEG ~0.7) is a mitigation; document max size or add client-side cap + user-visible error if invoke fails. |
| **Empty / error UX** | Show loading during analyze; show `notice` + `errorMessage` inline in photo mode (same as barcode).                                                                                          |
| **Permissions**      | Camera + library strings are in `Info.plist`; verify first-run flows on physical device.                                                                                                     |
| **Model / prompt**   | Optional hardening: tighten OpenAI prompt or switch model if JSON parsing often fails on messy plates.                                                                                       |


**Exit criteria:** Simple plate photo → at least one sensible candidate; failure cases show a human-readable message, not a silent empty list.

---

## Phase D — Shared confirmation & data model (V1 completeness)


| Task                             | Notes                                                                                                                                                                                                                                                                                   |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Single item per save (today)** | One `nutrition_log` + one `nutrition_log_items` row per confirmation. Photo flow may return **many** candidates; user picks **one** per save. **V1 is still satisfied**; logging multiple foods from one photo = repeat flow or defer to **V1.1** (multi-select + one log, many items). |
| **Meal type**                    | `meal_type` exists on `nutrition_logs` but may be unused in UI; optional for V1: set from quick picker on confirm (breakfast/lunch/dinner/snack).                                                                                                                                       |
| **HealthKit**                    | Already gated by Apple Health toggle; no change required for V1 recognition scope.                                                                                                                                                                                                      |


**Exit criteria:** Barcode, photo, and search all land on the same confirm sheet and produce consistent rows in Supabase.

---

## Phase E — Verification (release gate)

1. **Device matrix** — At least one **physical** iPhone: camera scan, library pick, barcode in store lighting.
2. **Account** — Signed-in user; RLS allows insert/select; Storage upload succeeds for photo meals.
3. **Regression** — Manual search + save still works; pull-to-refresh on Nutrition list.
4. **Build** — `xcodebuild` green (project rule).

---

## Optional “V1.1” (not required to close V1)

Full sequencing, schema notes, HealthKit strategy, and exit criteria live in **[nutrition_v1_1_implementation_plan.md](./nutrition_v1_1_implementation_plan.md)**.

**Scope summary:**

- Multi-item logging from one photo (one log, multiple `nutrition_log_items`, summed HealthKit write or per-item samples — product decision).
- Typical **serving / household** data from Open Food Facts and USDA (detail where needed), applied as the default portion on confirm—not only implicit 100 g.
- **Per-item quantity** (e.g. “2 pancakes”) so users multiply label servings without manually doubling grams; stored on `nutrition_log_items` (see implementation plan).
- **Extended nutrition** beyond core macros, persisted for in-app reference (e.g. `nutrients` JSONB + optional detail UI); HealthKit scope unchanged unless you decide later.
- VisionKit `DataScannerViewController` instead of raw AVFoundation (simpler maintenance, similar UX), with fallback where unsupported.
- Thumbnail of `photo_path` in meal list (signed URLs + caching).
- Favorites / recents for faster re-logging.
- Meal notes on `nutrition_logs`.
- Update Apple Health when a meal is edited (metadata correlation + delete/rewrite).
- Offline / retry queue for failed lookups and saves.

---

## Summary

**V1 recognition** in code is largely **already implemented**. Treat **Phase A** as the real gate; **Phases B–E** are how you prove barcode + photo are **reliable and understandable** in production. Use the exit criteria above to sign off V1 before moving to **V2 polish** (favorites, trends, micronutrients, `daily_stats`, etc.).

---

## Progress log (repo)


| Item                                             | Status                                                                    |
| ------------------------------------------------ | ------------------------------------------------------------------------- |
| Phase A                                          | Still **your** Supabase: migration, deploy `food-lookup`, secrets         |
| Barcode: torch + ignore duplicate delegate fires | Done (`NutritionView.swift` scanner VC)                                   |
| Barcode: surface notices / errors                | Done — `lookupNoticeView` (orange empty / red error), progress after scan |
| Search: loading indicator                        | Done                                                                      |
| Photo: compress under ~2.4MB JPEG + base64 cap   | Done (`ht_jpegForFoodLookup`, `NutritionManager.lookupPhoto`)             |
| Photo: size hint + notices                       | Done                                                                      |
| Edge: GTIN check digit (8/12/13/14)              | Done (`food-lookup/index.ts`)                                             |
| Edge: max base64 length guard                    | Done (413 + message)                                                      |
| `.upca` symbology                                | Not used — current SDK literal unavailable; EAN-13 covers many UPC cases  |


