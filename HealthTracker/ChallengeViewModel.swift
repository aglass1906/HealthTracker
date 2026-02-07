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
    var progress: Double // 0.0 to 1.0
    var rank: Int = 0
}

struct DailyStatDB: Codable {
    let user_id: UUID
    let date: String
    let steps: Int
    let calories: Int
    let flights: Int
    let distance: Double
    let workouts_count: Int? 
    let exercise_minutes: Int?
}

class ChallengeViewModel: ObservableObject {
    @Published var activeChallenges: [Challenge] = []
    @Published var participants: [ChallengeParticipant] = [] // For the selected challenge
    @Published var creatorName: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var rounds: [ChallengeRound] = []
    @Published var currentRoundParticipants: [RoundParticipant] = []
    @Published var roundWinCounts: [UUID: Int] = [:] // user_id -> win count
    
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
            
            // Check for challenge completions
            for challenge in challenges {
                await checkChallengeCompletion(for: challenge)
            }
        } catch {
            print("Fetch challenges error: \(error)")
            // errorMessage = "Failed to load challenges" // Optional: show error to user
        }
        
        isLoading = false
    }
    
    // MARK: - Create Challenge
    
    func createChallenge(familyId: UUID, title: String, type: ChallengeType, metric: ChallengeMetric, target: Int, startDate: Date, endDate: Date?, roundDuration: RoundDuration? = nil) async -> Bool {
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
            let round_duration: String?
            let current_round_number: Int?
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
            status: .active,
            round_duration: roundDuration?.rawValue,
            current_round_number: roundDuration != nil ? 1 : nil
        )
        
        do {
            let createdChallenges: [Challenge] = try await client
                .from("challenges")
                .insert(newChallenge)
                .select()
                .execute()
                .value
            
            // If rounds enabled, create all rounds upfront
            if let roundDur = roundDuration, let challenge = createdChallenges.first {
                let calendar = Calendar.current
                let startOfFirstRound = calendar.startOfDay(for: startDate)
                var currentRoundStart = startOfFirstRound
                var roundNum = 1
                
                // Create all rounds upfront based on challenge duration
                let challengeEnd = endDate ?? calendar.date(byAdding: .day, value: 1, to: startDate)!
                while currentRoundStart < challengeEnd {
                    var roundEnd: Date
                    
                    switch roundDur {
                    case .daily:
                        // End of the same day (23:59:59)
                        roundEnd = calendar.date(byAdding: .day, value: 1, to: currentRoundStart)!.addingTimeInterval(-1)
                    case .weekly:
                        roundEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: currentRoundStart)!.addingTimeInterval(-1)
                    case .monthly:
                        roundEnd = calendar.date(byAdding: .month, value: 1, to: currentRoundStart)!.addingTimeInterval(-1)
                    }
                    
                    // Clamp round end to challenge end if needed
                    if roundEnd > challengeEnd {
                        roundEnd = challengeEnd
                    }
                    
                    // Determine status based on current date
                    let now = Date()
                    let status: String
                    if now < currentRoundStart {
                        status = "pending"
                    } else if now > roundEnd {
                        status = "completed"
                    } else {
                        status = "active"
                    }
                    
                    let round = ChallengeRoundInsert(
                        challenge_id: challenge.id,
                        round_number: roundNum,
                        start_date: formatter.string(from: currentRoundStart),
                        end_date: formatter.string(from: roundEnd),
                        status: status
                    )
                    
                    try await client
                        .from("challenge_rounds")
                        .insert(round)
                        .execute()
                    
                    // Move to next round
                    switch roundDur {
                    case .daily:
                        currentRoundStart = calendar.date(byAdding: .day, value: 1, to: currentRoundStart)!
                    case .weekly:
                        currentRoundStart = calendar.date(byAdding: .weekOfYear, value: 1, to: currentRoundStart)!
                    case .monthly:
                        currentRoundStart = calendar.date(byAdding: .month, value: 1, to: currentRoundStart)!
                    }
                    
                    roundNum += 1
                    
                    // Safety check to prevent infinite loops
                    if roundNum > 1000 {
                        print("Warning: Too many rounds generated, breaking loop")
                        break
                    }
                }
            }
            
            // Refresh list
            await fetchActiveChallenges(for: familyId)
            
            // Post to Feed
            Task {
                var goalText = "\(target) \(metric.unit)"
                if type == .count {
                    if let endDate = endDate {
                        goalText = "Most \(metric.displayName) by \(endDate.formatted(date: .abbreviated, time: .omitted))"
                    } else {
                        goalText = "Most \(metric.displayName)"
                    }
                }
                
                let payload: [String: String] = [
                    "title": title,
                    "metric": metric.displayName,
                    "goal": goalText
                ]
                await SocialFeedManager.shared.post(type: .challenge_created, familyId: familyId, payload: payload)
            }
            
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
                    let totalInt = userStats.reduce(into: 0) { $0 += ($1.exercise_minutes ?? 0) }
                    totalValue = Double(totalInt)
                case .flights:
                    totalValue = Double(userStats.reduce(0) { $0 + $1.flights })
                case .workouts:
                    let totalInt = userStats.reduce(into: 0) { $0 += ($1.workouts_count ?? 0) }
                    totalValue = Double(totalInt)
                }
                
                let progress: Double
                
                if challenge.type == .count {
                    // For count/leaderboard, progress is relative to the LEADER (max value), 
                    // calculated after we have all values.
                    progress = 0 // Placeholder
                } else {
                    progress = totalValue / Double(challenge.target_value)
                }
                
                tempParticipants.append(ChallengeParticipant(
                    id: profile.id,
                    profile: profile,
                    value: totalValue,
                    progress: progress
                ))
            }
            
            // 4. Rank
            tempParticipants.sort { $0.value > $1.value }
            
            // Assign ranks & Fix Progress for .count
            let maxValue = tempParticipants.first?.value ?? 1
            
            for i in 0..<tempParticipants.count {
                tempParticipants[i].rank = i + 1
                
                if challenge.type == .count {
                    if maxValue > 0 {
                        tempParticipants[i].progress = tempParticipants[i].value / maxValue
                    } else {
                        tempParticipants[i].progress = 0
                    }
                }
                
                // For other types, we might want to cap at 1.0 or let it go over?
                // Typically progress bars clamp to 1.0 visually, but data can be > 1.0
            }
            
            self.participants = tempParticipants
            
        } catch {
            print("Load progress error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Edit/Delete Challenge
    
    func updateChallenge(challenge: Challenge, title: String, target: Int, startDate: Date, endDate: Date?, notifyFeed: Bool) async -> Bool {
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
            
            // If this is a round-based challenge and end date changed, create missing rounds
            if let roundDur = challenge.roundDuration, let newEndDate = endDate {
                // Get existing rounds
                let existingRounds: [ChallengeRound] = try await client
                    .from("challenge_rounds")
                    .select()
                    .eq("challenge_id", value: challenge.id)
                    .order("round_number", ascending: false)
                    .execute()
                    .value
                
                let calendar = Calendar.current
                let oldEndDate = challenge.end_date ?? challenge.start_date
                
                // Only create new rounds if end date was extended
                if newEndDate > oldEndDate, let lastRound = existingRounds.first {
                    var nextRoundNumber = lastRound.round_number + 1
                    var currentRoundStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastRound.end_date))!
                    
                    // Create rounds until we reach the new end date
                    while currentRoundStart < newEndDate {
                        var roundEnd: Date
                        
                        switch roundDur {
                        case .daily:
                            roundEnd = calendar.date(byAdding: .day, value: 1, to: currentRoundStart)!.addingTimeInterval(-1)
                        case .weekly:
                            roundEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: currentRoundStart)!.addingTimeInterval(-1)
                        case .monthly:
                            roundEnd = calendar.date(byAdding: .month, value: 1, to: currentRoundStart)!.addingTimeInterval(-1)
                        }
                        
                        if roundEnd > newEndDate {
                            roundEnd = newEndDate
                        }
                        
                        // Determine status
                        let now = Date()
                        let status: String
                        if now < currentRoundStart {
                            status = "pending"
                        } else if now > roundEnd {
                            status = "completed"
                        } else {
                            status = "active"
                        }
                        
                        let newRound = ChallengeRoundInsert(
                            challenge_id: challenge.id,
                            round_number: nextRoundNumber,
                            start_date: formatter.string(from: currentRoundStart),
                            end_date: formatter.string(from: roundEnd),
                            status: status
                        )
                        
                        try await client
                            .from("challenge_rounds")
                            .insert(newRound)
                            .execute()
                        
                        // Move to next round
                        switch roundDur {
                        case .daily:
                            currentRoundStart = calendar.date(byAdding: .day, value: 1, to: currentRoundStart)!
                        case .weekly:
                            currentRoundStart = calendar.date(byAdding: .weekOfYear, value: 1, to: currentRoundStart)!
                        case .monthly:
                            currentRoundStart = calendar.date(byAdding: .month, value: 1, to: currentRoundStart)!
                        }
                        
                        nextRoundNumber += 1
                        
                        if nextRoundNumber > 1000 {
                            print("Warning: Too many rounds, breaking")
                            break
                        }
                    }
                }
            }
            
            if notifyFeed {
                var goalText = "\(target) \(challenge.metric.unit)"
                if challenge.type == .count {
                    if let endDate = endDate {
                        goalText = "Most \(challenge.metric.displayName) by \(endDate.formatted(date: .abbreviated, time: .omitted))"
                    } else {
                        goalText = "Most \(challenge.metric.displayName)"
                    }
                }
                
                let payload: [String: String] = [
                    "title": title,
                    "metric": challenge.metric.displayName,
                    "goal": goalText
                ]
                await SocialFeedManager.shared.post(type: .challenge_updated, familyId: challenge.family_id, payload: payload)
            }
            
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
    
    // MARK: - Round Management
    
    func loadRounds(for challenge: Challenge) async {
        guard challenge.round_duration != nil else { return }
        
        isLoading = true
        rounds = []
        roundWinCounts = [:]
        
        do {
            let fetchedRounds: [ChallengeRound] = try await client
                .from("challenge_rounds")
                .select()
                .eq("challenge_id", value: challenge.id)
                .order("round_number")
                .execute()
                .value
            
            rounds = fetchedRounds
            
            // Calculate win counts
            var winCounts: [UUID: Int] = [:]
            for round in fetchedRounds {
                if round.status == "completed", let winnerId = round.winner_id {
                    winCounts[winnerId, default: 0] += 1
                }
            }
            roundWinCounts = winCounts
            
        } catch {
            print("Load rounds error: \(error)")
        }
        
        isLoading = false
    }
    
    func loadRoundParticipants(for round: ChallengeRound) async {
        isLoading = true
        currentRoundParticipants = []
        
        do {
            let participants: [RoundParticipant] = try await client
                .from("round_participants")
                .select()
                .eq("round_id", value: round.id)
                .order("rank")
                .execute()
                .value
            
            currentRoundParticipants = participants
            
        } catch {
            print("Load round participants error: \(error)")
        }
        
        isLoading = false
    }
    
    func calculateRoundWinner(for challenge: Challenge, round: ChallengeRound) async {
        guard let duration = challenge.roundDuration else { return }
        
        do {
            // 1. Get profiles
            let profiles: [Profile] = try await client
                .from("profiles")
                .select()
                .eq("family_id", value: challenge.family_id)
                .execute()
                .value
            
            let userIds = profiles.map { $0.id }
            
            // 2. Aggregate stats for the round date range
            // Use date-only format for daily_stats queries (YYYY-MM-DD)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone.current
            
            let startString = dateFormatter.string(from: round.start_date)
            let endString = dateFormatter.string(from: round.end_date)
            
            let stats: [DailyStatDB] = try await client
                .from("daily_stats")
                .select()
                .in("user_id", values: userIds)
                .gte("date", value: startString)
                .lte("date", value: endString)
                .execute()
                .value
            
            // 3. Calculate values
            var participantValues: [(userId: UUID, value: Double)] = []
            
            for profile in profiles {
                let userStats = stats.filter { $0.user_id == profile.id }
                
                var totalValue: Double = 0
                switch challenge.metric {
                case .steps:
                    totalValue = Double(userStats.reduce(0) { $0 + $1.steps })
                case .calories:
                    totalValue = Double(userStats.reduce(0) { $0 + $1.calories })
                case .flights:
                    totalValue = Double(userStats.reduce(0) { $0 + $1.flights })
                case .distance:
                    totalValue = userStats.reduce(0) { $0 + $1.distance }
                case .exercise_minutes:
                    let totalInt = userStats.reduce(into: 0) { $0 += ($1.exercise_minutes ?? 0) }
                    totalValue = Double(totalInt)
                case .workouts:
                    let totalInt = userStats.reduce(into: 0) { $0 += ($1.workouts_count ?? 0) }
                    totalValue = Double(totalInt)
                }
                
                participantValues.append((userId: profile.id, value: totalValue))
            }
            
            // 4. Sort and rank
            participantValues.sort { $0.value > $1.value }
            
            // 5. Insert round_participants
            for (index, participant) in participantValues.enumerated() {
                let roundParticipant = RoundParticipantInsert(
                    round_id: round.id,
                    user_id: participant.userId,
                    value: participant.value,
                    rank: index + 1
                )
                
                try await client
                    .from("round_participants")
                    .upsert(roundParticipant)
                    .execute()
            }
            
            // 6. Determine winner(s) - all with max value
            guard let maxValue = participantValues.first?.value, maxValue > 0 else { return }
            let winners = participantValues.filter { $0.value == maxValue }
            
            // For now, set winner_id to first winner (or handle multiple winners differently)
            if let firstWinner = winners.first {
                try await client
                    .from("challenge_rounds")
                    .update(["winner_id": firstWinner.userId.uuidString, "status": "completed"])
                    .eq("id", value: round.id)
                    .execute()
                
                // Post to feed for each winner
                for winner in winners {
                    if let winnerProfile = profiles.first(where: { $0.id == winner.userId }) {
                        await SocialFeedManager.shared.postRoundWinner(
                            challengeTitle: challenge.title,
                            roundNumber: round.round_number,
                            winnerName: winnerProfile.display_name ?? "Unknown",
                            familyId: challenge.family_id
                        )
                    }
                }
            }
            
        } catch {
            print("Calculate round winner error: \(error)")
        }
    }
    
    func refreshRoundStatuses(for challenge: Challenge) async {
        guard challenge.round_duration != nil else { return }
        
        do {
            let fetchedRounds: [ChallengeRound] = try await client
                .from("challenge_rounds")
                .select()
                .eq("challenge_id", value: challenge.id)
                .execute()
                .value
            
            let now = Date()
            
            for round in fetchedRounds {
                // Check if status needs updating
                if round.status == "active" && now > round.end_date {
                    // Round just ended - calculate winner
                    await calculateRoundWinner(for: challenge, round: round)
                } else if round.status == "pending" && now >= round.start_date {
                    // Round just started
                    try await client
                        .from("challenge_rounds")
                        .update(["status": "active"])
                        .eq("id", value: round.id)
                        .execute()
                }
            }
            
            // Reload rounds after status updates
            await loadRounds(for: challenge)
            
        } catch {
            print("Refresh round statuses error: \(error)")
        }
    }
    
    // MARK: - Challenge Completion
    
    func checkChallengeCompletion(for challenge: Challenge) async {
        // Only check if challenge has ended
        guard challenge.isEnded else { return }
        
        // Check if we've already posted about this challenge completion
        let completionKey = "posted_challenge_won_\(challenge.id.uuidString)"
        if UserDefaults.standard.bool(forKey: completionKey) {
            return
        }
        
        do {
            // Get all participants
            let profiles: [Profile] = try await client
                .from("profiles")
                .select()
                .eq("family_id", value: challenge.family_id)
                .execute()
                .value
            
            let userIds = profiles.map { $0.id }
            
            // Get stats for the challenge period
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let startString = formatter.string(from: challenge.start_date)
            let endString = formatter.string(from: challenge.end_date ?? Date())
            
            let stats: [DailyStatDB] = try await client
                .from("daily_stats")
                .select()
                .in("user_id", values: userIds)
                .gte("date", value: startString)
                .lte("date", value: endString)
                .execute()
                .value
            
            // Calculate totals per user
            var userTotals: [(userId: UUID, value: Double)] = []
            
            for profile in profiles {
                let userStats = stats.filter { $0.user_id == profile.id }
                var totalValue: Double = 0
                
                switch challenge.metric {
                case .steps:
                    totalValue = Double(userStats.reduce(0) { $0 + $1.steps })
                case .calories:
                    totalValue = Double(userStats.reduce(0) { $0 + $1.calories })
                case .flights:
                    totalValue = Double(userStats.reduce(0) { $0 + $1.flights })
                case .distance:
                    totalValue = userStats.reduce(0) { $0 + $1.distance }
                case .exercise_minutes:
                    totalValue = Double(userStats.reduce(into: 0) { $0 += ($1.exercise_minutes ?? 0) })
                case .workouts:
                    totalValue = Double(userStats.reduce(into: 0) { $0 += ($1.workouts_count ?? 0) })
                }
                
                userTotals.append((userId: profile.id, value: totalValue))
            }
            
            // Sort by value descending
            userTotals.sort { $0.value > $1.value }
            
            // Get winner
            guard let winner = userTotals.first,
                  let winnerProfile = profiles.first(where: { $0.id == winner.userId }),
                  winner.value > 0 else {
                // No winner or no one participated
                UserDefaults.standard.set(true, forKey: completionKey)
                return
            }
            
            // Post feed event
            let payload: [String: String] = [
                "challenge_title": challenge.title,
                "winner_name": winnerProfile.display_name ?? winnerProfile.email ?? "Someone",
                "metric": challenge.metric.displayName,
                "value": String(format: "%.0f", winner.value)
            ]
            
            await SocialFeedManager.shared.post(type: .challenge_won, familyId: challenge.family_id, payload: payload)
            
            // Mark as posted
            UserDefaults.standard.set(true, forKey: completionKey)
            
        } catch {
            print("Check challenge completion error: \(error)")
        }
    }
}

// MARK: - Helper Structs for Round Management

struct RoundParticipantInsert: Encodable {
    let round_id: UUID
    let user_id: UUID
    let value: Double
    let rank: Int
}

struct ChallengeRoundInsert: Encodable {
    let challenge_id: UUID
    let round_number: Int
    let start_date: String
    let end_date: String
    let status: String
}
