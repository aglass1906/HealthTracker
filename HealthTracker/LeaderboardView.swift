//
//  LeaderboardView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/3/26.
//

import SwiftUI
import Supabase
import Combine

struct LeaderboardEntry: Identifiable, Codable {
    let id = UUID() // Local ID for UI
    let user_id: UUID
    let date: String
    let steps: Int
    let calories: Int
    let flights: Int
    let distance: Double
    
    // Joined profile
    let profile: Profile?
    
    enum CodingKeys: String, CodingKey {
        case user_id
        case date
        case steps
        case calories
        case flights
        case distance
        case profile
    }
}

class LeaderboardViewModel: ObservableObject {
    @Published var entries: [LeaderboardEntry] = []
    @Published var isLoading = false
    
    let client = AuthManager.shared.client
    
    func fetchLeaderboard(for familyId: UUID) async {
        isLoading = true
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        
        do {
            // 1. Get all profiles in family to map names
            let profiles: [Profile] = try await client
                .from("profiles")
                .select()
                .eq("family_id", value: familyId)
                .execute()
                .value
            
            // 2. Get today's stats for these users
            let userIds = profiles.map { $0.id }
            
            struct DailyStat: Codable {
                let user_id: UUID
                let date: String
                let steps: Int
                let calories: Int
                let flights: Int
                let distance: Double
            }
            
            let stats: [DailyStat] = try await client
                .from("daily_stats")
                .select()
                .in("user_id", values: userIds)
                .eq("date", value: today)
                .order("steps", ascending: false) // Rank by steps by default
                .execute()
                .value
            
            // 3. Merge
            self.entries = stats.map { stat in
                let profile = profiles.first(where: { $0.id == stat.user_id })
                return LeaderboardEntry(
                    user_id: stat.user_id,
                    date: stat.date,
                    steps: stat.steps,
                    calories: stat.calories,
                    flights: stat.flights,
                    distance: stat.distance,
                    profile: profile
                )
            }
        } catch {
            print("Leaderboard fetch error: \(error)")
        }
        
        isLoading = false
    }
}

struct LeaderboardView: View {
    let familyId: UUID
    @StateObject private var viewModel = LeaderboardViewModel()
    
    var body: some View {
        VStack {
            Text("Today's Leaderboard")
                .font(.headline)
                .padding(.top)
            
            if viewModel.isLoading {
                ProgressView()
                    .padding()
            } else if viewModel.entries.isEmpty {
                Text("No data for today yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List {
                    ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                        HStack {
                            Text("#\(index + 1)")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundStyle(.blue)
                                .frame(width: 40)
                            
                            VStack(alignment: .leading) {
                                Text(entry.profile?.display_name ?? entry.profile?.email ?? "Unknown")
                                    .fontWeight(.semibold)
                                Text("\(entry.steps) steps")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            // Visualize relative progress
                            if let maxSteps = viewModel.entries.first?.steps, maxSteps > 0 {
                                let progress = Double(entry.steps) / Double(maxSteps)
                                Circle()
                                    .trim(from: 0, to: progress)
                                    .stroke(Color.blue, lineWidth: 4)
                                    .frame(width: 30, height: 30)
                                    .rotationEffect(.degrees(-90))
                                    .overlay {
                                        Text("🏆")
                                            .font(.caption2)
                                            .opacity(index == 0 ? 1 : 0)
                                    }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .task {
            await viewModel.fetchLeaderboard(for: familyId)
        }
        .refreshable {
            await viewModel.fetchLeaderboard(for: familyId)
        }
    }
}
