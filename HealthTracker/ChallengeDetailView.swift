//
//  ChallengeDetailView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/4/26.
//

import SwiftUI
import Supabase

struct ChallengeDetailView: View {
    let challenge: Challenge
    @StateObject private var viewModel = ChallengeViewModel()
    @State private var showingEdit = false
    @State private var selectedTab = 0
    @State private var leaderboardMode = 1 // 0: Total, 1: Wins
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Card (always visible)
            // Header Card
            VStack(alignment: .leading, spacing: 12) {
                // Row 1: Icon + Title
                HStack(spacing: 12) {
                    Image(systemName: challenge.metric.icon)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.blue)
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(challenge.title)
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        if let creatorName = viewModel.creatorName {
                            Text("by \(creatorName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                
                Divider()
                
                // Row 2: Goal/Metric + Rounds
                HStack {
                    // Goal Pill
                    if challenge.type == .streak {
                        Text("\(challenge.target_value) \(challenge.metric.unit) / day")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.1))
                            .foregroundStyle(.orange)
                            .cornerRadius(8)
                    } else if challenge.type == .count {
                        Text("Most \(challenge.metric.displayName)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.1))
                            .foregroundStyle(.purple)
                            .cornerRadius(8)
                    } else {
                        Text("\(challenge.target_value) \(challenge.metric.unit)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .cornerRadius(8)
                    }
                    
                    Spacer()
                    
                    // Metric & Rounds
                    HStack(spacing: 4) {
                        if let duration = challenge.roundDuration {
                            Text("\(duration.displayName) Rounds")
                                .fontWeight(.medium)
                                .foregroundStyle(.purple)
                        } else {
                            Text(challenge.metric.displayName)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                // Row 3: Dates
                HStack {
                    Label(challenge.start_date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    Spacer()
                    if let endDate = challenge.end_date {
                        Label(endDate.formatted(date: .abbreviated, time: .shortened), systemImage: "flag.checkered")
                    } else {
                        Text("Open Ended")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
            .padding(.horizontal)
            .padding(.top)
            
            // Tab Picker (only for round-based challenges)
            if challenge.round_duration != nil {
                Picker("View", selection: $selectedTab) {
                    Text("Leaderboard").tag(0)
                    Text("Rounds").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
            }
            
            // Content based on selected tab
            if challenge.round_duration != nil {
                if selectedTab == 0 {
                    leaderboardView
                } else {
                    ChallengeRoundsView(challenge: challenge, viewModel: viewModel)
                }
            } else {
                leaderboardView
            }
        }
        .navigationTitle("Challenge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if challenge.creator_id == AuthManager.shared.session?.user.id {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        showingEdit = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingEdit, onDismiss: {
            Task { await viewModel.loadProgress(for: challenge) }
        }) {
            EditChallengeView(challenge: challenge, viewModel: viewModel, onDeleteSuccess: {
                dismiss()
            })
        }
        .task {
            await viewModel.loadProgress(for: challenge)
            if challenge.round_duration != nil {
                await viewModel.refreshRoundStatuses(for: challenge)
            }
        }
        .refreshable {
            await viewModel.loadProgress(for: challenge)
            if challenge.round_duration != nil {
                await viewModel.refreshRoundStatuses(for: challenge)
            }
        }
    }
    
    // MARK: - Leaderboard View
    
    private var sortedWinCounts: [(userId: UUID, wins: Int)] {
        viewModel.roundWinCounts.map { (userId: $0.key, wins: $0.value) }
            .sorted { $0.wins > $1.wins }
    }
    
    private var leaderboardView: some View {
        ScrollView {
            if challenge.round_duration != nil {
                HStack {
                    Text("Standings")
                        .font(.headline)
                    Spacer()
                    Menu {
                        Button {
                            leaderboardMode = 2
                        } label: {
                            Label("Current Round", systemImage: leaderboardMode == 2 ? "checkmark" : "")
                        }
                        Button {
                            leaderboardMode = 1
                        } label: {
                            Label("Most Wins", systemImage: leaderboardMode == 1 ? "checkmark" : "")
                        }
                        Button {
                            leaderboardMode = 0
                        } label: {
                            Label("Total Progress", systemImage: leaderboardMode == 0 ? "checkmark" : "")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(leaderboardMode == 2 ? "Current Round" : (leaderboardMode == 1 ? "Most Wins" : "Total Progress"))
                            Image(systemName: "chevron.down")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            
            if viewModel.isLoading {
                ProgressView()
                    .padding()
            } else {
                LazyVStack(spacing: 16) {
                    if leaderboardMode == 2 && challenge.round_duration != nil {
                        // Current Round ONLY
                        if viewModel.currentRoundStats.isEmpty {
                            Text("No active round")
                                .foregroundStyle(.secondary)
                                .padding()
                        } else {
                            ForEach(viewModel.currentRoundStats) { participant in
                                ParticipantRow(participant: participant, target: Double(challenge.target_value), metric: challenge.metric, type: challenge.type)
                                    .id("\(participant.id)-current")
                            }
                        }
                    } else if leaderboardMode == 1 && challenge.round_duration != nil {
                        // Total Wins ONLY
                        if sortedWinCounts.isEmpty {
                            Text("No wins yet")
                                .foregroundStyle(.secondary)
                                .padding()
                        } else {
                            ForEach(sortedWinCounts, id: \.userId) { item in
                                WinCountRow(userId: item.userId, wins: item.wins, participants: viewModel.participants)
                                    .id("\(item.userId)-wins")
                            }
                        }
                    } else {
                        // Total Progress
                        ForEach(viewModel.participants) { participant in
                            ParticipantRow(participant: participant, target: Double(challenge.target_value), metric: challenge.metric, type: challenge.type)
                                .id("\(participant.id)-total")
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical)
                .id(leaderboardMode) // Force refresh when switching modes
            }
        }
    }
}

struct ParticipantRow: View {
    let participant: ChallengeParticipant
    let target: Double
    let metric: ChallengeMetric
    let type: ChallengeType // Pass type down
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                // Rank Badge
                ZStack {
                    Circle()
                        .fill(participant.rank == 1 ? Color.yellow : Color.gray.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Text("#\(participant.rank)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(participant.rank == 1 ? .white : .primary)
                }
                
                VStack(alignment: .leading) {
                    Text(participant.profile.display_name ?? "Unknown")
                        .fontWeight(.semibold)
                    
                    if type == .streak {
                        Text("\(Int(participant.value)) Day Streak")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if type == .count {
                        Text("\(Int(participant.value)) \(metric.unit)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(Int(participant.value)) / \(Int(target))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if type != .count {
                    Text("\(Int(participant.progress * 100))%")
                        .font(.headline)
                        .foregroundStyle(participant.progress >= 1.0 ? .green : .blue)
                }
            }
            
            // Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 12)
                    
                    Capsule()
                        .fill(participant.progress >= 1.0 ? Color.green : Color.blue)
                        .frame(width: min(geometry.size.width * participant.progress, geometry.size.width), height: 12)
                }
            }
            .frame(height: 12)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}
