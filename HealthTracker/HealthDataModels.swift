//
//  HealthDataModels.swift
//  HealthTracker
//
//  Created by Alan Glass on 12/29/25.
//

import Foundation
import HealthKit

// MARK: - Activity Rings

struct ActivityRings: Codable {
    let move: RingData
    let exercise: RingData
    let stand: RingData
}

struct RingData: Codable {
    let value: Double
    let goal: Double
    let progress: Double
}

// MARK: - Workout Data

struct WorkoutData: Identifiable, Codable {
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

struct DailyHealthData: Identifiable, Codable {
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
        case .boxing: return "Boxing"
        case .martialArts: return "Martial Arts"
        case .pilates: return "Pilates"
        case .skatingSports: return "Skating"
        case .snowSports: return "Snow Sports"
        case .waterSports: return "Water Sports"
        default: return "Other"
        }
    }
}

