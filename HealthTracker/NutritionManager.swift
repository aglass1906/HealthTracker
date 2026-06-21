//
//  NutritionManager.swift
//  HealthTracker
//

import Foundation
import SwiftUI
import Combine
import Supabase

@MainActor
final class NutritionManager: ObservableObject {
    static let shared = NutritionManager()

    @Published private(set) var logs: [NutritionLogRow] = []
    @Published private(set) var activeGoal: NutritionGoal?
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Last successful `loadLogs` range; used to refresh the same day after saves/deletes.
    private(set) var lastLoadedLogsStart: Date?
    private(set) var lastLoadedLogsEnd: Date?

    private let functionName = "food-lookup"
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {}

    private var client: SupabaseClient { AuthManager.shared.client }

    private static let goalSelect =
        "id, user_id, goal_type, daily_calories, protein_g, carb_g, fat_g, sugar_g, sodium_mg, fiber_g, is_active"
    private static let itemsSelect =
        "id, log_id, name, brand, serving_amount, serving_unit, grams, quantity, calories, protein_g, carb_g, fat_g, fiber_g, sodium_mg, fdc_id, external_product_id, image_url, nutrients, combo_name"
    private static let itemsSelectWithoutImageURL =
        "id, log_id, name, brand, serving_amount, serving_unit, grams, quantity, calories, protein_g, carb_g, fat_g, fiber_g, sodium_mg, fdc_id, external_product_id, nutrients, combo_name"

    func loadLogs(from start: Date, to end: Date) async {
        guard let session = AuthManager.shared.session else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let uid = session.user.id
        let startS = isoFormatter.string(from: start)
        let endS = isoFormatter.string(from: end)

        do {
            let rows: [NutritionLogRow] = try await client
                .from("nutrition_logs")
                .select(
                    "id, user_id, logged_at, meal_type, source, barcode_raw, photo_path, status, created_at, notes, nutrition_log_items(\(Self.itemsSelect))"
                )
                .eq("user_id", value: uid)
                .gte("logged_at", value: startS)
                .lte("logged_at", value: endS)
                .order("logged_at", ascending: false)
                .execute()
                .value
            logs = rows
            lastLoadedLogsStart = start
            lastLoadedLogsEnd = end
        } catch {
            if isMissingImageURLColumn(error) {
                await loadLogsWithoutImageURL(from: start, to: end, userID: uid, startString: startS, endString: endS)
                return
            }
            errorMessage = error.localizedDescription
            print("Nutrition load error: \(error)")
        }
    }

    func loadActiveGoal() async {
        guard let session = AuthManager.shared.session else {
            activeGoal = nil
            return
        }

        errorMessage = nil

        do {
            let rows: [NutritionGoal] = try await client
                .from("nutrition_goals")
                .select(Self.goalSelect)
                .eq("user_id", value: session.user.id)
                .eq("is_active", value: true)
                .limit(1)
                .execute()
                .value
            activeGoal = rows.first
        } catch {
            errorMessage = error.localizedDescription
            print("Nutrition goal load error: \(error)")
        }
    }

    func saveGoal(_ goal: NutritionGoal) async -> Bool {
        guard let session = AuthManager.shared.session else {
            errorMessage = "Not signed in"
            return false
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        struct ActiveGoalPatch: Encodable {
            let is_active: Bool
        }

        struct GoalUpsert: Encodable {
            let id: UUID
            let user_id: UUID
            let goal_type: NutritionGoalType
            let daily_calories: Double
            let protein_g: Double
            let carb_g: Double
            let fat_g: Double
            let sugar_g: Double
            let sodium_mg: Double
            let fiber_g: Double?
            let is_active: Bool
        }

        let uid = session.user.id
        let payload = GoalUpsert(
            id: goal.id,
            user_id: uid,
            goal_type: goal.goal_type,
            daily_calories: goal.daily_calories,
            protein_g: goal.protein_g,
            carb_g: goal.carb_g,
            fat_g: goal.fat_g,
            sugar_g: goal.sugar_g,
            sodium_mg: goal.sodium_mg,
            fiber_g: goal.fiber_g,
            is_active: true
        )

        do {
            try await client
                .from("nutrition_goals")
                .update(ActiveGoalPatch(is_active: false))
                .eq("user_id", value: uid)
                .eq("is_active", value: true)
                .execute()

            let saved: NutritionGoal = try await client
                .from("nutrition_goals")
                .upsert(payload, onConflict: "id")
                .select(Self.goalSelect)
                .single()
                .execute()
                .value

            activeGoal = saved
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("Nutrition goal save error: \(error)")
            return false
        }
    }

    func dailyTotals(for date: Date) async -> NutritionDayTotals {
        guard let session = AuthManager.shared.session else {
            return NutritionDayTotals()
        }

        struct DailyTotalsLogRow: Decodable {
            let nutrition_log_items: [DailyTotalsItemRow]?
        }

        struct DailyTotalsItemRow: Decodable {
            let calories: Double
            let protein_g: Double
            let carb_g: Double
            let fat_g: Double
            let sodium_mg: Double?
            let nutrients: [String: Double]?
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let startString = isoFormatter.string(from: start)
        let endString = isoFormatter.string(from: end)

        do {
            let rows: [DailyTotalsLogRow] = try await client
                .from("nutrition_logs")
                .select(
                    "nutrition_log_items(calories, protein_g, carb_g, fat_g, sodium_mg, nutrients)"
                )
                .eq("user_id", value: session.user.id)
                .eq("status", value: "confirmed")
                .gte("logged_at", value: startString)
                .lt("logged_at", value: endString)
                .execute()
                .value

            return rows.reduce(into: NutritionDayTotals()) { totals, log in
                for item in log.nutrition_log_items ?? [] {
                    totals.calories += item.calories
                    totals.protein_g += item.protein_g
                    totals.carb_g += item.carb_g
                    totals.fat_g += item.fat_g
                    totals.sugar_g += NutritionLogItemRow.sugarGrams(from: item.nutrients)
                    totals.sodium_mg += item.sodium_mg ?? 0
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            print("Nutrition daily totals error: \(error)")
            return NutritionDayTotals()
        }
    }

    func progress(for totals: NutritionDayTotals, goal: NutritionGoal) -> [NutritionProgressItem] {
        [
            NutritionProgressItem(
                kind: .calories,
                current: totals.calories,
                target: goal.daily_calories,
                unit: "kcal"
            ),
            NutritionProgressItem(
                kind: .protein,
                current: totals.protein_g,
                target: goal.protein_g,
                unit: "g"
            ),
            NutritionProgressItem(
                kind: .carbs,
                current: totals.carb_g,
                target: goal.carb_g,
                unit: "g"
            ),
            NutritionProgressItem(
                kind: .fat,
                current: totals.fat_g,
                target: goal.fat_g,
                unit: "g"
            ),
            NutritionProgressItem(
                kind: .sugar,
                current: totals.sugar_g,
                target: goal.sugar_g,
                unit: "g"
            ),
            NutritionProgressItem(
                kind: .sodium,
                current: totals.sodium_mg,
                target: goal.sodium_mg,
                unit: "mg"
            )
        ]
    }

    private func loadLogsWithoutImageURL(
        from start: Date,
        to end: Date,
        userID uid: UUID,
        startString startS: String,
        endString endS: String
    ) async {
        do {
            let rows: [NutritionLogRow] = try await client
                .from("nutrition_logs")
                .select(
                    "id, user_id, logged_at, meal_type, source, barcode_raw, photo_path, status, created_at, notes, nutrition_log_items(\(Self.itemsSelectWithoutImageURL))"
                )
                .eq("user_id", value: uid)
                .gte("logged_at", value: startS)
                .lte("logged_at", value: endS)
                .order("logged_at", ascending: false)
                .execute()
                .value
            logs = rows
            lastLoadedLogsStart = start
            lastLoadedLogsEnd = end
        } catch {
            errorMessage = error.localizedDescription
            print("Nutrition load error: \(error)")
        }
    }

    private func isMissingImageURLColumn(_ error: Error) -> Bool {
        let description = String(describing: error)
        return description.contains("PGRST204")
            && description.contains("image_url")
            && description.contains("nutrition_log_items")
    }

    /// Reloads the same calendar day range as the last `loadLogs`, or today if none.
    func reloadLoadedLogsRange() async {
        let cal = Calendar.current
        if let s = lastLoadedLogsStart, let e = lastLoadedLogsEnd {
            await loadLogs(from: s, to: e)
        } else {
            let start = cal.startOfDay(for: Date())
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
            await loadLogs(from: start, to: end)
        }
    }

    /// Signed URL for a private `meal-photos` object (short TTL).
    func mealPhotoSignedURL(path: String, expiresIn: Int = 3600) async -> URL? {
        do {
            let url = try await client.storage
                .from("meal-photos")
                .createSignedURL(path: path, expiresIn: expiresIn)
            return url
        } catch {
            print("Signed URL error: \(error)")
            return nil
        }
    }

    func lookupBarcode(_ code: String) async -> FoodLookupResponse? {
        await invokeLookup(FoodLookupRequest(mode: "barcode", barcode: code, imageBase64: nil, mimeType: nil, query: nil))
    }

    func lookupSearch(_ query: String) async -> FoodLookupResponse? {
        await invokeLookup(FoodLookupRequest(mode: "search", barcode: nil, imageBase64: nil, mimeType: nil, query: query))
    }

    func lookupDescription(_ description: String) async -> FoodLookupResponse? {
        await invokeLookup(FoodLookupRequest(mode: "describe", barcode: nil, imageBase64: nil, mimeType: nil, query: description))
    }

    /// Avoid huge JSON bodies (~6.5M+ base64 chars can hit gateway limits); client compresses with `UIImage.ht_jpegForFoodLookup()`.
    private let maxPhotoBase64Length = 9_000_000

    func lookupPhoto(imageJPEG: Data) async -> FoodLookupResponse? {
        let b64 = imageJPEG.base64EncodedString()
        if b64.count > maxPhotoBase64Length {
            errorMessage = "Photo is still too large to upload. Try taking a new photo or choose a smaller image."
            return nil
        }
        return await invokeLookup(
            FoodLookupRequest(mode: "photo", barcode: nil, imageBase64: b64, mimeType: "image/jpeg", query: nil)
        )
    }

    private func invokeLookup(_ body: FoodLookupRequest) async -> FoodLookupResponse? {
        do {
            let session = try await client.auth.session
            let response: FoodLookupResponse = try await client.functions.invoke(
                functionName,
                options: FunctionInvokeOptions(
                    headers: ["Authorization": "Bearer \(session.accessToken)"],
                    body: body
                )
            )
            if let err = response.error {
                errorMessage = err
                return nil
            }
            return response
        } catch let error as FunctionsError {
            if case .httpError(let code, let data) = error {
                let s = String(data: data, encoding: .utf8) ?? ""
                errorMessage = "Lookup failed (\(code)): \(s)"
            } else {
                errorMessage = error.localizedDescription
            }
            print("Food lookup error: \(error)")
            return nil
        } catch let error as AuthError where error == .sessionMissing {
            errorMessage = "Not signed in"
            return nil
        } catch {
            errorMessage = error.localizedDescription
            print("Food lookup error: \(error)")
            return nil
        }
    }

    struct MealSaveLine {
        /// Macros and grams are **totals** for this line (after quantity / scaling).
        var scaledTotals: FoodCandidateDTO
        /// Stored `nutrition_log_items.quantity` (e.g. 2 pancakes).
        var quantity: Double
        /// Label serving amount for one counted unit (from API).
        var perUnitServingAmount: Double
        var perUnitServingUnit: String
        /// Non-nil when this line is part of a named combo/recipe.
        var comboName: String?
    }

    struct MealSaveInput {
        var source: String
        var mealType: String?
        var notes: String?
        var barcodeRaw: String?
        var photoJPEG: Data?
        var loggedAt: Date
        var items: [MealSaveLine]
    }

    func saveMeal(_ input: MealSaveInput, syncToHealthKit: Bool) async -> Bool {
        guard let session = AuthManager.shared.session else {
            errorMessage = "Not signed in"
            return false
        }
        guard !input.items.isEmpty else {
            errorMessage = "Nothing to save"
            return false
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let uid = session.user.id

        struct LogInsert: Encodable {
            let user_id: UUID
            let logged_at: String
            let source: String
            let meal_type: String?
            let barcode_raw: String?
            let photo_path: String?
            let status: String
            let notes: String?
        }

        struct ItemInsert: Encodable {
            let log_id: UUID
            let name: String
            let brand: String?
            let serving_amount: Double
            let serving_unit: String
            let grams: Double?
            let quantity: Double
            let calories: Double
            let protein_g: Double
            let carb_g: Double
            let fat_g: Double
            let fiber_g: Double?
            let sodium_mg: Double?
            let fdc_id: Int64?
            let external_product_id: String?
            let image_url: String?
            let nutrients: [String: Double]?
            let combo_name: String?
        }

        struct ItemInsertWithoutImageURL: Encodable {
            let log_id: UUID
            let name: String
            let brand: String?
            let serving_amount: Double
            let serving_unit: String
            let grams: Double?
            let quantity: Double
            let calories: Double
            let protein_g: Double
            let carb_g: Double
            let fat_g: Double
            let fiber_g: Double?
            let sodium_mg: Double?
            let fdc_id: Int64?
            let external_product_id: String?
            let nutrients: [String: Double]?
            let combo_name: String?
        }

        let loggedAtStr = isoFormatter.string(from: input.loggedAt)
        let notesTrimmed = input.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesOut = (notesTrimmed?.isEmpty == false) ? notesTrimmed : nil

        do {
            let newLog: NutritionLogRow = try await client
                .from("nutrition_logs")
                .insert(
                    LogInsert(
                        user_id: uid,
                        logged_at: loggedAtStr,
                        source: input.source,
                        meal_type: input.mealType,
                        barcode_raw: input.barcodeRaw,
                        photo_path: nil,
                        status: "confirmed",
                        notes: notesOut
                    )
                )
                .select("id, user_id, logged_at, meal_type, source, barcode_raw, photo_path, status, created_at, notes")
                .single()
                .execute()
                .value

            if let jpeg = input.photoJPEG {
                let path = "\(uid.uuidString.lowercased())/\(newLog.id.uuidString.lowercased()).jpg"
                try await client.storage
                    .from("meal-photos")
                    .upload(
                        path,
                        data: jpeg,
                        options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true)
                    )

                struct PhotoUpdate: Encodable {
                    let photo_path: String
                }
                try await client
                    .from("nutrition_logs")
                    .update(PhotoUpdate(photo_path: path))
                    .eq("id", value: newLog.id)
                    .execute()
            }

            for line in input.items {
                let c = line.scaledTotals
                let item = ItemInsert(
                    log_id: newLog.id,
                    name: c.name,
                    brand: c.brand,
                    serving_amount: line.perUnitServingAmount,
                    serving_unit: line.perUnitServingUnit,
                    grams: c.grams,
                    quantity: line.quantity,
                    calories: c.calories,
                    protein_g: c.protein_g,
                    carb_g: c.carb_g,
                    fat_g: c.fat_g,
                    fiber_g: c.fiber_g,
                    sodium_mg: c.sodium_mg,
                    fdc_id: c.fdc_id,
                    external_product_id: c.external_product_id,
                    image_url: c.image_url,
                    nutrients: c.nutrients_extra,
                    combo_name: line.comboName
                )
                do {
                    try await client
                        .from("nutrition_log_items")
                        .insert(item)
                        .execute()
                } catch {
                    guard isMissingImageURLColumn(error) else { throw error }
                    let fallbackItem = ItemInsertWithoutImageURL(
                        log_id: newLog.id,
                        name: c.name,
                        brand: c.brand,
                        serving_amount: line.perUnitServingAmount,
                        serving_unit: line.perUnitServingUnit,
                        grams: c.grams,
                        quantity: line.quantity,
                        calories: c.calories,
                        protein_g: c.protein_g,
                        carb_g: c.carb_g,
                        fat_g: c.fat_g,
                        fiber_g: c.fiber_g,
                        sodium_mg: c.sodium_mg,
                        fdc_id: c.fdc_id,
                        external_product_id: c.external_product_id,
                        nutrients: c.nutrients_extra,
                        combo_name: line.comboName
                    )
                    try await client
                        .from("nutrition_log_items")
                        .insert(fallbackItem)
                        .execute()
                }
            }

            if syncToHealthKit {
                var sumCal = 0.0, sumP = 0.0, sumC = 0.0, sumF = 0.0
                var sumFiber: Double = 0
                var sumSodium: Double = 0
                var sumSugar: Double = 0
                var anyFiber = false
                var anySodium = false
                var anySugar = false
                for line in input.items {
                    let c = line.scaledTotals
                    sumCal += c.calories
                    sumP += c.protein_g
                    sumC += c.carb_g
                    sumF += c.fat_g
                    if let f = c.fiber_g {
                        sumFiber += f
                        anyFiber = true
                    }
                    if let na = c.sodium_mg {
                        sumSodium += na
                        anySodium = true
                    }
                    let sg = c.sugarGramsFromNutrients
                    if sg > 0 {
                        sumSugar += sg
                        anySugar = true
                    }
                }
                await HealthKitManager.shared.saveNutritionFromMeal(
                    calories: sumCal,
                    proteinG: sumP,
                    carbG: sumC,
                    fatG: sumF,
                    fiberG: anyFiber ? sumFiber : nil,
                    sodiumMg: anySodium ? sumSodium : nil,
                    sugarG: anySugar ? sumSugar : nil,
                    date: input.loggedAt,
                    nutritionLogId: newLog.id
                )
            }

            await reloadLoadedLogsRange()

            return true
        } catch {
            errorMessage = error.localizedDescription
            print("Save meal error: \(error)")
            return false
        }
    }

    func updateLog(
        _ log: NutritionLogRow,
        loggedAt: Date,
        mealCategory: MealCategory,
        notes: String?,
        newGramsForSingleItem: Double?,
        newQuantityForSingleItem: Double?,
        syncToHealthKit: Bool
    ) async -> Bool {
        guard AuthManager.shared.session != nil else {
            errorMessage = "Not signed in"
            return false
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        struct LogPatch: Encodable {
            let logged_at: String
            let meal_type: String
            let notes: String?
        }

        struct ItemPatch: Encodable {
            let serving_amount: Double
            let serving_unit: String
            let grams: Double?
            let quantity: Double
            let calories: Double
            let protein_g: Double
            let carb_g: Double
            let fat_g: Double
            let fiber_g: Double?
            let sodium_mg: Double?
            let nutrients: [String: Double]?
        }

        let loggedAtStr = isoFormatter.string(from: loggedAt)
        let mealTypeStr = mealCategory.rawValue
        let notesTrimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesOut = notesTrimmed.flatMap { $0.isEmpty ? nil : $0 }

        do {
            try await client
                .from("nutrition_logs")
                .update(LogPatch(logged_at: loggedAtStr, meal_type: mealTypeStr, notes: notesOut))
                .eq("id", value: log.id)
                .execute()

            if let items = log.nutrition_log_items, items.count == 1, let item = items.first,
               newGramsForSingleItem != nil || newQuantityForSingleItem != nil
            {
                let oldG = max(item.grams ?? item.serving_amount, 1)
                let oldQty = max(item.quantity ?? 1, 0.01)
                let newQty = max(newQuantityForSingleItem ?? oldQty, 0.01)
                let newG = max(newGramsForSingleItem ?? oldG, 1)
                let factor = newG / oldG
                let scaledNutrients = item.nutrients.map { dict in
                    dict.mapValues { $0 * factor }
                }
                let patch = ItemPatch(
                    serving_amount: item.serving_amount * factor,
                    serving_unit: item.serving_unit,
                    grams: newG,
                    quantity: newQty,
                    calories: item.calories * factor,
                    protein_g: item.protein_g * factor,
                    carb_g: item.carb_g * factor,
                    fat_g: item.fat_g * factor,
                    fiber_g: item.fiber_g.map { $0 * factor },
                    sodium_mg: item.sodium_mg.map { $0 * factor },
                    nutrients: scaledNutrients
                )
                try await client
                    .from("nutrition_log_items")
                    .update(patch)
                    .eq("id", value: item.id)
                    .execute()
            }

            await reloadLoadedLogsRange()

            if syncToHealthKit {
                await HealthKitManager.shared.deleteNutritionSamplesForLog(nutritionLogId: log.id)
                if let refreshed = logs.first(where: { $0.id == log.id }) {
                    await syncHealthKitAggregated(for: refreshed, date: loggedAt)
                }
            }

            return true
        } catch {
            errorMessage = error.localizedDescription
            print("Update meal error: \(error)")
            return false
        }
    }

    /// Updates one line item’s portion and rescales macros; optionally refreshes aggregated Apple Health for the parent log.
    func updateLogLineItem(
        log: NutritionLogRow,
        itemId: UUID,
        newGrams: Double,
        newQuantity: Double,
        syncToHealthKit: Bool
    ) async -> Bool {
        guard AuthManager.shared.session != nil else {
            errorMessage = "Not signed in"
            return false
        }
        guard let items = log.nutrition_log_items, let item = items.first(where: { $0.id == itemId }) else {
            errorMessage = "Food line not found"
            return false
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        struct ItemPatch: Encodable {
            let serving_amount: Double
            let serving_unit: String
            let grams: Double?
            let quantity: Double
            let calories: Double
            let protein_g: Double
            let carb_g: Double
            let fat_g: Double
            let fiber_g: Double?
            let sodium_mg: Double?
            let nutrients: [String: Double]?
        }

        let oldG = max(item.grams ?? item.serving_amount, 1)
        let newG = max(newGrams, 1)
        let factor = newG / oldG
        let newQty = max(newQuantity, 0.01)
        let scaledNutrients = item.nutrients.map { dict in
            dict.mapValues { $0 * factor }
        }
        let patch = ItemPatch(
            serving_amount: item.serving_amount * factor,
            serving_unit: item.serving_unit,
            grams: newG,
            quantity: newQty,
            calories: item.calories * factor,
            protein_g: item.protein_g * factor,
            carb_g: item.carb_g * factor,
            fat_g: item.fat_g * factor,
            fiber_g: item.fiber_g.map { $0 * factor },
            sodium_mg: item.sodium_mg.map { $0 * factor },
            nutrients: scaledNutrients
        )

        do {
            try await client
                .from("nutrition_log_items")
                .update(patch)
                .eq("id", value: itemId)
                .execute()

            await reloadLoadedLogsRange()

            if syncToHealthKit {
                await HealthKitManager.shared.deleteNutritionSamplesForLog(nutritionLogId: log.id)
                if let refreshed = logs.first(where: { $0.id == log.id }) {
                    await syncHealthKitAggregated(for: refreshed, date: refreshed.logged_at)
                }
            }

            return true
        } catch {
            errorMessage = error.localizedDescription
            print("Update line item error: \(error)")
            return false
        }
    }

    private func syncHealthKitAggregated(for log: NutritionLogRow, date: Date) async {
        var sumCal = 0.0, sumP = 0.0, sumC = 0.0, sumF = 0.0
        var sumFiber: Double = 0
        var sumSodium: Double = 0
        var sumSugar: Double = 0
        var anyFiber = false
        var anySodium = false
        var anySugar = false
        for c in log.nutrition_log_items ?? [] {
            sumCal += c.calories
            sumP += c.protein_g
            sumC += c.carb_g
            sumF += c.fat_g
            if let f = c.fiber_g {
                sumFiber += f
                anyFiber = true
            }
            if let na = c.sodium_mg {
                sumSodium += na
                anySodium = true
            }
            let sg = c.sugarGramsFromNutrients
            if sg > 0 {
                sumSugar += sg
                anySugar = true
            }
        }
        await HealthKitManager.shared.saveNutritionFromMeal(
            calories: sumCal,
            proteinG: sumP,
            carbG: sumC,
            fatG: sumF,
            fiberG: anyFiber ? sumFiber : nil,
            sodiumMg: anySodium ? sumSodium : nil,
            sugarG: anySugar ? sumSugar : nil,
            date: date,
            nutritionLogId: log.id
        )
    }

    func deleteLog(id: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        await HealthKitManager.shared.deleteNutritionSamplesForLog(nutritionLogId: id)
        do {
            try await client
                .from("nutrition_logs")
                .delete()
                .eq("id", value: id)
                .execute()
            await reloadLoadedLogsRange()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Totals for the currently loaded logs (one calendar day when using the Nutrition tab day picker).
    var loadedDayNutritionTotals: NutritionDayTotals {
        var totals = NutritionDayTotals()
        for log in logs {
            guard log.status == "confirmed" else { continue }
            for item in log.nutrition_log_items ?? [] {
                totals.calories += item.calories
                totals.protein_g += item.protein_g
                totals.carb_g += item.carb_g
                totals.fat_g += item.fat_g
                totals.sugar_g += item.sugarGramsFromNutrients
                totals.sodium_mg += item.sodium_mg ?? 0
            }
        }
        return totals
    }

    /// Legacy tuple used by the current Nutrition summary UI.
    var loadedDayTotals: (calories: Double, protein: Double, carbs: Double, fat: Double, sugar: Double, sodium: Double) {
        let totals = loadedDayNutritionTotals
        return (
            totals.calories,
            totals.protein_g,
            totals.carb_g,
            totals.fat_g,
            totals.sugar_g,
            totals.sodium_mg
        )
    }

    /// Percent of calories from each macro (4/4/9 kcal per gram). Nil components when calories are zero.
    func macroPercentOfCalories(
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double
    ) -> (protein: Double?, carbs: Double?, fat: Double?) {
        guard calories > 0 else { return (nil, nil, nil) }
        let pp = 100 * 4 * protein / calories
        let pc = 100 * 4 * carbs / calories
        let pf = 100 * 9 * fat / calories
        return (pp, pc, pf)
    }
}
