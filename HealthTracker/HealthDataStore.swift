//
//  HealthDataStore.swift
//  HealthTracker
//
//  Created by Alan Glass on 12/29/25.
//

import Foundation
import Combine
import HealthKit

@MainActor
class HealthDataStore: ObservableObject {
    static let shared = HealthDataStore()
    
    @Published var todayData: DailyHealthData?
    @Published var allDailyData: [DailyHealthData] = []
    @Published var isLoading = false
    @Published var lastSyncDate: Date?
    @Published var shouldShowImportPrompt = false
    @Published var lastErrorMessage: String? // Debugging aid
    @Published var newlyFinishedWorkout: WorkoutData?
    
    // Internal state
    private var lastSeenWorkoutIDs: Set<String> = []
    
    private let healthKitManager = HealthKitManager.shared
    private let userDefaults = UserDefaults.standard
    private let dataKey = "healthTracker_dailyData"
    private let lastSyncKey = "healthTracker_lastSync"
    private let lastSeenWorkoutsKey = "healthTracker_lastSeenWorkouts"
    private let hasImportedKey = "healthTracker_hasImported"
    
    private init() {
        loadPersistedData()
    }
    
    // MARK: - Persistence
    
    func loadPersistedData() {
        if let data = userDefaults.data(forKey: dataKey),
           let decoded = try? JSONDecoder().decode([DailyHealthData].self, from: data) {
            allDailyData = decoded
        }
        
        if let syncDate = userDefaults.object(forKey: lastSyncKey) as? Date {
            lastSyncDate = syncDate
        }
        
        if let savedIDs = userDefaults.array(forKey: lastSeenWorkoutsKey) as? [String] {
            lastSeenWorkoutIDs = Set(savedIDs)
        }
        
        // Load today's data if available
        let today = Calendar.current.startOfDay(for: Date())
        todayData = allDailyData.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }
    
    func saveData() {
        if let encoded = try? JSONEncoder().encode(allDailyData) {
            userDefaults.set(encoded, forKey: dataKey)
        }
        
        let ids = Array(lastSeenWorkoutIDs)
        userDefaults.set(ids, forKey: lastSeenWorkoutsKey)
        
        userDefaults.set(Date(), forKey: lastSyncKey)
        lastSyncDate = Date()
    }
    
    // MARK: - Data Fetching
    
    func refreshTodayData() async {
        if !healthKitManager.isAuthorized {
            do {
                try await healthKitManager.requestAuthorization()
            } catch {
                print("Failed to authorize HealthKit: \(error)")
                return
            }
        }
        
        guard healthKitManager.isAuthorized else {
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            async let steps = healthKitManager.fetchTodaySteps()
            async let flights = healthKitManager.fetchTodayFlights()
            async let calories = healthKitManager.fetchTodayCalories()
            async let distance = healthKitManager.fetchTodayDistance()
            async let workouts = healthKitManager.fetchTodayWorkouts()
            async let rings = healthKitManager.fetchActivityRings()
            
            let (stepsValue, flightsValue, caloriesValue, distanceValue, workoutsValue, ringsValue) = try await (steps, flights, calories, distance, workouts, rings)
            
            let today = Calendar.current.startOfDay(for: Date())
            let newData = DailyHealthData(
                date: today,
                steps: stepsValue,
                flights: flightsValue,
                calories: caloriesValue,
                distance: distanceValue,
                activityRings: ringsValue,
                workouts: workoutsValue
            )
            
            todayData = newData
            
            // Update or add to allDailyData
            if let index = allDailyData.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
                allDailyData[index] = newData
            } else {
                allDailyData.append(newData)
                allDailyData.sort { $0.date > $1.date }
            }
            
            saveData()
            
            // Sync to Supabase
            Task {
                await SyncManager.shared.uploadDailyStats(data: newData)
                await SyncManager.shared.syncWorkouts(workouts: workoutsValue)
                await SyncManager.shared.syncRings(rings: ringsValue)
            }
            
            // Clear error on success
            lastErrorMessage = nil
        } catch {
            print("Failed to fetch today's data: \(error)")
            
            // Check for locked database
            if let hkError = error as? HKError, hkError.code == .errorDatabaseInaccessible {
                lastErrorMessage = "Sync was interrupted because the device was locked. Information is being updated now..."
            } else {
                lastErrorMessage = "Today Sync Error: \(error.localizedDescription)"
            }
        }
    }
    
    func refreshAllData() async {
        if !healthKitManager.isAuthorized {
            do {
                try await healthKitManager.requestAuthorization()
            } catch {
                print("Failed to authorize HealthKit: \(error)")
                return
            }
        }
        
        guard healthKitManager.isAuthorized else {
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Fetch last 30 days of data
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -30, to: endDate)!
        
        do {
            let dailyData = try await healthKitManager.fetchHealthDataForDateRange(from: startDate, to: endDate)
            
            // Fetch workouts for each day
            var updatedData: [DailyHealthData] = []
            for data in dailyData {
                let dayStart = calendar.startOfDay(for: data.date)
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
                
                do {
                    let workouts = try await healthKitManager.fetchWorkouts(from: dayStart, to: dayEnd)
                    let rings = try await healthKitManager.fetchActivityRings(for: data.date)
                    
                    var updated = data
                    updated.workouts = workouts
                    updated.activityRings = rings
                    updatedData.append(updated)
                } catch {
                    updatedData.append(data)
                }
            }
            
            allDailyData = updatedData.sorted { $0.date > $1.date }
            saveData()
            
            // Sync to Supabase
            Task {
                await SyncManager.shared.uploadBatchStats(dataList: updatedData)
            }
            
            // Update today's data
            let today = calendar.startOfDay(for: Date())
            todayData = allDailyData.first { calendar.isDate($0.date, inSameDayAs: today) }
            
            // Clear error on success
            lastErrorMessage = nil
        } catch {
            print("Failed to fetch all data: \(error)")
            
            // Check for locked database
            if let hkError = error as? HKError, hkError.code == .errorDatabaseInaccessible {
                lastErrorMessage = "Sync was interrupted because the device was locked. Information is being updated now..."
            } else {
                lastErrorMessage = "All Data Sync Error: \(error.localizedDescription)"
            }
        }
    }
    
    func getDailyData(for date: Date) -> DailyHealthData? {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)
        return allDailyData.first { calendar.isDate($0.date, inSameDayAs: targetDate) }
    }
    
    func getSummary(for startDate: Date, to endDate: Date) -> HealthSummary {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        
        let filteredData = allDailyData.filter { data in
            data.date >= start && data.date <= end
        }
        
        return HealthSummary(startDate: start, endDate: end, dailyData: filteredData)
    }
    
    // MARK: - Import Functions
    
    func importLast30Days() async {
        if !healthKitManager.isAuthorized {
            do {
                try await healthKitManager.requestAuthorization()
            } catch {
                print("Failed to authorize HealthKit: \(error)")
                return
            }
        }
        
        guard healthKitManager.isAuthorized else {
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -30, to: endDate)!
        
        do {
            let dailyData = try await healthKitManager.fetchHealthDataForDateRange(from: startDate, to: endDate)
            
            // Fetch workouts and rings for each day
            var updatedData: [DailyHealthData] = []
            for data in dailyData {
                let dayStart = calendar.startOfDay(for: data.date)
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
                
                do {
                    let workouts = try await healthKitManager.fetchWorkouts(from: dayStart, to: dayEnd)
                    let rings = try await healthKitManager.fetchActivityRings(for: data.date)
                    
                    var updated = data
                    updated.workouts = workouts
                    updated.activityRings = rings
                    updatedData.append(updated)
                } catch {
                    updatedData.append(data)
                }
            }
            
            // Merge with existing data, keeping the most recent version
            var mergedData = allDailyData
            for newData in updatedData {
                if let index = mergedData.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: newData.date) }) {
                    mergedData[index] = newData
                } else {
                    mergedData.append(newData)
                }
            }
            
            allDailyData = mergedData.sorted { $0.date > $1.date }
            saveData()
            
            // Sync to Supabase
            Task {
                await SyncManager.shared.uploadBatchStats(dataList: mergedData)
            }
            
            // Clear error on success
            lastErrorMessage = nil
        } catch {
            print("Failed to import data: \(error)")
            
            // Check for locked database
            if let hkError = error as? HKError, hkError.code == .errorDatabaseInaccessible {
                lastErrorMessage = "Sync was interrupted because the device was locked. Information is being updated now..."
            } else {
                lastErrorMessage = "Import Error: \(error.localizedDescription)"
            }
        }
    }
    
    func importLatestData() async {
        if !healthKitManager.isAuthorized {
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Check if we need to import recent days (last 7 days to catch up)
        let endDate = today
        let startDate = calendar.date(byAdding: .day, value: -7, to: endDate)!
        
        // Find which days we're missing
        var daysToImport: [Date] = []
        var currentDate = startDate
        while currentDate <= endDate {
            let dayData = allDailyData.first { calendar.isDate($0.date, inSameDayAs: currentDate) }
            if dayData == nil {
                daysToImport.append(currentDate)
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        // If we have today's data, just refresh it
        if let todayData = todayData, calendar.isDate(todayData.date, inSameDayAs: today) {
            await refreshTodayData()
        } else {
            // Import missing days
            if !daysToImport.isEmpty, let minDate = daysToImport.min(), let maxDate = daysToImport.max() {
                do {
                    let dailyData = try await healthKitManager.fetchHealthDataForDateRange(
                        from: minDate,
                        to: maxDate
                    )
                    
                    var updatedData: [DailyHealthData] = []
                    for data in dailyData {
                        if daysToImport.contains(where: { calendar.isDate($0, inSameDayAs: data.date) }) {
                            let dayStart = calendar.startOfDay(for: data.date)
                            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
                            
                            do {
                                let workouts = try await healthKitManager.fetchWorkouts(from: dayStart, to: dayEnd)
                                let rings = try await healthKitManager.fetchActivityRings(for: data.date)
                                
                                var updated = data
                                updated.workouts = workouts
                                updated.activityRings = rings
                                updatedData.append(updated)
                                
                                // Track seen workouts
                                for workout in workouts {
                                    if !lastSeenWorkoutIDs.contains(workout.id) {
                                        lastSeenWorkoutIDs.insert(workout.id)
                                    }
                                }
                            } catch {
                                updatedData.append(data)
                            }
                        }
                    }
                    
                    // Merge with existing data
                    for newData in updatedData {
                        if let index = allDailyData.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: newData.date) }) {
                            allDailyData[index] = newData
                        } else {
                            allDailyData.append(newData)
                        }
                    }
                    
                    allDailyData.sort { $0.date > $1.date }
                    saveData()
                    
                    // Sync to Supabase
                    Task {
                        await SyncManager.shared.uploadBatchStats(dataList: allDailyData)
                    }
                    
                    // Update today's data
                    todayData = allDailyData.first { calendar.isDate($0.date, inSameDayAs: today) }
                    
                    // Clear error on success
                    lastErrorMessage = nil
                } catch {
                    print("Failed to import latest data: \(error)")
                    
                    // Check for locked database
                    if let hkError = error as? HKError, hkError.code == .errorDatabaseInaccessible {
                        lastErrorMessage = "Sync was interrupted because the device was locked. Information is being updated now..."
                    } else {
                        lastErrorMessage = "Import Latest Error: \(error.localizedDescription)"
                    }
                }
            } else {
                // Just refresh today's data
                await refreshTodayData()
            }
        }
    }
    
    var hasImportedData: Bool {
        userDefaults.bool(forKey: hasImportedKey)
    }
    
    // MARK: - Clear Data
    
    func clearAllData() {
        allDailyData = []
        todayData = nil
        lastSyncDate = nil
        userDefaults.removeObject(forKey: dataKey)
        userDefaults.removeObject(forKey: lastSyncKey)
        userDefaults.removeObject(forKey: hasImportedKey)
    }
}

