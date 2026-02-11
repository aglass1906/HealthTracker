//
//  ChallengesListView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/4/26.
//

import SwiftUI

struct ChallengesListView: View {
    let familyId: UUID
    @StateObject private var viewModel = ChallengeViewModel()
    
    var body: some View {
        VStack {
            if viewModel.isLoading && viewModel.activeChallenges.isEmpty {
                ProgressView()
                    .padding()
            } else if viewModel.activeChallenges.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "flag.checkered.circle")
                        .font(.system(size: 60))
                        .foregroundStyle(.gray.opacity(0.3))
                    Text("No Active Challenges")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Start a race to compete with your family!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)
            } else {
                List {
                    Section {
                        Picker("Filter", selection: $viewModel.selectedFilter) {
                            ForEach(ChallengeViewModel.ChallengeFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical, 8)
                    }
                    
                    ForEach(viewModel.filteredChallenges) { challenge in
                        NavigationLink(destination: ChallengeDetailView(challenge: challenge)) {
                            HStack {
                                Image(systemName: challenge.metric.icon)
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(challenge.isEnded ? Color.gray : Color.blue)
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading) {
                                    Text(challenge.title)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(challenge.isEnded ? .secondary : .primary)
                                    Text(challengeDescription(for: challenge))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    if !challenge.start_date_string.isEmpty {
                                        Text("\(formattedDate(challenge.start_date)) - \(formattedDate(challenge.end_date ?? Date()))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                if !challenge.isEnded {
                                    Text("ACTIVE")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green)
                                        .cornerRadius(4)
                                } else {
                                    // Check if recent (ended < 7 days ago)
                                    if let endDate = challenge.end_date, endDate >= Calendar.current.date(byAdding: .day, value: -7, to: Date())! {
                                        Text("RECENT")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.orange)
                                            .cornerRadius(4)
                                    } else {
                                        Text("ENDED")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.gray)
                                            .cornerRadius(4)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .refreshable {
                    await viewModel.fetchActiveChallenges(for: familyId)
                }
                .sensoryFeedback(.selection, trigger: viewModel.selectedFilter)
            }
            
        }
        .task {
            // Refetch when view appears (e.g. switched tabs)
            if viewModel.activeChallenges.isEmpty {
                await viewModel.fetchActiveChallenges(for: familyId)
            }
        }
    }
    
    // MARK: - Helper
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    private func challengeDescription(for challenge: Challenge) -> String {
        var parts: [String] = []
        
        // Add type description
        if challenge.type == .count {
            parts.append("Leaderboard")
        } else {
            parts.append(challenge.type.title)
        }
        
        // Add round duration if applicable
        if let roundDuration = challenge.roundDuration {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: challenge.start_date)
            let end = challenge.end_date ?? challenge.start_date
            
            // Calculate number of rounds
            var roundCount = 0
            switch roundDuration {
            case .daily:
                roundCount = calendar.dateComponents([.day], from: start, to: end).day ?? 0
            case .weekly:
                roundCount = calendar.dateComponents([.weekOfYear], from: start, to: end).weekOfYear ?? 0
            case .monthly:
                roundCount = calendar.dateComponents([.month], from: start, to: end).month ?? 0
            }
            
            if roundCount > 0 {
                parts.append("\(roundDuration.displayName) Rounds (\(roundCount))")
            } else {
                parts.append("\(roundDuration.displayName) Rounds")
            }
        }
        
        // Add target/goal
        if challenge.type == .count {
            parts.append("Most \(challenge.metric.displayName)")
        } else if challenge.type == .streak {
            parts.append("\(challenge.target_value) \(challenge.metric.unit)/day")
        } else {
            parts.append("First to \(challenge.target_value) \(challenge.metric.unit)")
        }
        
        return parts.joined(separator: " • ")
    }
}
