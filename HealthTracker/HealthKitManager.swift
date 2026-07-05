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
              let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
              let exerciseTime = HKObjectType.quantityType(forIdentifier: .appleExerciseTime),
              let standHour = HKObjectType.categoryType(forIdentifier: .appleStandHour) else {
            return []
        }
        let workoutType = HKObjectType.workoutType()
        let activitySummaryType = HKObjectType.activitySummaryType()
        return [stepCount, flightsClimbed, activeEnergy, distance, workoutType, activitySummaryType, exerciseTime, standHour]
    }()

    /// Nutrition logging (write) — energy and macros saved when user confirms a meal (optional in UI).
    private let shareNutritionTypes: Set<HKSampleType> = {
        let ids: [HKQuantityTypeIdentifier] = [
            .dietaryEnergyConsumed,
            .dietaryProtein,
            .dietaryCarbohydrates,
            .dietaryFatTotal,
            .dietaryFiber,
            .dietarySodium,
            .dietarySugar,
        ]
        var set = Set<HKSampleType>()
        for id in ids {
            if let t = HKObjectType.quantityType(forIdentifier: id) {
                set.insert(t)
            }
        }
        return set
    }()
    
    private init() {
        checkAuthorizationStatus()
    }
    
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        
        try await healthStore.requestAuthorization(toShare: shareNutritionTypes, read: readTypes)
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

    /// True once observer queries have been registered; prevents duplicate
    /// HKObserverQuery registration when authorization is re-checked.
    private var isObservingHealthData = false

    func startObservingHealthData() {
        guard isAuthorized else { return }
        guard !isObservingHealthData else { return }
        isObservingHealthData = true

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
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
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
            options: .strictStartDate
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
            options: .strictStartDate
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
            options: .strictStartDate
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
            options: .strictStartDate
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
        // Primary: use HKActivitySummary which contains the user's actual goals and Apple Watch ring data
        if let summary = try? await fetchActivitySummary(for: date) {
            let moveValue = summary.activeEnergyBurned.doubleValue(for: .kilocalorie())
            let moveGoal = summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
            let exerciseValue = summary.appleExerciseTime.doubleValue(for: .minute())
            let exerciseGoal = summary.appleExerciseTimeGoal.doubleValue(for: .minute())
            let standValue = summary.appleStandHours.doubleValue(for: .count())
            let standGoal = summary.appleStandHoursGoal.doubleValue(for: .count())

            let safeMoveGoal = moveGoal > 0 ? moveGoal : 600
            let safeExerciseGoal = exerciseGoal > 0 ? exerciseGoal : 30
            let safeStandGoal = standGoal > 0 ? standGoal : 12

            return ActivityRings(
                move: RingData(value: moveValue, goal: safeMoveGoal, progress: min(moveValue / safeMoveGoal, 1.0)),
                exercise: RingData(value: exerciseValue, goal: safeExerciseGoal, progress: min(exerciseValue / safeExerciseGoal, 1.0)),
                stand: RingData(value: standValue, goal: safeStandGoal, progress: min(standValue / safeStandGoal, 1.0))
            )
        }

        // Fallback: compute from raw metrics (no Apple Watch or no summary available)
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let activeEnergy = try await fetchCalories(for: startOfDay, end: endOfDay)
        let moveGoal: Double = 600
        let exerciseMinutes = try await fetchExerciseMinutes(for: startOfDay, end: endOfDay)
        let exerciseGoal: Double = 30
        let standHours = try await fetchStandHours(for: startOfDay, end: endOfDay)
        let standGoal: Double = 12

        return ActivityRings(
            move: RingData(value: activeEnergy, goal: moveGoal, progress: min(activeEnergy / moveGoal, 1.0)),
            exercise: RingData(value: exerciseMinutes, goal: exerciseGoal, progress: min(exerciseMinutes / exerciseGoal, 1.0)),
            stand: RingData(value: standHours, goal: standGoal, progress: min(standHours / standGoal, 1.0))
        )
    }

    private func fetchActivitySummary(for date: Date) async throws -> HKActivitySummary? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        components.calendar = calendar
        let predicate = HKQuery.predicateForActivitySummary(with: components)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: summaries?.first)
            }
            self.healthStore.execute(query)
        }
    }
    
    private func fetchCalories(for start: Date, end: Date) async throws -> Double {
        guard let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthKitError.invalidType
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

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
        guard let exerciseTimeType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) else {
            return 0
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: exerciseTimeType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    print("Exercise minutes fetch error (safe to ignore if no data): \(error.localizedDescription)")
                    continuation.resume(returning: 0)
                    return
                }
                let minutes = result?.sumQuantity()?.doubleValue(for: .minute()) ?? 0
                continuation.resume(returning: minutes)
            }
            healthStore.execute(query)
        }
    }

    private func fetchStandHours(for start: Date, end: Date) async throws -> Double {
        guard let standHourType = HKObjectType.categoryType(forIdentifier: .appleStandHour) else {
            return 0
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: standHourType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    print("Stand hour fetch error (safe to ignore if no data): \(error.localizedDescription)")
                    continuation.resume(returning: 0)
                    return
                }
                // Count samples with value "stood" (value 0 = stood, value 1 = idle)
                let stoodCount = (samples as? [HKCategorySample] ?? [])
                    .filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }
                    .count
                continuation.resume(returning: Double(stoodCount))
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchSteps(for start: Date, end: Date) async throws -> Double {
        guard let stepCountType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitError.invalidType
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

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
            options: .strictStartDate
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
                options: .strictStartDate
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
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

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

    // MARK: - Nutrition (write)

    /// Correlates quantity samples with a `nutrition_logs` row for delete-on-edit.
    static let nutritionLogMetadataKey = "com.healthtracker.nutrition_log_id"

    private let nutritionWriteTypeIdentifiers: [HKQuantityTypeIdentifier] = [
        .dietaryEnergyConsumed,
        .dietaryProtein,
        .dietaryCarbohydrates,
        .dietaryFatTotal,
        .dietaryFiber,
        .dietarySodium,
        .dietarySugar,
    ]

    /// Removes nutrition samples previously saved for this meal log (same metadata key on each type).
    func deleteNutritionSamplesForLog(nutritionLogId: UUID) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard hasRequestedAuthorization else { return }
        let key = Self.nutritionLogMetadataKey
        let value = nutritionLogId.uuidString

        for id in nutritionWriteTypeIdentifiers {
            guard let type = HKObjectType.quantityType(forIdentifier: id) else { continue }
            let predicate = HKQuery.predicateForObjects(withMetadataKey: key, allowedValues: [value])
            let toDelete: [HKSample] = await withCheckedContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: type,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, samples, _ in
                    continuation.resume(returning: samples ?? [])
                }
                healthStore.execute(query)
            }
            guard !toDelete.isEmpty else { continue }
            do {
                try await healthStore.delete(toDelete)
            } catch {
                print("HealthKit nutrition delete failed (\(id.rawValue)): \(error.localizedDescription)")
            }
        }
    }

    /// Saves one meal as quantity samples at `date` (same timestamp for each nutrient).
    func saveNutritionFromMeal(
        calories: Double,
        proteinG: Double,
        carbG: Double,
        fatG: Double,
        fiberG: Double?,
        sodiumMg: Double?,
        sugarG: Double? = nil,
        date: Date,
        nutritionLogId: UUID? = nil
    ) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard hasRequestedAuthorization else { return }

        var meta: [String: String]?
        if let nutritionLogId {
            meta = [Self.nutritionLogMetadataKey: nutritionLogId.uuidString]
        }

        func save(_ id: HKQuantityTypeIdentifier, value: Double, unit: HKUnit) async {
            guard let type = HKObjectType.quantityType(forIdentifier: id) else { return }
            guard value > 0 else { return }
            let quantity = HKQuantity(unit: unit, doubleValue: value)
            let sample = HKQuantitySample(
                type: type,
                quantity: quantity,
                start: date,
                end: date,
                metadata: meta
            )
            do {
                try await healthStore.save(sample)
            } catch {
                print("HealthKit nutrition save failed (\(id.rawValue)): \(error.localizedDescription)")
            }
        }

        await save(.dietaryEnergyConsumed, value: calories, unit: .kilocalorie())
        await save(.dietaryProtein, value: proteinG, unit: .gram())
        await save(.dietaryCarbohydrates, value: carbG, unit: .gram())
        await save(.dietaryFatTotal, value: fatG, unit: .gram())
        if let f = fiberG, f > 0 {
            await save(.dietaryFiber, value: f, unit: .gram())
        }
        if let na = sodiumMg, na > 0 {
            await save(.dietarySodium, value: na, unit: .gramUnit(with: .milli))
        }
        if let su = sugarG, su > 0 {
            await save(.dietarySugar, value: su, unit: .gram())
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
