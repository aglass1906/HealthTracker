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
    
    @State private var selectedFilter: RoundFilter = .all
    
    enum RoundFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case past = "Past"
        case upcoming = "Future"
        
        var id: String { self.rawValue }
    }
    
    var filteredRounds: [ChallengeRound] {
        switch selectedFilter {
        case .all:
            return viewModel.rounds
        case .active:
            return viewModel.rounds.filter { $0.status == "active" }
        case .past:
            return viewModel.rounds.filter { $0.status == "completed" }
        case .upcoming:
            return viewModel.rounds.filter { $0.status == "upcoming" || ($0.status != "active" && $0.status != "completed") }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header & Filter
                HStack {
                    Text("Rounds")
                        .font(.headline)
                    Spacer()
                    Menu {
                        ForEach(RoundFilter.allCases) { filter in
                            Button {
                                selectedFilter = filter
                            } label: {
                                Label(filter.rawValue, systemImage: selectedFilter == filter ? "checkmark" : "")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedFilter.rawValue)
                            Image(systemName: "chevron.down")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                    }
                }
                .padding(.horizontal)
                .padding(.top)

                // Rounds List
                if viewModel.isLoading {
                    ProgressView()
                        .padding()
                } else if filteredRounds.isEmpty {
                    ContentUnavailableView {
                        Label("No rounds found", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Try changing the filter")
                    }
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(filteredRounds) { round in
                            RoundCard(round: round, challenge: challenge, participants: viewModel.participants)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
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
