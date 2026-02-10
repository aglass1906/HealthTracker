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
        case round_winner
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
        let key = "posted_workout_\(workout.startDate.timeIntervalSince1970)_\(workout.workoutType)"
        
        if UserDefaults.standard.bool(forKey: key) { return }
        
        var payload: [String: String] = [
            "workout_type": workout.workoutType,
            "duration": formatDuration(workout.duration),
            "duration_seconds": String(workout.duration)
        ]
        
        if let calories = workout.totalEnergyBurned {
            payload["calories"] = String(format: "%.0f", calories)
        }
        
        if let distance = workout.totalDistance {
            payload["distance"] = String(format: "%.2f", distance / 1000) // km
        }
        
        Task {
            await post(type: .workout_finished, familyId: familyId, payload: payload)
            UserDefaults.standard.set(true, forKey: key)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
    
    // MARK: - Round Winner
    
    func postRoundWinner(challengeTitle: String, roundNumber: Int, winnerName: String, familyId: UUID) async {
        let payload: [String: String] = [
            "challenge_title": challengeTitle,
            "round_number": "\(roundNumber)",
            "winner_name": winnerName
        ]
        
        await post(type: .round_winner, familyId: familyId, payload: payload)
    }
}
