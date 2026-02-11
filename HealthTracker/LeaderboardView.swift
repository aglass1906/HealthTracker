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
    let exercise_minutes: Int
    let workouts_count: Int
    
    // Joined profile
    let profile: Profile?
    
    enum CodingKeys: String, CodingKey {
        case user_id
        case date
        case steps
        case calories
        case flights
        case distance
        case exercise_minutes
        case workouts_count
        case profile
    }
}

class LeaderboardViewModel: ObservableObject {
    @Published var entries: [LeaderboardEntry] = []
    @Published var isLoading = false
    @Published var selectedMetric: HealthMetric = .steps {
        didSet {
            Task { await fetchLeaderboard(for: currentFamilyId) }
        }
    }
    
    private var currentFamilyId: UUID = UUID()
    let client = AuthManager.shared.client
    
    func fetchLeaderboard(for familyId: UUID) async {
        isLoading = true
        currentFamilyId = familyId
        
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
                let exercise_minutes: Int
                let workouts_count: Int
            }
            
            let stats: [DailyStat] = try await client
                .from("daily_stats")
                .select()
                .in("user_id", values: userIds)
                .eq("date", value: today)
                .order(selectedMetric.databaseColumn, ascending: false)
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
                    exercise_minutes: stat.exercise_minutes,
                    workouts_count: stat.workouts_count,
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
            Picker("Metric", selection: $viewModel.selectedMetric) {
                ForEach(HealthMetric.allCases) { metric in
                    Text(metric.displayName).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top)
            
            Text("Today's \(viewModel.selectedMetric.displayName) Leaderboard")
                .font(.headline)
                .padding(.top, 8)
            
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
                                .foregroundStyle(viewModel.selectedMetric.color)
                                .frame(width: 40)
                            
                            VStack(alignment: .leading) {
                                Text(entry.profile?.display_name ?? entry.profile?.email ?? "Unknown")
                                    .fontWeight(.semibold)
                                Text(detailText(for: entry))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            // Visualize relative progress
                            let maxVal = getMetricValue(for: viewModel.entries.first!)
                            if maxVal > 0 {
                                let currentVal = getMetricValue(for: entry)
                                let progress = currentVal / maxVal
                                Circle()
                                    .trim(from: 0, to: progress)
                                    .stroke(viewModel.selectedMetric.color, lineWidth: 4)
                                    .frame(width: 30, height: 30)
                                    .rotationEffect(.degrees(-90))
                                    .overlay {
                                        if index == 0 {
                                            Text("🏆")
                                                .font(.caption2)
                                        } else {
                                            Image(systemName: viewModel.selectedMetric.icon)
                                                .font(.caption2)
                                                .foregroundStyle(viewModel.selectedMetric.color)
                                        }
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
    
    private func getMetricValue(for entry: LeaderboardEntry) -> Double {
        switch viewModel.selectedMetric {
        case .steps: return Double(entry.steps)
        case .calories: return Double(entry.calories)
        case .distance: return entry.distance
        case .flights: return Double(entry.flights)
        case .exercise: return Double(entry.exercise_minutes)
        case .workouts: return Double(entry.workouts_count)
        }
    }
    
    private func detailText(for entry: LeaderboardEntry) -> String {
        let value = getMetricValue(for: entry)
        let unit = viewModel.selectedMetric.unit
        
        if viewModel.selectedMetric == .distance {
             return String(format: "%.2f %@", value, unit)
        } else {
             return String(format: "%.0f %@", value, unit)
        }
    }
}
