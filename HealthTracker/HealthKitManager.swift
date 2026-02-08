//
//  HealthKitManager.swift
//  HealthTracker
//
//  Created by Alan Glass on 12/29/25.
//

import Foundation
import HealthKit
import Combine

@MainActor
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    
    private let healthStore = HKHealthStore()
    
    @Published var isAuthorized = false
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined
    
    private let hasRequestedAuthKey = "healthTracker_hasRequestedAuth"
    
    var hasRequestedAuthorization: Bool {
        get { UserDefaults.standard.bool(forKey: hasRequestedAuthKey) }
        set { 
            UserDefaults.standard.set(newValue, forKey: hasRequestedAuthKey)
            checkAuthorizationStatus()
        }
    }
    
    // Health data types we want to read
    private let readTypes: Set<HKObjectType> = {
        guard let stepCount = HKObjectType.quantityType(forIdentifier: .stepCount),
              let flightsClimbed = HKObjectType.quantityType(forIdentifier: .flightsClimbed),
              let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
              let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) else {
            return []
        }
        let workoutType = HKObjectType.workoutType()
        return [stepCount, flightsClimbed, activeEnergy, distance, workoutType]
    }()
    
    private init() {
        checkAuthorizationStatus()
    }
    
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        
        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
        hasRequestedAuthorization = true
    }
    
    func checkAuthorizationStatus() {
        // For read-only access, HealthKit does not allow us to check if permission was granted.
        // We rely on whether we have requested authorization.
        isAuthorized = hasRequestedAuthorization
        
        if isAuthorized {
            startObservingHealthData()
        }
        
        // We still fetch the status, but it will likely remain .notDetermined for read-only types
        if let stepCount = HKObjectType.quantityType(forIdentifier: .stepCount) {
            authorizationStatus = healthStore.authorizationStatus(for: stepCount)
        }
    }
    
    func clearAuthorizationState() {
        // Note: HealthKit doesn't allow programmatic revocation
        // This clears our local state. Users must revoke in iOS Settings
        hasRequestedAuthorization = false
        isAuthorized = false
        authorizationStatus = .notDetermined
    }
    
    // MARK: - Background Delivery
    
    func startObservingHealthData() {
        guard isAuthorized else { return }
        
        let typesToObserve: [(HKSampleType, HKUpdateFrequency)] = [
            (HKObjectType.quantityType(forIdentifier: .stepCount)!, .hourly),
            (HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!, .hourly),
            (HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!, .hourly),
            (HKObjectType.quantityType(forIdentifier: .flightsClimbed)!, .hourly),
            (HKObjectType.workoutType(), .immediate)
        ]
        
        for (type, frequency) in typesToObserve {
            // 1. Enable Background Delivery
            healthStore.enableBackgroundDelivery(for: type, frequency: frequency) { success, error in
                if let error = error {
                    print("❌ Failed to enable background delivery for \(type.identifier): \(error.localizedDescription)")
                } else {
                    print("✅ Background delivery enabled for \(type.identifier) at \(frequency == .immediate ? "immediate" : "hourly") frequency")
                }
            }
            
            // 2. Execute Observer Query
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] query, completionHandler, error in
                if let error = error {
                    print("❌ Observer query failed for \(type.identifier): \(error.localizedDescription)")
                    completionHandler()
                    return
                }
                
                print("🔄 HealthKit update received for \(type.identifier)")
                
                // Trigger background sync
                // Use DispatchQueue to avoid Task overhead for high-frequency updates
                DispatchQueue.main.async {
                    BackgroundTaskManager.shared.handleHealthKitUpdate {
                        completionHandler()
                    }
                }
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Fetch Today's Data
    
    func fetchTodaySteps() async throws -> Double {
        guard let stepCountType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitError.invalidType
        }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: [] // Relaxed from .strictStartDate
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepCountType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    // Don't throw on "No Data" or other query errors, just return 0
                    print("Step fetch error (safe to ignore if no data): \(error.localizedDescription)")
                    continuation.resume(returning: 0)
                    return
                }
                
                let steps = result?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                continuation.resume(returning: steps)
            }
            
            healthStore.execute(query)
        }
    }
    
    func fetchTodayFlights() async throws -> Double {
        guard let flightsType = HKObjectType.quantityType(forIdentifier: .flightsClimbed) else {
            throw HealthKitError.invalidType
        }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: [] // Relaxed from .strictStartDate
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: flightsType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    print("Flight fetch error (safe to ignore if no data): \(error.localizedDescription)")
                    continuation.resume(returning: 0)
                    return
                }
                
                let flights = result?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                continuation.resume(returning: flights)
            }
            
            healthStore.execute(query)
        }
    }
    
    func fetchTodayCalories() async throws -> Double {
        guard let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthKitError.invalidType
        }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: [] // Relaxed from .strictStartDate
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: activeEnergyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    print("Calorie fetch error (safe to ignore if no data): \(error.localizedDescription)")
                    continuation.resume(returning: 0)
                    return
                }
                
                let calories = result?.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) ?? 0
                continuation.resume(returning: calories)
            }
            
            healthStore.execute(query)
        }
    }
    
    func fetchTodayDistance() async throws -> Double {
        guard let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) else {
            throw HealthKitError.invalidType
        }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: []
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: distanceType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    print("Distance fetch error (safe to ignore): \(error.localizedDescription)")
                    continuation.resume(returning: 0)
                    return
                }
                
                // Return in meters
                let distance = result?.sumQuantity()?.doubleValue(for: HKUnit.meter()) ?? 0
                continuation.resume(returning: distance)
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Activity Rings
    
    func fetchActivityRings(for date: Date = Date()) async throws -> ActivityRings {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        // Fetch active energy (Move ring - Red)
        let activeEnergy = try await fetchCalories(for: startOfDay, end: endOfDay)
        let moveGoal: Double = 600 // Default goal, can be customized
        let moveProgress = min(activeEnergy / moveGoal, 1.0)
        
        // Fetch exercise minutes (Exercise ring - Green)
        let exerciseMinutes = try await fetchExerciseMinutes(for: startOfDay, end: endOfDay)
        let exerciseGoal: Double = 30 // Default 30 minutes
        let exerciseProgress = min(exerciseMinutes / exerciseGoal, 1.0)
        
        // Fetch stand hours (Stand ring - Blue)
        let standHours = try await fetchStandHours(for: startOfDay, end: endOfDay)
        let standGoal: Double = 12 // Default 12 hours
        let standProgress = min(standHours / standGoal, 1.0)
        
        return ActivityRings(
            move: RingData(value: activeEnergy, goal: moveGoal, progress: moveProgress),
            exercise: RingData(value: exerciseMinutes, goal: exerciseGoal, progress: exerciseProgress),
            stand: RingData(value: standHours, goal: standGoal, progress: standProgress)
        )
    }
    
    private func fetchCalories(for start: Date, end: Date) async throws -> Double {
        guard let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthKitError.invalidType
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: activeEnergyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    print("Calorie fetch error (safe to ignore if no data): \(error.localizedDescription)")
                    continuation.resume(returning: 0)
                    return
                }
                let calories = result?.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) ?? 0
                continuation.resume(returning: calories)
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchExerciseMinutes(for start: Date, end: Date) async throws -> Double {
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: 50, // Limit to reasonable count to avoid OOM
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let workouts = samples as? [HKWorkout] ?? []
                let totalMinutes = workouts.reduce(0.0) { total, workout in
                    total + workout.duration / 60.0
                }
                continuation.resume(returning: totalMinutes)
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchStandHours(for start: Date, end: Date) async throws -> Double {
        // Stand hours are typically tracked by Apple Watch
        // For devices without watch, we'll estimate based on step activity
        let steps = try await fetchSteps(for: start, end: end)
        // Estimate: if user has significant steps throughout the day, count as stand hours
        // This is a simplified approach - real implementation would use HKCategoryTypeIdentifierAppleStandHour
        let estimatedStandHours = min(12.0, steps / 1000.0) // Rough estimate
        return estimatedStandHours
    }
    
    private func fetchSteps(for start: Date, end: Date) async throws -> Double {
        guard let stepCountType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitError.invalidType
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepCountType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    print("Step fetch error (safe to ignore if no data): \(error.localizedDescription)")
                    continuation.resume(returning: 0)
                    return
                }
                let steps = result?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                continuation.resume(returning: steps)
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - Workouts
    
    func fetchTodayWorkouts() async throws -> [WorkoutData] {
        let workoutType = HKObjectType.workoutType()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: [] // Relaxed from .strictStartDate
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: 50, // Limit to 50 workouts per day (safety cap)
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let workouts = (samples as? [HKWorkout] ?? []).map { workout in
                    WorkoutData(from: workout)
                }
                continuation.resume(returning: workouts)
            }
            
            healthStore.execute(query)
        }
    }
    
    func fetchWorkouts(from startDate: Date, to endDate: Date) async throws -> [WorkoutData] {
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate // Keeping strict for explicit ranges unless issues arise
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let workouts = (samples as? [HKWorkout] ?? []).map { workout in
                    WorkoutData(from: workout)
                }
                continuation.resume(returning: workouts)
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Date Range Queries
    
    func fetchStepsForDateRange(from startDate: Date, to endDate: Date) async throws -> [DailyHealthData] {
        guard let stepCountType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitError.invalidType
        }
        
        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        var results: [DailyHealthData] = []
        
        while currentDate <= end {
            let dayStart = currentDate
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            
            let predicate = HKQuery.predicateForSamples(
                withStart: dayStart,
                end: dayEnd,
                options: [] // Relaxed from .strictStartDate
            )
            
            let steps = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double, Error>) in
                let query = HKStatisticsQuery(
                    quantityType: stepCountType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum
                ) { _, result, error in
                    if let error = error {
                        print("Step range fetch error: \(error.localizedDescription)")
                        continuation.resume(returning: 0) // Safe default
                        return
                    }
                    let steps = result?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                    continuation.resume(returning: steps)
                }
                healthStore.execute(query)
            }
            
            results.append(DailyHealthData(date: dayStart, steps: steps, flights: 0, calories: 0))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return results
    }
    
    func fetchHealthDataForDateRange(from startDate: Date, to endDate: Date) async throws -> [DailyHealthData] {
        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        var results: [DailyHealthData] = []
        
        while currentDate <= end {
            let dayStart = currentDate
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            
            async let steps = fetchSteps(for: dayStart, end: dayEnd)
            async let flights = fetchFlights(for: dayStart, end: dayEnd)
            async let calories = fetchCalories(for: dayStart, end: dayEnd)
            
            let (stepsValue, flightsValue, caloriesValue) = try await (steps, flights, calories)
            
            results.append(DailyHealthData(
                date: dayStart,
                steps: stepsValue,
                flights: flightsValue,
                calories: caloriesValue
            ))
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return results
    }
    
    private func fetchFlights(for start: Date, end: Date) async throws -> Double {
        guard let flightsType = HKObjectType.quantityType(forIdentifier: .flightsClimbed) else {
            throw HealthKitError.invalidType
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: flightsType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    print("Flight fetch error (safe to ignore if no data): \(error.localizedDescription)")
                    continuation.resume(returning: 0)
                    return
                }
                let flights = result?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                continuation.resume(returning: flights)
            }
            healthStore.execute(query)
        }
    }
}

enum HealthKitError: LocalizedError {
    case notAvailable
    case invalidType
    case authorizationDenied
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .invalidType:
            return "Invalid health data type"
        case .authorizationDenied:
            return "Health data access was denied"
        }
    }
}
