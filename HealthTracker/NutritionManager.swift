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
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let functionName = "food-lookup"
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {}

    private var client: SupabaseClient { AuthManager.shared.client }

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
                .select("id, user_id, logged_at, meal_type, source, barcode_raw, photo_path, status, created_at, nutrition_log_items(id, log_id, name, brand, serving_amount, serving_unit, grams, calories, protein_g, carb_g, fat_g, fiber_g, sodium_mg, fdc_id, external_product_id)")
                .eq("user_id", value: uid)
                .gte("logged_at", value: startS)
                .lte("logged_at", value: endS)
                .order("logged_at", ascending: false)
                .execute()
                .value
            logs = rows
        } catch {
            errorMessage = error.localizedDescription
            print("Nutrition load error: \(error)")
        }
    }

    func lookupBarcode(_ code: String) async -> FoodLookupResponse? {
        await invokeLookup(FoodLookupRequest(mode: "barcode", barcode: code, imageBase64: nil, mimeType: nil, query: nil))
    }

    func lookupSearch(_ query: String) async -> FoodLookupResponse? {
        await invokeLookup(FoodLookupRequest(mode: "search", barcode: nil, imageBase64: nil, mimeType: nil, query: query))
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
            // `client.auth.session` refreshes when needed; `AuthManager.session` can be expired (Edge returns Invalid JWT).
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

    struct MealSaveInput {
        var source: String
        var mealType: String?
        var barcodeRaw: String?
        var photoJPEG: Data?
        var loggedAt: Date
        var candidate: FoodCandidateDTO
    }

    func saveMeal(_ input: MealSaveInput, syncToHealthKit: Bool) async -> Bool {
        guard let session = AuthManager.shared.session else {
            errorMessage = "Not signed in"
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
        }

        struct ItemInsert: Encodable {
            let log_id: UUID
            let name: String
            let brand: String?
            let serving_amount: Double
            let serving_unit: String
            let grams: Double?
            let calories: Double
            let protein_g: Double
            let carb_g: Double
            let fat_g: Double
            let fiber_g: Double?
            let sodium_mg: Double?
            let fdc_id: Int64?
            let external_product_id: String?
        }

        let loggedAtStr = isoFormatter.string(from: input.loggedAt)

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
                        status: "confirmed"
                    )
                )
                .select("id, user_id, logged_at, meal_type, source, barcode_raw, photo_path, status, created_at")
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

            let c = input.candidate
            let item = ItemInsert(
                log_id: newLog.id,
                name: c.name,
                brand: c.brand,
                serving_amount: c.serving_amount,
                serving_unit: c.serving_unit,
                grams: c.grams,
                calories: c.calories,
                protein_g: c.protein_g,
                carb_g: c.carb_g,
                fat_g: c.fat_g,
                fiber_g: c.fiber_g,
                sodium_mg: c.sodium_mg,
                fdc_id: c.fdc_id,
                external_product_id: c.external_product_id
            )

            try await client
                .from("nutrition_log_items")
                .insert(item)
                .execute()

            if syncToHealthKit {
                await HealthKitManager.shared.saveNutritionFromMeal(
                    calories: c.calories,
                    proteinG: c.protein_g,
                    carbG: c.carb_g,
                    fatG: c.fat_g,
                    fiberG: c.fiber_g,
                    sodiumMg: c.sodium_mg,
                    date: input.loggedAt
                )
            }

            let cal = Calendar.current
            let start = cal.startOfDay(for: Date())
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
            await loadLogs(from: start, to: end)

            return true
        } catch {
            errorMessage = error.localizedDescription
            print("Save meal error: \(error)")
            return false
        }
    }

    /// Updates log time/meal type; for a single line item, rescales macros from a new gram amount.
    /// Does not modify Apple Health (samples are not tied to log ids).
    func updateLog(
        _ log: NutritionLogRow,
        loggedAt: Date,
        mealCategory: MealCategory,
        newGramsForSingleItem: Double?
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
        }

        struct ItemPatch: Encodable {
            let serving_amount: Double
            let serving_unit: String
            let grams: Double?
            let calories: Double
            let protein_g: Double
            let carb_g: Double
            let fat_g: Double
            let fiber_g: Double?
            let sodium_mg: Double?
        }

        let loggedAtStr = isoFormatter.string(from: loggedAt)
        let mealTypeStr = mealCategory.rawValue

        do {
            try await client
                .from("nutrition_logs")
                .update(LogPatch(logged_at: loggedAtStr, meal_type: mealTypeStr))
                .eq("id", value: log.id)
                .execute()

            if let items = log.nutrition_log_items, items.count == 1, let item = items.first,
               let newG = newGramsForSingleItem
            {
                let oldG = max(item.grams ?? item.serving_amount, 1)
                let factor = newG / oldG
                let patch = ItemPatch(
                    serving_amount: item.serving_amount * factor,
                    serving_unit: item.serving_unit,
                    grams: newG,
                    calories: item.calories * factor,
                    protein_g: item.protein_g * factor,
                    carb_g: item.carb_g * factor,
                    fat_g: item.fat_g * factor,
                    fiber_g: item.fiber_g.map { $0 * factor },
                    sodium_mg: item.sodium_mg.map { $0 * factor }
                )
                try await client
                    .from("nutrition_log_items")
                    .update(patch)
                    .eq("id", value: item.id)
                    .execute()
            }

            let cal = Calendar.current
            let start = cal.startOfDay(for: Date())
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
            await loadLogs(from: start, to: end)

            return true
        } catch {
            errorMessage = error.localizedDescription
            print("Update meal error: \(error)")
            return false
        }
    }

    func deleteLog(id: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await client
                .from("nutrition_logs")
                .delete()
                .eq("id", value: id)
                .execute()
            let cal = Calendar.current
            let start = cal.startOfDay(for: Date())
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
            await loadLogs(from: start, to: end)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Today's totals across all items in loaded logs (caller should load today's range first).
    var todayTotals: (calories: Double, protein: Double, carbs: Double, fat: Double) {
        var cal = 0.0, p = 0.0, c = 0.0, f = 0.0
        for log in logs {
            guard log.status == "confirmed" else { continue }
            for item in log.nutrition_log_items ?? [] {
                cal += item.calories
                p += item.protein_g
                c += item.carb_g
                f += item.fat_g
            }
        }
        return (cal, p, c, f)
    }
}
