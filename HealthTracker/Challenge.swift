//
//  Challenge.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/4/26.
//

import Foundation

struct Challenge: Identifiable, Codable {
    let id: UUID
    let family_id: UUID
    let creator_id: UUID
    let title: String
    let description: String?
    let type: ChallengeType
    let metric: ChallengeMetric
    let target_value: Int
    let start_date_string: String
    let end_date_string: String?
    let status: ChallengeStatus
    let created_at: Date
    
    // Computed props to expose Dates to the app
    var start_date: Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: start_date_string) ?? 
               ISO8601DateFormatter().date(from: start_date_string) ?? 
               Date()
    }
    
    var end_date: Date? {
        guard let dateString = end_date_string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: dateString) ??
               ISO8601DateFormatter().date(from: dateString)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, family_id, creator_id, title, description, type, metric, target_value, status, created_at
        case start_date_string = "start_date"
        case end_date_string = "end_date"
    }
    
    // Helper to check if active
    var isActive: Bool {
        return status == .active
    }
}

enum ChallengeType: String, Codable, CaseIterable {
    case race      // First to X
    case streak    // Daily Goal Streak
    
    var icon: String {
        switch self {
        case .race: return "flag.checkered"
        case .streak: return "flame.fill"
        }
    }
    
    var title: String {
        switch self {
        case .race: return "Race"
        case .streak: return "Streak"
        }
    }
}

enum ChallengeMetric: String, Codable, CaseIterable {
    case steps
    case calories
    case distance
    case exercise_minutes
    
    var displayName: String {
        switch self {
        case .steps: return "Steps"
        case .calories: return "Calories"
        case .distance: return "Distance (mi)"
        case .exercise_minutes: return "Exercise (min)"
        }
    }
    
    var unit: String {
        switch self {
        case .steps: return "steps"
        case .calories: return "kcal"
        case .distance: return "miles"
        case .exercise_minutes: return "mins"
        }
    }
    
    var icon: String {
        switch self {
        case .steps: return "figure.walk"
        case .calories: return "flame"
        case .distance: return "map"
        case .exercise_minutes: return "figure.run"
        }
    }
}

enum ChallengeStatus: String, Codable {
    case active
    case completed
    case cancelled
}
