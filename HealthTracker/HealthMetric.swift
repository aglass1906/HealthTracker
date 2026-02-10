//
//  HealthMetric.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/10/26.
//

import SwiftUI

enum HealthMetric: String, CaseIterable, Identifiable {
    case steps = "Steps"
    case calories = "Calories"
    case distance = "Distance"
    case flights = "Flights"
    case exercise = "Exercise"
    case workouts = "Workouts"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .steps: return "figure.walk"
        case .calories: return "flame.fill"
        case .distance: return "map.fill"
        case .flights: return "stairs"
        case .exercise: return "stopwatch"
        case .workouts: return "figure.run"
        }
    }
    
    var color: Color {
        switch self {
        case .steps: return .blue
        case .calories: return .orange
        case .distance: return .green
        case .flights: return .purple
        case .exercise: return .teal
        case .workouts: return .indigo
        }
    }
    
    var unit: String {
        switch self {
        case .steps: return "steps"
        case .calories: return "kcal"
        case .distance: return "m" // or km
        case .flights: return "flights"
        case .exercise: return "min"
        case .workouts: return "workouts"
        }
    }
    
    var displayName: String {
        switch self {
        case .exercise: return "Exercise Minutes"
        case .workouts: return "Workouts"
        default: return self.rawValue
        }
    }
    
    var databaseColumn: String {
        switch self {
        case .steps: return "steps"
        case .calories: return "calories"
        case .distance: return "distance"
        case .flights: return "flights"
        case .exercise: return "exercise_minutes"
        case .workouts: return "workouts_count"
        }
    }
}
