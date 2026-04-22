//
//  NutritionModels.swift
//  HealthTracker
//

import Foundation

enum MealCategory: String, CaseIterable, Identifiable, Sendable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snack = "Snack"

    var id: String { rawValue }

    static func defaultForCurrentTime() -> MealCategory {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5 ..< 10: return .breakfast
        case 10 ..< 15: return .lunch
        case 15 ..< 21: return .dinner
        default: return .snack
        }
    }
}

struct NutritionLogRow: Codable, Identifiable, Hashable {
    let id: UUID
    let user_id: UUID
    let logged_at: Date
    var meal_type: String?
    let source: String
    var barcode_raw: String?
    var photo_path: String?
    var status: String
    let created_at: Date
    var notes: String?
    var nutrition_log_items: [NutritionLogItemRow]?
}

struct NutritionLogItemRow: Codable, Identifiable, Hashable {
    let id: UUID
    let log_id: UUID
    var name: String
    var brand: String?
    var serving_amount: Double
    var serving_unit: String
    var grams: Double?
    /// Nil if row predates V1.1 migration; treat as 1.
    var quantity: Double?
    var calories: Double
    var protein_g: Double
    var carb_g: Double
    var fat_g: Double
    var fiber_g: Double?
    var sodium_mg: Double?
    var fdc_id: Int64?
    var external_product_id: String?
    var nutrients: [String: Double]?
    var combo_name: String?

    /// Sugar from `nutrients` JSON (e.g. food-lookup `sugars_g`). Zero when not provided.
    var sugarGramsFromNutrients: Double {
        Self.sugarGrams(from: nutrients)
    }

    static func sugarGrams(from nutrients: [String: Double]?) -> Double {
        guard let nutrients, !nutrients.isEmpty else { return 0 }
        let directKeys = ["sugars_g", "Sugar", "Total Sugars", "sugars"]
        for k in directKeys {
            if let v = nutrients[k] { return max(0, v) }
        }
        for (k, v) in nutrients where k.localizedCaseInsensitiveContains("sugar") {
            return max(0, v)
        }
        return 0
    }
}

struct FoodCandidateDTO: Codable, Identifiable {
    var id: String {
        "\(name)-\(brand ?? "")-\(fdc_id.map(String.init) ?? "")-\(external_product_id ?? "")"
    }
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
    var household_serving_text: String?
    var nutrients_extra: [String: Double]?
    var image_url: String?
    var source: String?

    func scaled(gramsEaten: Double) -> FoodCandidateDTO {
        let base = grams ?? 100
        guard base > 0 else { return self }
        let factor = gramsEaten / base
        let scaledExtra = nutrients_extra.map { dict in
            dict.mapValues { $0 * factor }
        }
        return FoodCandidateDTO(
            name: name,
            brand: brand,
            serving_amount: serving_amount * factor,
            serving_unit: serving_unit,
            grams: gramsEaten,
            calories: calories * factor,
            protein_g: protein_g * factor,
            carb_g: carb_g * factor,
            fat_g: fat_g * factor,
            fiber_g: fiber_g.map { $0 * factor },
            sodium_mg: sodium_mg.map { $0 * factor },
            fdc_id: fdc_id,
            external_product_id: external_product_id,
            household_serving_text: household_serving_text,
            nutrients_extra: scaledExtra,
            image_url: image_url,
            source: source
        )
    }
}

extension FoodCandidateDTO {
    /// Favorite / confirm baseline from a saved line (per–quantity-1 macros and grams so scaling matches lookup flow).
    init(fromLoggedItem item: NutritionLogItemRow) {
        let qty = max(item.quantity ?? 1, 0.01)
        let totalG = max(item.grams ?? item.serving_amount, 1)
        let gPer = totalG / qty
        let nutrientsScaled = item.nutrients.map { dict in
            dict.mapValues { $0 / qty }
        }
        name = item.name
        brand = item.brand
        serving_amount = item.serving_amount
        serving_unit = item.serving_unit
        grams = gPer
        calories = item.calories / qty
        protein_g = item.protein_g / qty
        carb_g = item.carb_g / qty
        fat_g = item.fat_g / qty
        fiber_g = item.fiber_g.map { $0 / qty }
        sodium_mg = item.sodium_mg.map { $0 / qty }
        fdc_id = item.fdc_id
        external_product_id = item.external_product_id
        household_serving_text = nil
        nutrients_extra = nutrientsScaled
        image_url = nil
        source = nil
    }

    var sugarGramsFromNutrients: Double {
        NutritionLogItemRow.sugarGrams(from: nutrients_extra)
    }
}

struct FoodLookupResponse: Decodable {
    let candidates: [FoodCandidateDTO]
    let notice: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case candidates, notice, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        candidates = try c.decodeIfPresent([FoodCandidateDTO].self, forKey: .candidates) ?? []
        notice = try c.decodeIfPresent(String.self, forKey: .notice)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

struct FoodLookupRequest: Encodable {
    let mode: String
    var barcode: String?
    var imageBase64: String?
    var mimeType: String?
    var query: String?

    enum CodingKeys: String, CodingKey {
        case mode, barcode, query
        case imageBase64 = "image_base64"
        case mimeType = "mime_type"
    }
}

// MARK: - Local favorites (UserDefaults)

enum NutritionFavoritesStore {
    private static let key = "nutrition_favorite_candidates_v1"
    private static let maxCount = 40

    static func load() -> [FoodCandidateDTO] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([FoodCandidateDTO].self, from: data)
        else { return [] }
        return decoded
    }

    static func contains(id: String) -> Bool {
        load().contains { $0.id == id }
    }

    static func add(_ candidate: FoodCandidateDTO) {
        var list = load().filter { $0.id != candidate.id }
        list.insert(candidate, at: 0)
        if list.count > maxCount { list = Array(list.prefix(maxCount)) }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func remove(id: String) {
        let list = load().filter { $0.id != id }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func toggle(_ candidate: FoodCandidateDTO) {
        if contains(id: candidate.id) {
            remove(id: candidate.id)
        } else {
            add(candidate)
        }
    }
}

// MARK: - Combo / recipe models

struct ComboItem: Codable {
    var candidate: FoodCandidateDTO
    var quantity: Double
}

struct ComboFavorite: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var items: [ComboItem]
    var createdAt: Date = Date()
}

enum ComboFavoritesStore {
    private static let key = "nutrition_combo_favorites_v1"
    private static let maxCount = 20

    static func load() -> [ComboFavorite] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ComboFavorite].self, from: data)
        else { return [] }
        return decoded
    }

    private static func save(_ combos: [ComboFavorite]) {
        if let data = try? JSONEncoder().encode(combos) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func upsert(_ combo: ComboFavorite) {
        var list = load().filter { $0.id != combo.id }
        list.insert(combo, at: 0)
        if list.count > maxCount { list = Array(list.prefix(maxCount)) }
        save(list)
    }

    static func delete(_ id: UUID) {
        save(load().filter { $0.id != id })
    }
}
