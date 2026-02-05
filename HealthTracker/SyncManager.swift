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
        
        let uploadData = DailyStatUpload(
            user_id: userId,
            date: dateString,
            steps: Int(data.steps),
            calories: Int(data.calories),
            flights: Int(data.flights),
            // Assuming we might add distance to DailyHealthData later, using 0 for now or calculating it if redundant
            distance: 0.0 
        )
        
        do {
            try await authManager.client
                .from("daily_stats")
                .upsert(uploadData, onConflict: "user_id, date")
                .execute()
            print("Successfully synced data for \(dateString)")
            
            // Post "Goal Met" to feed if applicable
            // 1. Need family_id. We accept a slight overhead of fetching profile here if not cached, 
            // or we could cache it in SyncManager. For now, fetch is safer.
            // But AuthManager has a helper now.
            
            if let profile = await authManager.fetchCurrentUserProfile(), let familyId = profile.family_id {
                 SocialFeedManager.shared.checkAndPostGoal(
                    steps: Int(data.steps),
                    calories: Int(data.calories),
                    flights: Int(data.flights),
                    distance: data.distance ?? 0.0,
                    familyId: familyId
                 )
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
        
        let uploadList = dataList.map { data in
            DailyStatUpload(
                user_id: userId,
                date: formatter.string(from: data.date),
                steps: Int(data.steps),
                calories: Int(data.calories),
                flights: Int(data.flights),
                distance: 0.0
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
