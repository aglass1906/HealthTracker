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
    var calories: Double
    var protein_g: Double
    var carb_g: Double
    var fat_g: Double
    var fiber_g: Double?
    var sodium_mg: Double?
    var fdc_id: Int64?
    var external_product_id: String?
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

    func scaled(gramsEaten: Double) -> FoodCandidateDTO {
        let base = grams ?? 100
        guard base > 0 else { return self }
        let factor = gramsEaten / base
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
            external_product_id: external_product_id
        )
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
