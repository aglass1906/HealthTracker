//
//  BackgroundTaskManager.swift
//  HealthTracker
//
//  Created by Background Refresh Implementation
//

import Foundation
import BackgroundTasks
import UIKit

class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    
    private let taskIdentifier = "com.healthtracker.refresh"
    
    private init() {}
    
    // MARK: - Registration
    
    /// Call this at app launch to register background task handlers
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }
        
        print("✅ Background tasks registered")
    }
    
    // MARK: - Scheduling
    
    /// Schedule the next background refresh
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        
        // Request refresh in 4 hours (iOS will adjust based on user patterns)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Background refresh scheduled for ~4 hours from now")
        } catch {
            print("❌ Failed to schedule background refresh: \(error)")
        }
    }
    
    // MARK: - HealthKit Background Delivery

    private var pendingCompletions: [() -> Void] = []
    private var isCoalescing = false

    @MainActor
    func handleHealthKitUpdate(completion: @escaping () -> Void) {
        print("⚡️ HealthKit background delivery received - queueing")
        pendingCompletions.append(completion)

        // If a sync is already in flight, just queue the completion — it will
        // be called when the current sync finishes.
        guard !isCoalescing else { return }
        isCoalescing = true

        Task {
            print("⚡️ Executing coalesced background sync")
            await performBackgroundSync()

            // Call all completions that accumulated while the sync ran.
            let completionsToCall = pendingCompletions
            pendingCompletions.removeAll()
            isCoalescing = false

            for c in completionsToCall { c() }
            print("✅ Called \(completionsToCall.count) HealthKit completion handlers after sync")
        }
    }
    
    // MARK: - Task Handler
    
    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        print("🔄 Background refresh started")
        
        // Schedule the next refresh before we do work
        scheduleBackgroundRefresh()
        
        // Set expiration handler
        task.expirationHandler = {
            print("⚠️ Background task expired")
            // Cancel any ongoing work if needed
        }
        
        // Perform the actual work
        Task {
            await performBackgroundSync()
            task.setTaskCompleted(success: true)
            print("✅ Background refresh completed")
        }
    }
    
    // MARK: - Sync Logic
    
    private func performBackgroundSync() async {
        // 1. Check if user is authenticated
        guard AuthManager.shared.session != nil else {
            print("⏭️ Skipping sync - no active session")
            return
        }
        
        // 2. Request HealthKit authorization
        let healthKitManager = HealthKitManager.shared
        
        if !healthKitManager.isAuthorized {
            do {
                try await healthKitManager.requestAuthorization()
            } catch {
                print("⏭️ Skipping sync - HealthKit authorization failed: \(error)")
                return
            }
        }
        
        guard healthKitManager.isAuthorized else {
            print("⏭️ Skipping sync - no HealthKit authorization")
            return
        }
        
        // Get today's date
        let today = Calendar.current.startOfDay(for: Date())
        
        // 3. Fetch today's data
        do {
            async let steps = healthKitManager.fetchTodaySteps()
            async let flights = healthKitManager.fetchTodayFlights()
            async let calories = healthKitManager.fetchTodayCalories()
            async let distance = healthKitManager.fetchTodayDistance()
            async let workouts = healthKitManager.fetchTodayWorkouts()
            async let rings = healthKitManager.fetchActivityRings()
            
            let (stepsValue, flightsValue, caloriesValue, distanceValue, workoutsValue, ringsValue) = try await (steps, flights, calories, distance, workouts, rings)
            
            let todayData = DailyHealthData(
                date: today,
                steps: stepsValue,
                flights: flightsValue,
                calories: caloriesValue,
                distance: distanceValue,
                activityRings: ringsValue,
                workouts: workoutsValue
            )
            
            // 4. Upload to Supabase (single profile fetch for all three operations)
            await SyncManager.shared.syncAll(data: todayData, workouts: workoutsValue, rings: ringsValue)

            // 5. Update local HealthDataStore so the UI reflects fresh data
            await MainActor.run {
                HealthDataStore.shared.todayData = todayData
                let calendar = Calendar.current
                if let index = HealthDataStore.shared.allDailyData.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
                    HealthDataStore.shared.allDailyData[index] = todayData
                } else {
                    HealthDataStore.shared.allDailyData.append(todayData)
                    HealthDataStore.shared.allDailyData.sort { $0.date > $1.date }
                }
                HealthDataStore.shared.saveData()
            }

            // 6. Update Morning Briefing Notification
            let briefingManager = MorningBriefingManager.shared
            briefingManager.checkBriefingStatus()
            briefingManager.rescheduleNotification()
            
            print("✅ Background sync completed - Steps: \(Int(todayData.steps)), Calories: \(Int(todayData.calories))")
        } catch {
            print("❌ Background sync failed: \(error)")
        }
    }
}
