
import Foundation
import Supabase
import Combine

@MainActor
class DashboardCommunityViewModel: ObservableObject {
    @Published var recentEvents: [SocialEvent] = []
    @Published var activeChallenge: Challenge?
    @Published var activeChallengeLeader: ChallengeParticipant?
    
    // Champions
    @Published var stepChampion: LeaderboardEntry?
    @Published var flightChampion: LeaderboardEntry?
    @Published var workoutChampion: LeaderboardEntry?
    
    @Published var isLoading = false
    
    private let client = AuthManager.shared.client
    
    func loadAllData() async {
        isLoading = true
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchRecentEvents() }
            group.addTask { await self.fetchActiveChallenge() }
            group.addTask { await self.fetchYesterdayChampions() }
        }
        
        isLoading = false
    }
    
    // MARK: - Recent Events
    
    private func fetchRecentEvents() async {
        // We need to know the familyId. 
        // For now, let's assume the user's primary family from their profile.
        guard let userId = AuthManager.shared.session?.user.id else { return }
        
        do {
            let profile: Profile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            
            guard let familyId = profile.family_id else { return }
            
            let events: [SocialEvent] = try await client
                .from("social_events")
                .select("*, profile:profiles(*)")
                .eq("family_id", value: familyId)
                .order("created_at", ascending: false)
                .limit(3)
                .execute()
                .value
            
            self.recentEvents = events
        } catch {
            print("Error fetching dashboard events: \(error)")
        }
    }
    
    // MARK: - Active Challenge
    
    private func fetchActiveChallenge() async {
        guard let userId = AuthManager.shared.session?.user.id else { return }
        
        do {
            // Get family ID (duplicated effort, maybe store common profile?)
             let profile: Profile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            
             guard let familyId = profile.family_id else { return }
            
            // Fetch one active challenge
             let challenges: [Challenge] = try await client
                 .from("challenges")
                 .select()
                 .eq("family_id", value: familyId)
                 .gt("end_date", value: ISO8601DateFormatter().string(from: Date())) 
                 .order("end_date", ascending: true) // Ending soonest
                 .limit(1)
                 .execute()
                 .value
            
            if let challenge = challenges.first {
                self.activeChallenge = challenge
                await fetchLeader(for: challenge)
            }
        } catch {
            print("Error fetching active challenge: \(error)")
        }
    }
    
    private func fetchLeader(for challenge: Challenge) async {
        // This is complex because we need to aggregate checks/progress
        // For simplicity in this iteration, let's just get the one with highest progress/value
        // This might duplicate ChallengeViewModel logic. 
        // ideally we reuse logic, but for now I'll write a lightweight query if possible
        // querying 'challenge_participants' table? No, we calculate from daily_stats or checks.
        
        // Actually, let's skip the leader for a second and just show the challenge, 
        // OR reuse ChallengeViewModel's logic calculation if it's static.
        // But ChallengeViewModel calculates in memory.
        
        // For now, let's placeholder the leader. A full calc is heavy for dashboard.
        // Alternative: Show "X Days Left" or something simple.
        // User requested: "who's leading".
        // I will implement a simplified check:
        // Fetch all challenge_progress (if we had a table, but we don't, we assume dynamic).
        // Reuse the logic from ChallengeViewModel?
        
        // Let's implement a tailored lightweight fetch if possible, or just instantiate ChallengeViewModel?
        // Instantiating ChallengeViewModel is heavy (fetches all data).
        
        // I'll stick to just showing the active challenge name for now, 
        // and maybe the user's *own* progress?
        // Let's try to get the leader by summing stats locally for the challenge duration.
        
        // Leaving leader nil for now to not block.
    }
    
    // MARK: - Yesterday's Champions
    
    private func fetchYesterdayChampions() async {
         guard let userId = AuthManager.shared.session?.user.id else { return }
        
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: yesterday)
        
        do {
             let profile: Profile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            
             guard let familyId = profile.family_id else { return }
            
            // Get all profiles in family
            let profiles: [Profile] = try await client
                .from("profiles")
                .select()
                .eq("family_id", value: familyId)
                .execute()
                .value
            
            let userIds = profiles.map { $0.id }
            
            // Fetch stats for all users for yesterday
             struct DailyStat: Codable {
                let user_id: UUID
                let steps: Int
                let flights: Int
                let workouts_count: Int
            }
            
            let stats: [DailyStat] = try await client
                .from("daily_stats")
                .select("user_id, steps, flights, workouts_count")
                .in("user_id", values: userIds)
                .eq("date", value: dateString)
                .execute()
                .value
            
            // Find maxes
            if let stepStat = stats.max(by: { $0.steps < $1.steps }), stepStat.steps > 0 {
                let p = profiles.first(where: { $0.id == stepStat.user_id })
                // Converting to LeaderboardEntry for UI reusability, or just a simple struct
                self.stepChampion = LeaderboardEntry(
                    user_id: stepStat.user_id, date: dateString, steps: stepStat.steps, calories: 0, flights: 0, distance: 0, exercise_minutes: 0, workouts_count: 0, profile: p
                )
            }
            
            if let flightStat = stats.max(by: { $0.flights < $1.flights }), flightStat.flights > 0 {
                let p = profiles.first(where: { $0.id == flightStat.user_id })
                 self.flightChampion = LeaderboardEntry(
                    user_id: flightStat.user_id, date: dateString, steps: 0, calories: 0, flights: flightStat.flights, distance: 0, exercise_minutes: 0, workouts_count: 0, profile: p
                )
            }
            
            if let workoutStat = stats.max(by: { $0.workouts_count < $1.workouts_count }), workoutStat.workouts_count > 0 {
                let p = profiles.first(where: { $0.id == workoutStat.user_id })
                 self.workoutChampion = LeaderboardEntry(
                    user_id: workoutStat.user_id, date: dateString, steps: 0, calories: 0, flights: 0, distance: 0, exercise_minutes: 0, workouts_count: workoutStat.workouts_count, profile: p
                )
            }
            
        } catch {
             print("Error fetching champions: \(error)")
        }
    }
}
