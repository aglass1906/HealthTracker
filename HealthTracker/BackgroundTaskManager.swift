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
    private var isDebouncing = false
    
    @MainActor
    func handleHealthKitUpdate(completion: @escaping () -> Void) {
        print("⚡️ HealthKit background delivery received - queueing")
        
        pendingCompletions.append(completion)
        
        if !isDebouncing {
            isDebouncing = true
            
            Task {
                // Wait 2 seconds to collect other updates (e.g. startup burst)
                try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                
                print("⚡️ Executing coalesced background sync")
                await performBackgroundSync()
                
                // Call all completions
                let completionsToCall = pendingCompletions
                pendingCompletions.removeAll()
                isDebouncing = false
                
                for completion in completionsToCall {
                    completion()
                }
                print("✅ Called \(completionsToCall.count) completion handlers after coalesced sync")
            }
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
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        
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
            
            // 4. Upload to Supabase
            await SyncManager.shared.uploadDailyStats(data: todayData)
            await SyncManager.shared.syncWorkouts(workouts: workoutsValue)
            await SyncManager.shared.syncRings(rings: ringsValue)
            
            print("✅ Background sync completed - Steps: \(Int(todayData.steps)), Calories: \(Int(todayData.calories))")
        } catch {
            print("❌ Background sync failed: \(error)")
        }
    }
}
