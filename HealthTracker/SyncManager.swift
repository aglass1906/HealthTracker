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
    let move_ring_value: Double
    let exercise_ring_value: Double
    let stand_ring_value: Double
    let all_rings_closed: Int
}

class SyncManager {
    static let shared = SyncManager()
    
    private let authManager = AuthManager.shared
    
    private init() {}

    private func allRingsClosed(_ rings: ActivityRings?) -> Int {
        guard let rings else { return 0 }
        let moveClosed = rings.move.goal > 0 && rings.move.value >= rings.move.goal
        let exerciseClosed = rings.exercise.goal > 0 && rings.exercise.value >= rings.exercise.goal
        let standClosed = rings.stand.goal > 0 && rings.stand.value >= rings.stand.goal
        return moveClosed && exerciseClosed && standClosed ? 1 : 0
    }

    /// Best available exercise minutes for the day: Apple's exercise ring
    /// minutes when present (this is what My Data and the Fitness app show),
    /// otherwise the summed duration of logged workouts.
    private func exerciseMinutes(workouts: [WorkoutData], rings: ActivityRings?) -> Int {
        let workoutMinutes = Int(workouts.reduce(0) { $0 + $1.duration } / 60)
        let ringMinutes = Int(rings?.exercise.value ?? 0)
        return max(ringMinutes, workoutMinutes)
    }
    
    func uploadBatchStats(dataList: [DailyHealthData]) async {
        guard let session = authManager.session else { return }
        
        let userId = session.user.id
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let uploadList = dataList.map { data -> DailyStatUpload in
            let totalMinutes = exerciseMinutes(workouts: data.workouts, rings: data.activityRings)
             return DailyStatUpload(
                user_id: userId,
                date: formatter.string(from: data.date),
                steps: Int(data.steps),
                calories: Int(data.calories),
                flights: Int(data.flights),
                distance: data.distance ?? 0.0,
                workouts_count: data.workouts.count,
                exercise_minutes: totalMinutes,
                move_ring_value: data.activityRings?.move.value ?? 0,
                exercise_ring_value: data.activityRings?.exercise.value ?? 0,
                stand_ring_value: data.activityRings?.stand.value ?? 0,
                all_rings_closed: allRingsClosed(data.activityRings)
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
    
    /// Single-call sync that uploads stats, workouts, and rings with only one
    /// community-membership fetch. Used by both foreground refreshes and
    /// background syncs.
    func syncAll(data: DailyHealthData, workouts: [WorkoutData], rings: ActivityRings) async {
        guard let session = authManager.session else {
            print("Sync skipped: No active session")
            return
        }

        let userId = session.user.id
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let dateString = formatter.string(from: data.date)
        let totalMinutes = exerciseMinutes(workouts: data.workouts, rings: rings)

        // 1. Upload daily stats
        let uploadData = DailyStatUpload(
            user_id: userId,
            date: dateString,
            steps: Int(data.steps),
            calories: Int(data.calories),
            flights: Int(data.flights),
            distance: data.distance ?? 0.0,
            workouts_count: data.workouts.count,
            exercise_minutes: totalMinutes,
            move_ring_value: rings.move.value,
            exercise_ring_value: rings.exercise.value,
            stand_ring_value: rings.stand.value,
            all_rings_closed: allRingsClosed(rings)
        )

        do {
            try await authManager.client
                .from("daily_stats")
                .upsert(uploadData, onConflict: "user_id, date")
                .execute()
            print("✅ syncAll: uploaded stats for \(dateString)")
        } catch {
            print("❌ syncAll: failed to upload stats: \(error)")
        }

        // 2. Fetch communities once for all feed posts
        let familyIds = await SocialFeedManager.shared.fetchCurrentUserCommunityIds()
        guard !familyIds.isEmpty else {
            print("syncAll: no communities, skipping feed posts")
            return
        }

        // 3. Goal check
        for familyId in familyIds {
            SocialFeedManager.shared.checkAndPostGoal(
                steps: Int(data.steps),
                calories: Int(data.calories),
                flights: Int(data.flights),
                distance: data.distance ?? 0.0,
                exerciseMinutes: totalMinutes,
                workoutsCount: data.workouts.count,
                familyId: familyId
            )

            // 4. Workouts
            for workout in workouts {
                SocialFeedManager.shared.checkAndPostWorkout(workout: workout, familyId: familyId)
            }

            // 5. Rings
            SocialFeedManager.shared.checkAndPostRings(rings: rings, familyId: familyId)
        }
    }
}
