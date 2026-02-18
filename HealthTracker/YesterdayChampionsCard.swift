
import SwiftUI

struct YesterdayChampionsCard: View {
    let stepChampion: LeaderboardEntry?
    let flightChampion: LeaderboardEntry?
    let workoutChampion: LeaderboardEntry?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Yesterday's Champions 🏆")
                .font(.headline)
            
            if stepChampion == nil && flightChampion == nil && workoutChampion == nil {
                Text("No data for yesterday.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        if let steps = stepChampion {
                            ChampionItem(
                                icon: "figure.walk",
                                color: .blue,
                                title: "Steps",
                                value: String(steps.steps),
                                profile: steps.profile
                            )
                        }
                        
                        if let flights = flightChampion {
                            ChampionItem(
                                icon: "stairs",
                                color: .green,
                                title: "Flights",
                                value: String(flights.flights),
                                profile: flights.profile
                            )
                        }
                        
                        if let workouts = workoutChampion {
                            ChampionItem(
                                icon: "figure.run",
                                color: .purple,
                                title: "Workouts",
                                value: String(workouts.workouts_count),
                                profile: workouts.profile
                            )
                        }
                    }
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(.separator), lineWidth: 1)
                }
        }
    }
}

struct ChampionItem: View {
    let icon: String
    let color: Color
    let title: String
    let value: String
    let profile: Profile?
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.headline)
            }
            .overlay(alignment: .topTrailing) {
                 Text("👑")
                    .font(.caption2)
                    .offset(x: 4, y: -4)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(profile?.display_name ?? "Unknown")
                    .font(.caption)
                    .fontWeight(.bold)
                    .lineLimit(1)
                
                Text(value)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80, alignment: .leading)
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
