//
//  SyncManager.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/3/26.
//

import Foundation
import Supabase

struct DailyStatUpload: Codable {
    let user_id: UUID
    let date: String // YYYY-MM-DD
    let steps: Int
    let calories: Int
    let flights: Int
    let distance: Double
    let workouts_count: Int
    let exercise_minutes: Int
}

class SyncManager {
    static let shared = SyncManager()
    
    private let authManager = AuthManager.shared
    
    private init() {}
    
    func uploadDailyStats(data: DailyHealthData) async {
        guard let session = authManager.session else {
            print("Sync skipped: No active session")
            return
        }
        
        let userId = session.user.id
        
        // Format date as YYYY-MM-DD for Postgres Date type
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: data.date)
        
        // Calculate exercise minutes from workout durations
        let totalMinutes = Int(data.workouts.reduce(0) { $0 + $1.duration } / 60)
        
        let uploadData = DailyStatUpload(
            user_id: userId,
            date: dateString,
            steps: Int(data.steps),
            calories: Int(data.calories),
            flights: Int(data.flights),
            distance: data.distance ?? 0.0,
            workouts_count: data.workouts.count,
            exercise_minutes: totalMinutes
        )
        
        do {
            try await authManager.client
                .from("daily_stats")
                .upsert(uploadData, onConflict: "user_id, date")
                .execute()
            print("Successfully synced data for \(dateString)")
            
            // Post "Goal Met" to feed if applicable
            if let profile = await authManager.fetchCurrentUserProfile(), let familyId = profile.family_id {
                 SocialFeedManager.shared.checkAndPostGoal(
                    steps: Int(data.steps),
                    calories: Int(data.calories),
                    flights: Int(data.flights),
                    distance: data.distance ?? 0.0,
                    exerciseMinutes: totalMinutes,
                    workoutsCount: data.workouts.count,
                    familyId: familyId
                 )
                 
                 // Also could post checkAndPostWorkout loop here, but SyncManager calls syncWorkouts separately typically.
                 // We will stick to the existing separate syncWorkouts calls.
            }
            
        } catch {
            print("Failed to sync data: \(error)")
        }
    }
    
    func uploadBatchStats(dataList: [DailyHealthData]) async {
        guard let session = authManager.session else { return }
        
        let userId = session.user.id
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        let uploadList = dataList.map { data -> DailyStatUpload in
            let totalMinutes = Int(data.workouts.reduce(0) { $0 + $1.duration } / 60)
             return DailyStatUpload(
                user_id: userId,
                date: formatter.string(from: data.date),
                steps: Int(data.steps),
                calories: Int(data.calories),
                flights: Int(data.flights),
                distance: data.distance ?? 0.0,
                workouts_count: data.workouts.count,
                exercise_minutes: totalMinutes
            )
        }
        
        guard !uploadList.isEmpty else { return }
        
        do {
            try await authManager.client
                .from("daily_stats")
                .upsert(uploadList, onConflict: "user_id, date")
                .execute()
            print("Successfully batch synced \(uploadList.count) days")
        } catch {
            print("Failed to batch sync: \(error)")
        }
    }
    
    func syncWorkouts(workouts: [WorkoutData]) async {
        guard !workouts.isEmpty else { return }
        
        if let profile = await authManager.fetchCurrentUserProfile(), let familyId = profile.family_id {
            for workout in workouts {
                SocialFeedManager.shared.checkAndPostWorkout(workout: workout, familyId: familyId)
            }
        }
    }
    
    func syncRings(rings: ActivityRings) async {
        if let profile = await authManager.fetchCurrentUserProfile(), let familyId = profile.family_id {
            SocialFeedManager.shared.checkAndPostRings(rings: rings, familyId: familyId)
        }
    }
}
