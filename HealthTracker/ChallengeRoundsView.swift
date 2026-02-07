//
//  ChallengeRoundsView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/6/26.
//

import SwiftUI

struct ChallengeRoundsView: View {
    let challenge: Challenge
    @ObservedObject var viewModel: ChallengeViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Current Round (if active)
                if let currentRound = viewModel.rounds.first(where: { $0.status == "active" }) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Current Round")
                                .font(.headline)
                            
                            Spacer()
                            
                            Text("LIVE")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red)
                                .cornerRadius(8)
                        }
                        .padding(.horizontal)
                        
                        // Current Round Info Card
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(roundLabel(for: currentRound))
                                    .font(.title3)
                                    .fontWeight(.bold)
                                
                                Spacer()
                            }
                            
                            HStack {
                                Text(currentRound.start_date.formatted(.dateTime.month().day()))
                                Text("–")
                                Text(currentRound.end_date.formatted(.dateTime.month().day()))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            
                            if !viewModel.currentRoundParticipants.isEmpty {
                                Divider()
                                    .padding(.vertical, 4)
                                
                                Text("Live Rankings")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                
                                ForEach(viewModel.currentRoundParticipants) { participant in
                                    CurrentRoundParticipantRow(
                                        participant: participant,
                                        allParticipants: viewModel.participants,
                                        metric: challenge.metric
                                    )
                                }
                            } else {
                                Text("No data yet for this round")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            }
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                        )
                        .padding(.horizontal)
                    }
                }
                
                // Overall Leaderboard (by wins)
                if !viewModel.roundWinCounts.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Overall Leaderboard")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        VStack(spacing: 12) {
                            ForEach(sortedWinCounts, id: \.userId) { item in
                                WinCountRow(userId: item.userId, wins: item.wins, participants: viewModel.participants)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                // Rounds History
                VStack(alignment: .leading, spacing: 12) {
                    Text("Rounds")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    if viewModel.isLoading {
                        ProgressView()
                            .padding()
                    } else if viewModel.rounds.isEmpty {
                        Text("No rounds yet")
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        VStack(spacing: 16) {
                            ForEach(viewModel.rounds) { round in
                                RoundCard(round: round, challenge: challenge, participants: viewModel.participants)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .task {
            await viewModel.refreshRoundStatuses(for: challenge)
            await viewModel.loadRounds(for: challenge)
            if let activeRound = viewModel.rounds.first(where: { $0.status == "active" }) {
                await viewModel.loadRoundParticipants(for: activeRound)
            }
        }
        .refreshable {
            await viewModel.refreshRoundStatuses(for: challenge)
            await viewModel.loadRounds(for: challenge)
            if let activeRound = viewModel.rounds.first(where: { $0.status == "active" }) {
                await viewModel.loadRoundParticipants(for: activeRound)
            }
        }
    }
    
    private func roundLabel(for round: ChallengeRound) -> String {
        guard let duration = challenge.roundDuration else { return "Round \(round.round_number)" }
        
        switch duration {
        case .daily:
            return "Day \(round.round_number)"
        case .weekly:
            return "Week \(round.round_number)"
        case .monthly:
            return "Month \(round.round_number)"
        }
    }
    
    private var sortedWinCounts: [(userId: UUID, wins: Int)] {
        viewModel.roundWinCounts.map { (userId: $0.key, wins: $0.value) }
            .sorted { $0.wins > $1.wins }
    }
}

struct WinCountRow: View {
    let userId: UUID
    let wins: Int
    let participants: [ChallengeParticipant]
    
    var userName: String {
        participants.first(where: { $0.id == userId })?.profile.display_name ?? "Unknown"
    }
    
    var body: some View {
        HStack {
            Image(systemName: "trophy.fill")
                .foregroundStyle(.yellow)
            
            Text(userName)
                .fontWeight(.semibold)
            
            Spacer()
            
            Text("\(wins) \(wins == 1 ? "win" : "wins")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct RoundCard: View {
    let round: ChallengeRound
    let challenge: Challenge
    let participants: [ChallengeParticipant]
    
    var roundLabel: String {
        guard let duration = challenge.roundDuration else { return "Round \(round.round_number)" }
        
        switch duration {
        case .daily:
            return "Day \(round.round_number)"
        case .weekly:
            return "Week \(round.round_number)"
        case .monthly:
            return "Month \(round.round_number)"
        }
    }
    
    var winnerName: String? {
        guard let winnerId = round.winner_id else { return nil }
        return participants.first(where: { $0.id == winnerId })?.profile.display_name ?? "Unknown"
    }
    
    var statusColor: Color {
        round.status == "completed" ? .green : .blue
    }
    
    var statusText: String {
        round.status == "completed" ? "Completed" : "Active"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(roundLabel)
                    .font(.headline)
                
                Spacer()
                
                Text(statusText)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor)
                    .cornerRadius(8)
            }
            
            HStack {
                Text(round.start_date.formatted(.dateTime.month().day()))
                Text("–")
                Text(round.end_date.formatted(.dateTime.month().day()))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
            if let winner = winnerName {
                HStack {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text("Winner: \(winner)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct CurrentRoundParticipantRow: View {
    let participant: RoundParticipant
    let allParticipants: [ChallengeParticipant]
    let metric: ChallengeMetric
    
    var userName: String {
        allParticipants.first(where: { $0.id == participant.user_id })?.profile.display_name ?? "Unknown"
    }
    
    var rankColor: Color {
        guard let rank = participant.rank else { return .gray }
        return rank == 1 ? .yellow : .gray.opacity(0.3)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Rank badge
            ZStack {
                Circle()
                    .fill(rankColor)
                    .frame(width: 28, height: 28)
                
                if let rank = participant.rank {
                    Text("#\(rank)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(rank == 1 ? .white : .primary)
                }
            }
            
            // User name
            Text(userName)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Spacer()
            
            // Value
            Text("\(Int(participant.value)) \(metric.unit)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 4)
    }
}
