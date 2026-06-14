import Foundation
import Supabase
import Combine

struct ChallengeParticipant: Identifiable {
    let id: UUID
    let profile: Profile
    let value: Double
    var progress: Double
    var rank: Int = 0
}

struct MetricLeaderboard: Identifiable {
    var id: ChallengeMetric { metric }
    let metric: ChallengeMetric
    let participants: [ChallengeParticipant]
}

struct ChallengeStanding: Identifiable {
    var id: UUID { profile.id }
    let profile: Profile
    let wins: Int
    var rank: Int
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
    let move_ring_value: Double?
    let exercise_ring_value: Double?
    let stand_ring_value: Double?
    let all_rings_closed: Int?
}

final class ChallengeViewModel: ObservableObject {
    @Published var activeChallenges: [Challenge] = []
    @Published var participants: [ChallengeParticipant] = []
    @Published var creatorName: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var rounds: [ChallengeRound] = []
    @Published var currentRoundParticipants: [RoundParticipant] = []
    @Published var roundWinCounts: [UUID: Int] = [:]
    @Published var currentRoundStats: [ChallengeParticipant] = []
    @Published var challengeMetrics: [ChallengeMetric] = []
    @Published var metricLeaderboards: [MetricLeaderboard] = []
    @Published var currentRoundLeaderboards: [MetricLeaderboard] = []
    @Published var overallStandings: [ChallengeStanding] = []
    @Published var metricWinners: [ChallengeMetricWinner] = []

    @Published var selectedFilter: ChallengeFilter = .all

    enum ChallengeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case recent = "Recent"
        case ended = "Ended"

        var id: String { rawValue }
    }

    private struct ChallengeInsert: Encodable {
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

    private struct ChallengeUpdate: Encodable {
        let title: String
        let metric: ChallengeMetric
        let target_value: Int
        let start_date: String
        let end_date: String?
    }

    private struct ChallengeMetricInsert: Encodable {
        let challenge_id: UUID
        let metric: ChallengeMetric
        let display_order: Int
    }

    private struct ChallengeMetricWinnerInsert: Encodable {
        let challenge_id: UUID
        let round_id: UUID?
        let metric: ChallengeMetric
        let user_id: UUID
        let value: Double
    }

    private let client = AuthManager.shared.client

    var filteredChallenges: [Challenge] {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let filtered: [Challenge]

        switch selectedFilter {
        case .all:
            filtered = activeChallenges
        case .active:
            filtered = activeChallenges.filter { !$0.isEnded }
        case .recent:
            filtered = activeChallenges.filter {
                guard let endDate = $0.end_date else { return false }
                return $0.isEnded && endDate >= sevenDaysAgo
            }
        case .ended:
            filtered = activeChallenges.filter {
                guard let endDate = $0.end_date else { return false }
                return $0.isEnded && endDate < sevenDaysAgo
            }
        }

        return filtered.sorted {
            if $0.isEnded != $1.isEnded {
                return !$0.isEnded
            }
            let firstEnd = $0.end_date ?? .distantFuture
            let secondEnd = $1.end_date ?? .distantFuture
            return $0.isEnded ? firstEnd > secondEnd : firstEnd < secondEnd
        }
    }

    // MARK: - Metrics and scoring

    func fetchMetrics(for challenge: Challenge) async -> [ChallengeMetric] {
        do {
            let records: [ChallengeMetricRecord] = try await client
                .from("challenge_metrics")
                .select()
                .eq("challenge_id", value: challenge.id)
                .order("display_order")
                .execute()
                .value
            return records.isEmpty ? [challenge.metric] : records.map(\.metric)
        } catch {
            print("Fetch challenge metrics error: \(error)")
            return [challenge.metric]
        }
    }

    private func aggregateValue(for metric: ChallengeMetric, stats: [DailyStatDB]) -> Double {
        stats.reduce(0) { $0 + dailyValue(for: metric, stat: $1) }
    }

    private func dailyValue(for metric: ChallengeMetric, stat: DailyStatDB) -> Double {
        switch metric {
        case .steps: return Double(stat.steps)
        case .calories: return Double(stat.calories)
        case .distance: return stat.distance
        case .exercise_minutes: return Double(stat.exercise_minutes ?? 0)
        case .flights: return Double(stat.flights)
        case .workouts: return Double(stat.workouts_count ?? 0)
        case .move_ring: return stat.move_ring_value ?? 0
        case .exercise_ring: return stat.exercise_ring_value ?? 0
        case .stand_ring: return stat.stand_ring_value ?? 0
        case .all_rings_closed: return Double(stat.all_rings_closed ?? 0)
        }
    }

    private func longestStreak(metric: ChallengeMetric, target: Int, stats: [DailyStatDB]) -> Double {
        let qualifyingDates = Set(stats.compactMap { stat -> Date? in
            guard dailyValue(for: metric, stat: stat) >= Double(target) else { return nil }
            return Self.dayFormatter.date(from: stat.date)
        })
        guard !qualifyingDates.isEmpty else { return 0 }

        let sortedDates = qualifyingDates.sorted()
        var longest = 1
        var current = 1

        for index in 1..<sortedDates.count {
            let days = Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: sortedDates[index - 1]),
                to: Calendar.current.startOfDay(for: sortedDates[index])
            ).day
            if days == 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return Double(longest)
    }

    private func buildLeaderboards(
        metrics: [ChallengeMetric],
        type: ChallengeType,
        target: Int,
        profiles: [Profile],
        stats: [DailyStatDB]
    ) -> [MetricLeaderboard] {
        metrics.map { metric in
            var metricParticipants = profiles.map { profile -> ChallengeParticipant in
                let userStats = stats.filter { $0.user_id == profile.id }
                let value = type == .streak
                    ? longestStreak(metric: metric, target: target, stats: userStats)
                    : aggregateValue(for: metric, stats: userStats)
                return ChallengeParticipant(id: profile.id, profile: profile, value: value, progress: 0)
            }

            metricParticipants.sort {
                if $0.value == $1.value {
                    return ($0.profile.display_name ?? "") < ($1.profile.display_name ?? "")
                }
                return $0.value > $1.value
            }

            let maxValue = metricParticipants.first?.value ?? 0
            var previousValue: Double?
            var previousRank = 0
            for index in metricParticipants.indices {
                let rank = previousValue == metricParticipants[index].value ? previousRank : index + 1
                metricParticipants[index].rank = rank
                previousValue = metricParticipants[index].value
                previousRank = rank

                if type == .race {
                    metricParticipants[index].progress = target > 0
                        ? metricParticipants[index].value / Double(target)
                        : 0
                } else {
                    metricParticipants[index].progress = maxValue > 0
                        ? metricParticipants[index].value / maxValue
                        : 0
                }
            }
            return MetricLeaderboard(metric: metric, participants: metricParticipants)
        }
    }

    private func standings(
        profiles: [Profile],
        winners: [ChallengeMetricWinner],
        liveLeaderboards: [MetricLeaderboard] = []
    ) -> [ChallengeStanding] {
        var winCounts: [UUID: Int] = [:]

        if winners.isEmpty {
            for leaderboard in liveLeaderboards {
                guard let topValue = leaderboard.participants.first?.value, topValue > 0 else { continue }
                for participant in leaderboard.participants where participant.value == topValue {
                    winCounts[participant.id, default: 0] += 1
                }
            }
        } else {
            for winner in winners {
                winCounts[winner.user_id, default: 0] += 1
            }
        }

        var result = profiles.map {
            ChallengeStanding(profile: $0, wins: winCounts[$0.id, default: 0], rank: 0)
        }
        result.sort {
            if $0.wins == $1.wins {
                return ($0.profile.display_name ?? "") < ($1.profile.display_name ?? "")
            }
            return $0.wins > $1.wins
        }

        var previousWins: Int?
        var previousRank = 0
        for index in result.indices {
            let rank = previousWins == result[index].wins ? previousRank : index + 1
            result[index].rank = rank
            previousWins = result[index].wins
            previousRank = rank
        }
        return result
    }

    private func fetchStats(userIds: [UUID], start: Date, end: Date) async throws -> [DailyStatDB] {
        guard !userIds.isEmpty else { return [] }
        return try await client
            .from("daily_stats")
            .select()
            .in("user_id", values: userIds)
            .gte("date", value: Self.dayFormatter.string(from: start))
            .lte("date", value: Self.dayFormatter.string(from: end))
            .execute()
            .value
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // MARK: - Fetch and create

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
            activeChallenges = challenges
            for challenge in challenges where challenge.status != .completed {
                await checkChallengeCompletion(for: challenge)
            }
        } catch {
            print("Fetch challenges error: \(error)")
            errorMessage = "Failed to load challenges."
        }
        isLoading = false
    }

    func createChallenge(
        familyId: UUID,
        title: String,
        type: ChallengeType,
        metrics: [ChallengeMetric],
        target: Int,
        startDate: Date,
        endDate: Date?,
        roundDuration: RoundDuration? = nil
    ) async -> Bool {
        guard let userId = AuthManager.shared.session?.user.id, let primaryMetric = metrics.first else {
            return false
        }
        let selectedMetrics = type == .count ? metrics : [primaryMetric]
        let insert = ChallengeInsert(
            family_id: familyId,
            creator_id: userId,
            title: title,
            type: type,
            metric: primaryMetric,
            target_value: target,
            start_date: Self.isoFormatter.string(from: startDate),
            end_date: endDate.map(Self.isoFormatter.string),
            status: .active,
            round_duration: roundDuration?.rawValue,
            current_round_number: roundDuration == nil ? nil : 1
        )

        do {
            let created: [Challenge] = try await client
                .from("challenges")
                .insert(insert)
                .select()
                .execute()
                .value
            guard let challenge = created.first else { return false }

            try await insertMetrics(selectedMetrics, challengeId: challenge.id)
            if let roundDuration {
                try await createRounds(
                    challengeId: challenge.id,
                    duration: roundDuration,
                    startDate: startDate,
                    endDate: endDate ?? startDate
                )
            }

            let metricNames = selectedMetrics.map(\.displayName).joined(separator: ", ")
            let goal = type == .count ? "Most \(metricNames)" : "\(target) \(primaryMetric.unit)"
            await SocialFeedManager.shared.post(
                type: .challenge_created,
                familyId: familyId,
                payload: [
                    "title": title,
                    "metric": metricNames,
                    "goal": goal,
                    "challenge_id": challenge.id.uuidString
                ]
            )
            await fetchActiveChallenges(for: familyId)
            return true
        } catch {
            print("Create challenge error: \(error)")
            errorMessage = "Failed to create challenge: \(error.localizedDescription)"
            return false
        }
    }

    private func insertMetrics(_ metrics: [ChallengeMetric], challengeId: UUID) async throws {
        let inserts = metrics.enumerated().map {
            ChallengeMetricInsert(challenge_id: challengeId, metric: $0.element, display_order: $0.offset)
        }
        try await client.from("challenge_metrics").insert(inserts).execute()
    }

    private func createRounds(
        challengeId: UUID,
        duration: RoundDuration,
        startDate: Date,
        endDate: Date
    ) async throws {
        let calendar = Calendar.current
        var roundStart = calendar.startOfDay(for: startDate)
        var roundNumber = 1

        while roundStart < endDate, roundNumber <= 1000 {
            let nextStart: Date
            switch duration {
            case .daily:
                nextStart = calendar.date(byAdding: .day, value: 1, to: roundStart)!
            case .weekly:
                nextStart = calendar.date(byAdding: .weekOfYear, value: 1, to: roundStart)!
            case .monthly:
                nextStart = calendar.date(byAdding: .month, value: 1, to: roundStart)!
            }
            let roundEnd = min(nextStart.addingTimeInterval(-1), endDate)
            let status = Date() < roundStart ? "pending" : "active"
            let insert = ChallengeRoundInsert(
                challenge_id: challengeId,
                round_number: roundNumber,
                start_date: Self.isoFormatter.string(from: roundStart),
                end_date: Self.isoFormatter.string(from: roundEnd),
                status: status
            )
            try await client.from("challenge_rounds").insert(insert).execute()
            roundStart = nextStart
            roundNumber += 1
        }
    }

    // MARK: - Progress

    func loadProgress(for challenge: Challenge) async {
        isLoading = true
        do {
            let profiles = await CommunityMembershipManager.shared.fetchMembers(for: challenge.family_id)
            creatorName = profiles.first(where: { $0.id == challenge.creator_id })?.display_name
            let metrics = await fetchMetrics(for: challenge)
            challengeMetrics = metrics
            let end = min(Date(), challenge.end_date ?? Date())
            let stats = try await fetchStats(
                userIds: profiles.map(\.id),
                start: challenge.start_date,
                end: end
            )
            let leaderboards = buildLeaderboards(
                metrics: challenge.type == .count ? metrics : [challenge.metric],
                type: challenge.type,
                target: challenge.target_value,
                profiles: profiles,
                stats: stats
            )
            metricLeaderboards = leaderboards
            participants = leaderboards.first?.participants ?? []

            let storedWinners: [ChallengeMetricWinner] = try await client
                .from("challenge_metric_winners")
                .select()
                .eq("challenge_id", value: challenge.id)
                .is("round_id", value: nil)
                .execute()
                .value
            metricWinners = storedWinners
            overallStandings = standings(
                profiles: profiles,
                winners: storedWinners,
                liveLeaderboards: leaderboards
            )

            if challenge.type == .race,
               leaderboards.first?.participants.first?.value ?? 0 >= Double(challenge.target_value) {
                await checkChallengeCompletion(for: challenge)
            } else if challenge.isEnded {
                await checkChallengeCompletion(for: challenge)
            }
        } catch {
            print("Load progress error: \(error)")
            errorMessage = "Failed to load challenge progress."
        }
        isLoading = false
    }

    // MARK: - Edit and delete

    func updateChallenge(
        challenge: Challenge,
        title: String,
        metrics: [ChallengeMetric],
        target: Int,
        startDate: Date,
        endDate: Date?,
        notifyFeed: Bool
    ) async -> Bool {
        guard AuthManager.shared.session?.user.id == challenge.creator_id,
              challenge.finalized_at == nil,
              let primaryMetric = metrics.first else { return false }
        let selectedMetrics = challenge.type == .count ? metrics : [primaryMetric]
        let update = ChallengeUpdate(
            title: title,
            metric: primaryMetric,
            target_value: target,
            start_date: Self.isoFormatter.string(from: startDate),
            end_date: endDate.map(Self.isoFormatter.string)
        )

        do {
            try await client.from("challenges").update(update).eq("id", value: challenge.id).execute()
            try await client.from("challenge_metrics").delete().eq("challenge_id", value: challenge.id).execute()
            try await insertMetrics(selectedMetrics, challengeId: challenge.id)

            if let duration = challenge.roundDuration,
               let endDate,
               endDate > (challenge.end_date ?? challenge.start_date) {
                let existing: [ChallengeRound] = try await client
                    .from("challenge_rounds")
                    .select()
                    .eq("challenge_id", value: challenge.id)
                    .order("round_number", ascending: false)
                    .execute()
                    .value
                if let last = existing.first {
                    try await appendRounds(
                        challengeId: challenge.id,
                        duration: duration,
                        after: last,
                        endDate: endDate
                    )
                }
            }

            if notifyFeed {
                let names = selectedMetrics.map(\.displayName).joined(separator: ", ")
                await SocialFeedManager.shared.post(
                    type: .challenge_updated,
                    familyId: challenge.family_id,
                    payload: [
                        "title": title,
                        "metric": names,
                        "goal": challenge.type == .count ? "Most \(names)" : "\(target) \(primaryMetric.unit)",
                        "status": challenge.status.rawValue,
                        "challenge_id": challenge.id.uuidString
                    ]
                )
            }
            return true
        } catch {
            print("Update challenge error: \(error)")
            errorMessage = "Failed to update challenge."
            return false
        }
    }

    private func appendRounds(
        challengeId: UUID,
        duration: RoundDuration,
        after lastRound: ChallengeRound,
        endDate: Date
    ) async throws {
        let calendar = Calendar.current
        var start = calendar.startOfDay(for: lastRound.end_date.addingTimeInterval(1))
        var number = lastRound.round_number + 1
        while start < endDate, number <= 1000 {
            let next: Date
            switch duration {
            case .daily: next = calendar.date(byAdding: .day, value: 1, to: start)!
            case .weekly: next = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
            case .monthly: next = calendar.date(byAdding: .month, value: 1, to: start)!
            }
            let insert = ChallengeRoundInsert(
                challenge_id: challengeId,
                round_number: number,
                start_date: Self.isoFormatter.string(from: start),
                end_date: Self.isoFormatter.string(from: min(next.addingTimeInterval(-1), endDate)),
                status: Date() < start ? "pending" : "active"
            )
            try await client.from("challenge_rounds").insert(insert).execute()
            start = next
            number += 1
        }
    }

    func deleteChallenge(challengeId: UUID) async -> Bool {
        do {
            try await client.from("challenges").delete().eq("id", value: challengeId).execute()
            return true
        } catch {
            print("Delete challenge error: \(error)")
            errorMessage = "Failed to delete challenge."
            return false
        }
    }

    // MARK: - Rounds

    func loadRounds(for challenge: Challenge) async {
        guard challenge.round_duration != nil else { return }
        isLoading = true
        do {
            rounds = try await client
                .from("challenge_rounds")
                .select()
                .eq("challenge_id", value: challenge.id)
                .order("round_number")
                .execute()
                .value

            let winners: [ChallengeMetricWinner] = try await client
                .from("challenge_metric_winners")
                .select()
                .eq("challenge_id", value: challenge.id)
                .not("round_id", operator: .is, value: "null")
                .execute()
                .value
            metricWinners = winners
            roundWinCounts = Dictionary(grouping: winners, by: \.user_id).mapValues(\.count)

            let profiles = participants.map(\.profile)
            overallStandings = standings(profiles: profiles, winners: winners)
        } catch {
            print("Load rounds error: \(error)")
        }
        isLoading = false
    }

    func loadRoundParticipants(for round: ChallengeRound) async {
        do {
            currentRoundParticipants = try await client
                .from("round_participants")
                .select()
                .eq("round_id", value: round.id)
                .order("rank")
                .execute()
                .value
        } catch {
            print("Load round participants error: \(error)")
        }
    }

    func fetchRoundLeaderboards(
        for challenge: Challenge,
        round: ChallengeRound
    ) async -> [MetricLeaderboard] {
        do {
            let profiles = await CommunityMembershipManager.shared.fetchMembers(for: challenge.family_id)
            let metrics = await fetchMetrics(for: challenge)
            let stats = try await fetchStats(
                userIds: profiles.map(\.id),
                start: round.start_date,
                end: min(Date(), round.end_date)
            )
            return buildLeaderboards(
                metrics: challenge.type == .count ? metrics : [challenge.metric],
                type: challenge.type,
                target: challenge.target_value,
                profiles: profiles,
                stats: stats
            )
        } catch {
            print("Fetch round stats error: \(error)")
            return []
        }
    }

    func fetchRoundStats(for challenge: Challenge, round: ChallengeRound) async -> [ChallengeParticipant] {
        await fetchRoundLeaderboards(for: challenge, round: round).first?.participants ?? []
    }

    func calculateRoundWinner(for challenge: Challenge, round: ChallengeRound) async {
        guard round.finalized_at == nil else { return }
        let leaderboards = await fetchRoundLeaderboards(for: challenge, round: round)
        guard !leaderboards.isEmpty else { return }

        for leaderboard in leaderboards {
            await persistWinners(
                challengeId: challenge.id,
                roundId: round.id,
                leaderboard: leaderboard
            )
        }

        do {
            let primaryWinner = leaderboards.first?.participants.first
            let claimed: [ChallengeRound] = try await client
                .from("challenge_rounds")
                .update([
                    "winner_id": primaryWinner?.id.uuidString,
                    "status": "completed",
                    "finalized_at": Self.isoFormatter.string(from: Date())
                ])
                .eq("id", value: round.id)
                .is("finalized_at", value: nil)
                .select()
                .execute()
                .value
            guard !claimed.isEmpty else { return }

            let winnerNames = Set(leaderboards.flatMap { leaderboard in
                guard let top = leaderboard.participants.first?.value, top > 0 else { return [String]() }
                return leaderboard.participants
                    .filter { $0.value == top }
                    .map { $0.profile.display_name ?? $0.profile.email ?? "Unknown" }
            }).sorted().joined(separator: ", ")

            await SocialFeedManager.shared.post(
                type: .round_winner,
                familyId: challenge.family_id,
                payload: [
                    "challenge_title": challenge.title,
                    "round_number": String(round.round_number),
                    "winner_name": winnerNames,
                    "metric": leaderboards.map { $0.metric.displayName }.joined(separator: ", "),
                    "challenge_id": challenge.id.uuidString
                ]
            )
        } catch {
            print("Calculate round winner error: \(error)")
        }
    }

    private func persistWinners(
        challengeId: UUID,
        roundId: UUID?,
        leaderboard: MetricLeaderboard
    ) async {
        guard let topValue = leaderboard.participants.first?.value, topValue > 0 else { return }
        for participant in leaderboard.participants where participant.value == topValue {
            let insert = ChallengeMetricWinnerInsert(
                challenge_id: challengeId,
                round_id: roundId,
                metric: leaderboard.metric,
                user_id: participant.id,
                value: participant.value
            )
            do {
                try await client.from("challenge_metric_winners").insert(insert).execute()
            } catch {
                // The unique indexes make concurrent finalization harmless.
                print("Persist metric winner skipped: \(error)")
            }
        }
    }

    func refreshCurrentRoundStats(for challenge: Challenge) async {
        guard let active = rounds.first(where: { $0.status == "active" }) else {
            currentRoundStats = []
            currentRoundLeaderboards = []
            return
        }
        let leaderboards = await fetchRoundLeaderboards(for: challenge, round: active)
        currentRoundLeaderboards = leaderboards
        currentRoundStats = leaderboards.first?.participants ?? []
    }

    func fetchChallenge(id: UUID) async -> Challenge? {
        do {
            let challenges: [Challenge] = try await client
                .from("challenges")
                .select()
                .eq("id", value: id)
                .execute()
                .value
            return challenges.first
        } catch {
            print("Fetch single challenge error: \(error)")
            return nil
        }
    }

    func refreshRoundStatuses(for challenge: Challenge) async {
        guard challenge.round_duration != nil else { return }
        do {
            let fetched: [ChallengeRound] = try await client
                .from("challenge_rounds")
                .select()
                .eq("challenge_id", value: challenge.id)
                .execute()
                .value
            let now = Date()

            for round in fetched {
                if round.finalized_at == nil, now > round.end_date {
                    await calculateRoundWinner(for: challenge, round: round)
                } else if round.status == "pending", now >= round.start_date, now <= round.end_date {
                    try await client
                        .from("challenge_rounds")
                        .update(["status": "active"])
                        .eq("id", value: round.id)
                        .execute()
                }
            }
            await loadRounds(for: challenge)
            await refreshCurrentRoundStats(for: challenge)
        } catch {
            print("Refresh round statuses error: \(error)")
        }
    }

    // MARK: - Completion

    func checkChallengeCompletion(for challenge: Challenge) async {
        guard challenge.finalized_at == nil, challenge.status != .completed else { return }
        guard challenge.type == .race || challenge.isEnded else { return }

        let profiles = await CommunityMembershipManager.shared.fetchMembers(for: challenge.family_id)
        let metrics = await fetchMetrics(for: challenge)
        let effectiveMetrics = challenge.type == .count ? metrics : [challenge.metric]

        do {
            if challenge.round_duration != nil {
                await refreshRoundStatuses(for: challenge)
            }

            let stats = try await fetchStats(
                userIds: profiles.map(\.id),
                start: challenge.start_date,
                end: min(Date(), challenge.end_date ?? Date())
            )
            let leaderboards = buildLeaderboards(
                metrics: effectiveMetrics,
                type: challenge.type,
                target: challenge.target_value,
                profiles: profiles,
                stats: stats
            )

            if challenge.type == .race,
               (leaderboards.first?.participants.first?.value ?? 0) < Double(challenge.target_value),
               !challenge.isEnded {
                return
            }

            for leaderboard in leaderboards {
                await persistWinners(challengeId: challenge.id, roundId: nil, leaderboard: leaderboard)
            }

            let overallWinners: [Profile]
            let winningValue: String
            let winningMetric: String

            if challenge.round_duration != nil {
                let roundWinners: [ChallengeMetricWinner] = try await client
                    .from("challenge_metric_winners")
                    .select()
                    .eq("challenge_id", value: challenge.id)
                    .not("round_id", operator: .is, value: "null")
                    .execute()
                    .value
                let finalStandings = standings(profiles: profiles, winners: roundWinners)
                let topWins = finalStandings.first?.wins ?? 0
                overallWinners = finalStandings.filter { $0.wins == topWins && topWins > 0 }.map(\.profile)
                winningValue = "\(topWins) wins"
                winningMetric = "Metric Wins"
            } else if challenge.type == .count {
                let finalStandings = standings(profiles: profiles, winners: [], liveLeaderboards: leaderboards)
                let topWins = finalStandings.first?.wins ?? 0
                overallWinners = finalStandings.filter { $0.wins == topWins && topWins > 0 }.map(\.profile)
                winningValue = "\(topWins) wins"
                winningMetric = "Metric Wins"
            } else {
                guard let topValue = leaderboards.first?.participants.first?.value, topValue > 0 else {
                    await markChallengeCompleted(challenge, winnerNames: nil, metric: nil, value: nil)
                    return
                }
                overallWinners = leaderboards.first?.participants
                    .filter { $0.value == topValue }
                    .map(\.profile) ?? []
                winningValue = String(format: "%.0f", topValue)
                winningMetric = challenge.type == .streak ? "Day Streak" : challenge.metric.displayName
            }

            let names = overallWinners.map { $0.display_name ?? $0.email ?? "Unknown" }
            await markChallengeCompleted(
                challenge,
                winnerNames: names.isEmpty ? nil : names.joined(separator: ", "),
                metric: winningMetric,
                value: winningValue
            )
        } catch {
            print("Check challenge completion error: \(error)")
        }
    }

    private func markChallengeCompleted(
        _ challenge: Challenge,
        winnerNames: String?,
        metric: String?,
        value: String?
    ) async {
        do {
            let claimed: [Challenge] = try await client
                .from("challenges")
                .update([
                    "status": ChallengeStatus.completed.rawValue,
                    "finalized_at": Self.isoFormatter.string(from: Date())
                ])
                .eq("id", value: challenge.id)
                .is("finalized_at", value: nil)
                .select()
                .execute()
                .value
            guard !claimed.isEmpty, let winnerNames, let metric, let value else { return }

            await SocialFeedManager.shared.post(
                type: .challenge_won,
                familyId: challenge.family_id,
                payload: [
                    "challenge_title": challenge.title,
                    "winner_name": winnerNames,
                    "metric": metric,
                    "value": value,
                    "challenge_id": challenge.id.uuidString
                ]
            )
        } catch {
            print("Complete challenge error: \(error)")
        }
    }
}

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
