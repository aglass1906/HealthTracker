//
//  ChallengeDetailView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/4/26.
//

import SwiftUI

struct ChallengeDetailView: View {
    let challenge: Challenge
    @StateObject private var viewModel = ChallengeViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Card
                VStack(spacing: 8) {
                    Image(systemName: challenge.metric.icon)
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                        .padding(.bottom, 8)
                    
                    Text(challenge.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text("Goal: \(challenge.target_value) \(challenge.metric.unit)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(20)
                    
                    VStack(spacing: 4) {
                        Text("Start: \(challenge.start_date.formatted(.dateTime.weekday().hour().minute()))")
                        if let endDate = challenge.end_date {
                            Text("End: \(endDate.formatted(.dateTime.weekday().hour().minute()))")
                        } else {
                            Text("Open Ended")
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
                
                // Leaderboard
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.participants) { participant in
                            ParticipantRow(participant: participant, target: Double(challenge.target_value), metric: challenge.metric)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Challenge")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadProgress(for: challenge)
        }
        .refreshable {
            await viewModel.loadProgress(for: challenge)
        }
    }
}

struct ParticipantRow: View {
    let participant: ChallengeParticipant
    let target: Double
    let metric: ChallengeMetric
    
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
                    Text("\(Int(participant.value)) / \(Int(target))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text("\(Int(participant.progress * 100))%")
                    .font(.headline)
                    .foregroundStyle(participant.progress >= 1.0 ? .green : .blue)
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
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}
