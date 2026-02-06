//
//  SocialFeedManager.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/4/26.
//

import Foundation
import Supabase

class SocialFeedManager {
    static let shared = SocialFeedManager()
    
    private let client = AuthManager.shared.client
    
    private init() {}
    
    // Event Types matches DB check or app convention
    enum EventType: String {
        case joined_family
        case challenge_created
        case challenge_updated // Added
        case challenge_won
        case goal_met
        case workout_finished
        case ring_closed_move
        case ring_closed_exercise
        case ring_closed_stand
    }
    
    // MARK: - Core Post
    
    func post(type: EventType, familyId: UUID, payload: [String: String]? = nil) async {
        guard let userId = AuthManager.shared.session?.user.id else { return }
        
        struct EventInsert: Encodable {
            let family_id: UUID
            let user_id: UUID
            let type: String
            let payload: [String: String]?
        }
        
        let event = EventInsert(
            family_id: familyId,
            user_id: userId,
            type: type.rawValue,
            payload: payload
        )
        
        do {
            try await client
                .from("social_events")
                .insert(event)
                .execute()
            print("Posted event to feed: \(type.rawValue)")
        } catch {
            print("Failed to post event: \(error)")
        }
    }

    
    // MARK: - Goal Checks (Prevent Duplicates)
    
    func checkAndPostGoal(steps: Int, calories: Int, flights: Int, distance: Double, exerciseMinutes: Int, workoutsCount: Int, familyId: UUID) {
        let today = Date().formatted(date: .numeric, time: .omitted)
        
        func check(type: String, value: Double, threshold: Double, unit: String, displayValue: String) {
            let key = "posted_goal_\(type)_\(today)"
            if UserDefaults.standard.bool(forKey: key) { return }
            
            if value >= threshold {
                Task {
                    let payload = [
                        "goal": type,
                        "value": displayValue
                    ]
                    await post(type: .goal_met, familyId: familyId, payload: payload)
                    UserDefaults.standard.set(true, forKey: key)
                }
            }
        }
        
        // Thresholds (could be dynamic later)
        check(type: "Steps", value: Double(steps), threshold: 10_000, unit: "steps", displayValue: "\(steps.formatted()) steps")
        check(type: "Calories", value: Double(calories), threshold: 600, unit: "kcal", displayValue: "\(calories) kcal")
        check(type: "Flights", value: Double(flights), threshold: 10, unit: "floors", displayValue: "\(flights) floors")
        check(type: "Distance", value: distance, threshold: 8000, unit: "m", displayValue: String(format: "%.1f km", distance / 1000))
        check(type: "Exercise Minutes", value: Double(exerciseMinutes), threshold: 30, unit: "mins", displayValue: "\(exerciseMinutes) mins")
        check(type: "Workouts", value: Double(workoutsCount), threshold: 1, unit: "workouts", displayValue: "\(workoutsCount) workouts")
    }
    
    // MARK: - Ring Checks
    
    func checkAndPostRings(rings: ActivityRings, familyId: UUID) {
        let today = Date().formatted(date: .numeric, time: .omitted)
        
        func check(ring: RingData, type: EventType, keySuffix: String) {
            let key = "posted_ring_\(keySuffix)_\(today)"
            if UserDefaults.standard.bool(forKey: key) { return }
            
            if ring.value >= ring.goal && ring.goal > 0 {
                Task {
                    await post(type: type, familyId: familyId)
                    UserDefaults.standard.set(true, forKey: key)
                }
            }
        }
        
        check(ring: rings.move, type: .ring_closed_move, keySuffix: "move")
        check(ring: rings.exercise, type: .ring_closed_exercise, keySuffix: "exercise")
        check(ring: rings.stand, type: .ring_closed_stand, keySuffix: "stand")
    }
    
    // MARK: - Workout Check
    
    func checkAndPostWorkout(workout: WorkoutData, familyId: UUID) {
        // Use a unique key for this workout (e.g. start time + type)
        // Ideally we'd use UUID but WorkoutData might trigger from HK where UUIDs are persistent.
        // Let's use start date string as key + type.
        let key = "posted_workout_\(workout.startDate.timeIntervalSince1970)_\(workout.workoutType)"
        
        if UserDefaults.standard.bool(forKey: key) { return }
        
        Task {
            await post(type: .workout_finished, familyId: familyId)
            UserDefaults.standard.set(true, forKey: key)
        }
    }
}
