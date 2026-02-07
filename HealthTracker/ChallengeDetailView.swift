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
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Card (always visible)
            ScrollView {
                VStack(spacing: 8) {
                    Image(systemName: challenge.metric.icon)
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                        .padding(.bottom, 8)
                    
                    Text(challenge.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    if challenge.type == .streak {
                        Text("Goal: \(challenge.target_value) \(challenge.metric.unit) / day")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(20)
                    } else if challenge.type == .count {
                        Text("Goal: Most \(challenge.metric.displayName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(20)
                    } else {
                        Text("Goal: \(challenge.target_value) \(challenge.metric.unit)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(20)
                    }
                    
                    VStack(spacing: 4) {
                        Text("Metric: \(challenge.metric.displayName)")
                        if let duration = challenge.roundDuration {
                            Text("Rounds: \(duration.displayName)")
                                .fontWeight(.semibold)
                                .foregroundStyle(.purple)
                        }
                        Text("Start: \(challenge.start_date.formatted(.dateTime.weekday().hour().minute()))")
                        if let endDate = challenge.end_date {
                            Text("End: \(endDate.formatted(.dateTime.weekday().hour().minute()))")
                        } else {
                            Text("Open Ended")
                        }
                        if let creatorName = viewModel.creatorName {
                            Text("Created by \(creatorName)")
                                .padding(.top, 4)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
                .padding(.horizontal)
                .padding(.top)
            }
            .frame(height: 280)
            
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
        }
        .refreshable {
            await viewModel.loadProgress(for: challenge)
        }
    }
    
    // MARK: - Leaderboard View
    
    private var leaderboardView: some View {
        ScrollView {
            if viewModel.isLoading {
                ProgressView()
                    .padding()
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.participants) { participant in
                        ParticipantRow(participant: participant, target: Double(challenge.target_value), metric: challenge.metric, type: challenge.type)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical)
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
