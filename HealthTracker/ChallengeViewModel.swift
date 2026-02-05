//
//  ChallengeViewModel.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/4/26.
//

import Foundation
import Supabase
import Combine

struct ChallengeParticipant: Identifiable {
    let id: UUID // user_id
    let profile: Profile
    let value: Double // aggregated value (steps, calories, etc)
    let progress: Double // 0.0 to 1.0
    var rank: Int = 0
}

struct DailyStatDB: Codable {
    let user_id: UUID
    let date: String
    let steps: Int
    let calories: Int
    let flights: Int
    let distance: Double
    let duration: Double? // workout minutes if we add column, for now we might need to assume it's NOT in daily_stats table yet based on previous file reads
}

class ChallengeViewModel: ObservableObject {
    @Published var activeChallenges: [Challenge] = []
    @Published var participants: [ChallengeParticipant] = [] // For the selected challenge
    @Published var creatorName: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    let client = AuthManager.shared.client
    
    // MARK: - Fetch Challenges
    
    func fetchActiveChallenges(for familyId: UUID) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let challenges: [Challenge] = try await client
                .from("challenges")
                .select()
                .eq("family_id", value: familyId)
                .order("created_at", ascending: false)
                .execute()
                .value
            
            self.activeChallenges = challenges
        } catch {
            print("Fetch challenges error: \(error)")
            // errorMessage = "Failed to load challenges" // Optional: show error to user
        }
        
        isLoading = false
    }
    
    // MARK: - Create Challenge
    
    func createChallenge(familyId: UUID, title: String, type: ChallengeType, metric: ChallengeMetric, target: Int, startDate: Date, endDate: Date?) async -> Bool {
        guard let userId = AuthManager.shared.session?.user.id else { return false }
        
        // Supabase requires dates in ISO8601 string or Date object depending on SDK
        // The SDK handles Date encoding usually.
        
        struct ChallengeInsert: Encodable {
            let family_id: UUID
            let creator_id: UUID
            let title: String
            let type: ChallengeType
            let metric: ChallengeMetric
            let target_value: Int
            let start_date: String
            let end_date: String?
            let status: ChallengeStatus
        }
        
        // Format dates to ISO8601
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let startString = formatter.string(from: startDate)
        let endString = endDate.map { formatter.string(from: $0) }
        
        let newChallenge = ChallengeInsert(
            family_id: familyId,
            creator_id: userId,
            title: title,
            type: type,
            metric: metric,
            target_value: target,
            start_date: startString,
            end_date: endString,
            status: .active
        )
        
        do {
            try await client
                .from("challenges")
                .insert(newChallenge)
                .execute()
            
            // Refresh list
            await fetchActiveChallenges(for: familyId)
            return true
        } catch {
            print("Create challenge error: \(error)")
            errorMessage = "Failed to create challenge: \(error.localizedDescription)"
            return false
        }
    }
    
    // MARK: - Calculate Progress (The "Race" Logic)
    
    func loadProgress(for challenge: Challenge) async {
        isLoading = true
        participants = []
        creatorName = nil
        
        do {
            // 1. Get family profiles
            let profiles: [Profile] = try await client
                .from("profiles")
                .select()
                .eq("family_id", value: challenge.family_id)
                .execute()
                .value
            
            // Set Creator Name
            if let creator = profiles.first(where: { $0.id == challenge.creator_id }) {
                self.creatorName = creator.display_name ?? creator.email
            }
            
            let userIds = profiles.map { $0.id }
            
            // 2. Get stats since start_date
            // Format start_date to YYYY-MM-DD
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let startString = formatter.string(from: challenge.start_date)
            let todayString = formatter.string(from: Date())
            
            // Note: Schema checks. 'daily_stats' has steps, calories, distance.
            // It might NOT have 'exercise_minutes' column yet unless we verify.
            // If metric is exercise_minutes, we might fail if column doesn't exist.
            // Assuming we stick to Steps/Calories for V1 safety or verify column later.
            
            let stats: [DailyStatDB] = try await client
                .from("daily_stats")
                .select()
                .in("user_id", values: userIds)
                .gte("date", value: startString)
                .lte("date", value: todayString)
                .execute()
                .value
            
            // 3. Aggregate
            var tempParticipants: [ChallengeParticipant] = []
            
            for profile in profiles {
                let userStats = stats.filter { $0.user_id == profile.id }
                
                var totalValue: Double = 0
                
                switch challenge.metric {
                case .steps:
                    totalValue = Double(userStats.reduce(0) { $0 + $1.steps })
                case .calories:
                    totalValue = Double(userStats.reduce(0) { $0 + $1.calories })
                case .distance:
                    totalValue = userStats.reduce(0) { $0 + $1.distance }
                case .exercise_minutes:
                     // Fallback if column missing or logic TODO
                    totalValue = 0 
                case .flights:
                    totalValue = Double(userStats.reduce(0) { $0 + $1.flights })
                }
                
                let progress = totalValue / Double(challenge.target_value)
                
                tempParticipants.append(ChallengeParticipant(
                    id: profile.id,
                    profile: profile,
                    value: totalValue,
                    progress: progress
                ))
            }
            
            // 4. Rank
            tempParticipants.sort { $0.value > $1.value }
            
            // Assign ranks
            for i in 0..<tempParticipants.count {
                tempParticipants[i].rank = i + 1
            }
            
            self.participants = tempParticipants
            
        } catch {
            print("Load progress error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Edit/Delete Challenge
    
    func updateChallenge(challenge: Challenge, title: String, target: Int, startDate: Date, endDate: Date?) async -> Bool {
        guard let userId = AuthManager.shared.session?.user.id, userId == challenge.creator_id else { return false }
        
        struct ChallengeUpdate: Encodable {
            let title: String
            let target_value: Int
            let start_date: String
            let end_date: String?
        }
        
        // Format dates to ISO8601
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let startString = formatter.string(from: startDate)
        let endString = endDate.map { formatter.string(from: $0) }
        
        let updateData = ChallengeUpdate(
            title: title,
            target_value: target,
            start_date: startString,
            end_date: endString
        )
        
        do {
            try await client
                .from("challenges")
                .update(updateData)
                .eq("id", value: challenge.id)
                .execute()
            
            return true
        } catch {
            print("Update challenge error: \(error)")
            errorMessage = "Failed to update challenge."
            return false
        }
    }
    
    func deleteChallenge(challengeId: UUID) async -> Bool {
        do {
            try await client
                .from("challenges")
                .delete()
                .eq("id", value: challengeId)
                .execute()
            
            return true
        } catch {
            print("Delete challenge error: \(error)")
            errorMessage = "Failed to delete challenge."
            return false
        }
    }
}
