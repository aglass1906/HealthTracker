//
//  HealthDataModels.swift
//  HealthTracker
//
//  Created by Alan Glass on 12/29/25.
//

import Foundation
import HealthKit

// MARK: - Activity Rings

struct ActivityRings: Codable, Equatable {
    let move: RingData
    let exercise: RingData
    let stand: RingData
}

struct RingData: Codable, Equatable {
    let value: Double
    let goal: Double
    let progress: Double
}

// MARK: - Workout Data

struct WorkoutData: Identifiable, Codable, Equatable {
    let id: String
    let workoutType: String
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let totalEnergyBurned: Double?
    let totalDistance: Double?
    
    init(from workout: HKWorkout) {
        self.id = workout.uuid.uuidString
        self.workoutType = workout.workoutActivityType.name
        self.startDate = workout.startDate
        self.endDate = workout.endDate
        self.duration = workout.duration
        if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            self.totalEnergyBurned = workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie())
        } else {
            self.totalEnergyBurned = nil
        }
        self.totalDistance = workout.totalDistance?.doubleValue(for: HKUnit.meter())
    }
    
    init(id: String, workoutType: String, startDate: Date, endDate: Date, duration: TimeInterval, totalEnergyBurned: Double?, totalDistance: Double?) {
        self.id = id
        self.workoutType = workoutType
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
        self.totalEnergyBurned = totalEnergyBurned
        self.totalDistance = totalDistance
    }
}

// MARK: - Daily Health Data

struct DailyHealthData: Identifiable, Codable, Equatable {
    let id: String
    let date: Date
    let steps: Double
    let flights: Double
    let calories: Double
    var distance: Double? // Added optional
    var activityRings: ActivityRings?
    var workouts: [WorkoutData]
    
    init(date: Date, steps: Double, flights: Double, calories: Double, distance: Double? = nil, activityRings: ActivityRings? = nil, workouts: [WorkoutData] = []) {
        self.id = date.formatted(date: .numeric, time: .omitted)
        self.date = date
        self.steps = steps
        self.flights = flights
        self.calories = calories
        self.distance = distance
        self.activityRings = activityRings
        self.workouts = workouts
    }
}

// MARK: - Health Summary

struct HealthSummary: Codable {
    let startDate: Date
    let endDate: Date
    let totalSteps: Double
    let totalFlights: Double
    let totalCalories: Double
    let totalWorkouts: Int
    let averageSteps: Double
    let averageFlights: Double
    let averageCalories: Double
    let dailyData: [DailyHealthData]
    
    init(startDate: Date, endDate: Date, dailyData: [DailyHealthData]) {
        self.startDate = startDate
        self.endDate = endDate
        self.dailyData = dailyData
        
        self.totalSteps = dailyData.reduce(0) { $0 + $1.steps }
        self.totalFlights = dailyData.reduce(0) { $0 + $1.flights }
        self.totalCalories = dailyData.reduce(0) { $0 + $1.calories }
        self.totalWorkouts = dailyData.reduce(0) { $0 + $1.workouts.count }
        
        let dayCount = max(1, dailyData.count)
        self.averageSteps = self.totalSteps / Double(dayCount)
        self.averageFlights = self.totalFlights / Double(dayCount)
        self.averageCalories = self.totalCalories / Double(dayCount)
    }
}

// MARK: - HKWorkoutActivityType Extension

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .yoga: return "Yoga"
        case .traditionalStrengthTraining: return "Strength Training"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .tennis: return "Tennis"
        case .basketball: return "Basketball"
        case .soccer: return "Soccer"
        case .americanFootball: return "American Football"
        case .baseball: return "Baseball"
        case .crossTraining: return "Cross Training"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stair Climbing"
        case .dance: return "Dance"
        case .golf: return "Golf"
        case .highIntensityIntervalTraining: return "HIIT"
        case .functionalStrengthTraining: return "Functional Strength"
        case .coreTraining: return "Core Training"
        case .cooldown: return "Cooldown"
        case .mindAndBody: return "Mind & Body"
        case .flexibility: return "Flexibility"
        case .barre: return "Barre"
        case .pilates: return "Pilates"
        case .jumpRope: return "Jump Rope"
        case .kickboxing: return "Kickboxing"
        case .boxing: return "Boxing"
        case .martialArts: return "Martial Arts"
        case .taiChi: return "Tai Chi"
        case .wrestling: return "Wrestling"
        
        // Sports
        case .pickleball: return "Pickleball"
        case .tableTennis: return "Table Tennis"
        case .racquetball: return "Racquetball"
        case .squash: return "Squash"
        case .badminton: return "Badminton"
        case .volleyball: return "Volleyball"
        case .handball: return "Handball"
        case .lacrosse: return "Lacrosse"
        case .rugby: return "Rugby"
        case .softball: return "Softball"
        case .trackAndField: return "Track & Field"
        case .gymnastics: return "Gymnastics"
        case .bowling: return "Bowling"
        case .fencing: return "Fencing"
        
        // Water
        case .waterFitness: return "Water Fitness"
        case .waterPolo: return "Water Polo"
        case .surfingSports: return "Surfing"
        case .sailing: return "Sailing"
        
        // Cardio / Other
        case .stepTraining: return "Step Training"
        case .cardioDance: return "Cardio Dance"
        case .socialDance: return "Social Dance"
        case .stairs: return "Stairs"
        case .wheelchairWalkPace: return "Wheelchair Walk"
        case .wheelchairRunPace: return "Wheelchair Run"
        
        default: return "Workout"
        }
    }
}

struct DailyHealthGoals {
    static let steps = 10_000
    static let calories = 600
    static let flights = 10
    static let distance = 8000.0 // meters
    static let exerciseMinutes = 30
    static let workouts = 1
}



// MARK: - User Profile

struct Profile: Codable, Identifiable {
    let id: UUID
    let email: String?
    let display_name: String?
    let avatar_url: String?
    let family_id: UUID?
    let is_admin: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case display_name
        case avatar_url
        case family_id
        case is_admin
    }
}
