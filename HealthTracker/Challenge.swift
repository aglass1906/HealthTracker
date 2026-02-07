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
    let round_duration: String?
    let current_round_number: Int?
    let total_rounds: Int?
    
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
    
    var roundDuration: RoundDuration? {
        guard let durationString = round_duration else { return nil }
        return RoundDuration(rawValue: durationString)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, family_id, creator_id, title, description, type, metric, target_value, status, created_at
        case start_date_string = "start_date"
        case end_date_string = "end_date"
        case round_duration, current_round_number, total_rounds
    }
    
    // Helper to check if active
    var isActive: Bool {
        return status == .active
    }
}

enum ChallengeType: String, Codable, CaseIterable {
    case race      // First to X
    case streak    // Daily Goal Streak
    case count     // Most X by End Date
    
    var icon: String {
        switch self {
        case .race: return "flag.checkered"
        case .streak: return "flame.fill"
        case .count: return "chart.bar.fill"
        }
    }
    
    var title: String {
        switch self {
        case .race: return "Race"
        case .streak: return "Streak"
        case .count: return "Leaderboard"
        }
    }
}

enum ChallengeMetric: String, Codable, CaseIterable {
    case steps
    case calories
    case distance
    case exercise_minutes
    case flights
    case workouts
    
    var displayName: String {
        switch self {
        case .steps: return "Steps"
        case .calories: return "Calories"
        case .distance: return "Distance"
        case .exercise_minutes: return "Exercise Minutes"
        case .flights: return "Flights"
        case .workouts: return "Workouts"
        }
    }
    
    var unit: String {
        switch self {
        case .steps: return "steps"
        case .calories: return "kcal"
        case .distance: return "km"
        case .exercise_minutes: return "mins"
        case .flights: return "floors"
        case .workouts: return "workouts"
        }
    }
    
    var icon: String {
        switch self {
        case .steps: return "figure.walk"
        case .calories: return "flame.fill"
        case .distance: return "figure.run"
        case .exercise_minutes: return "clock.fill"
        case .flights: return "stairs"
        case .workouts: return "dumbbell.fill"
        }
    }
}

enum ChallengeStatus: String, Codable {
    case active
    case completed
    case cancelled
}

enum RoundDuration: String, Codable, CaseIterable {
    case daily
    case weekly
    case monthly
    
    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

struct ChallengeRound: Identifiable, Codable {
    let id: UUID
    let challenge_id: UUID
    let round_number: Int
    let start_date_string: String
    let end_date_string: String
    let winner_id: UUID?
    let status: String
    let created_at: Date
    
    var start_date: Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: start_date_string) ?? 
               ISO8601DateFormatter().date(from: start_date_string) ?? 
               Date()
    }
    
    var end_date: Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: end_date_string) ?? 
               ISO8601DateFormatter().date(from: end_date_string) ?? 
               Date()
    }
    
    enum CodingKeys: String, CodingKey {
        case id, challenge_id, round_number, winner_id, status, created_at
        case start_date_string = "start_date"
        case end_date_string = "end_date"
    }
}

struct RoundParticipant: Identifiable, Codable {
    let id: UUID
    let round_id: UUID
    let user_id: UUID
    let value: Double
    let rank: Int?
    let created_at: Date
}
