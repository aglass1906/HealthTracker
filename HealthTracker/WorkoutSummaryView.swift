//
//  WorkoutSummaryView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/9/26.
//

import SwiftUI

struct WorkoutSummaryView: View {
    let workout: WorkoutData
    let profile: Profile? // Optional: If viewing from feed, show who did it
    @Environment(\.dismiss) private var dismiss
    
    // If no profile is passed, we assume it's the current user (e.g., just finished)
    // or we could fetch current user profile. For now, "You" is sufficient if nil.
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // User Header
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 80, height: 80)
                            
                            if let avatarUrl = profile?.avatar_url, let url = URL(string: avatarUrl) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 80, height: 80)
                                        .clipShape(Circle())
                                } placeholder: {
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 80))
                                        .foregroundStyle(.blue.opacity(0.5))
                                }
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 80))
                                    .foregroundStyle(.blue.opacity(0.5))
                            }
                        }
                        
                        Text(profile?.display_name ?? "You")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("Just finished a workout!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top)
                    
                    // Workout Type Icon
                    VStack(spacing: 12) {
                        Image(systemName: getIcon(for: workout.workoutType))
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)
                            .padding()
                            .background(Circle().fill(Color.blue.opacity(0.1)))
                        
                        Text(workout.workoutType)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Stats Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        StatBox(
                            title: "Duration",
                            value: formatDuration(workout.duration),
                            icon: "clock.fill",
                            color: .orange
                        )
                        
                        if let calories = workout.totalEnergyBurned {
                            StatBox(
                                title: "Calories",
                                value: String(format: "%.0f", calories),
                                unit: "kcal",
                                icon: "flame.fill",
                                color: .red
                            )
                        }
                        
                        if let distance = workout.totalDistance {
                            StatBox(
                                title: "Distance",
                                value: String(format: "%.2f", distance / 1000), // Convert m to km
                                unit: "km",
                                icon: "map.fill",
                                color: .green
                            )
                        }
                        
                        // Placeholder for avg heart rate if we had it in WorkoutData
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom)
            }
            .navigationTitle("Workout Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func getIcon(for type: String) -> String {
        // Simple mapping, could be shared
        if type.contains("Run") { return "figure.run" }
        if type.contains("Walk") { return "figure.walk" }
        if type.contains("Cycle") { return "bicycle" }
        if type.contains("Swim") { return "figure.pool.swim" }
        return "dumbbell.fill"
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

struct StatBox: View {
    let title: String
    let value: String
    var unit: String? = nil
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            VStack(spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                
                if let unit = unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}
