//
//  SocialFeedView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/3/26.
//

import SwiftUI
import Supabase
import Combine

struct SocialEvent: Codable, Identifiable {
    let id: UUID
    let family_id: UUID
    let user_id: UUID
    let type: String
    let payload: [String: String]?
    let created_at: String // ISO string
    
    // Joined profile
    let profile: Profile?
}

class SocialFeedViewModel: ObservableObject {
    @Published var events: [SocialEvent] = []
    @Published var isLoading = false
    
    let client = AuthManager.shared.client
    
    func fetchFeed(for familyId: UUID) async {
        isLoading = true
        
        do {
            // 1. Get profiles for mapping
            let profiles: [Profile] = try await client
                .from("profiles")
                .select()
                .eq("family_id", value: familyId)
                .execute()
                .value
            
            // 2. Get events
            struct EventDB: Codable {
                let id: UUID
                let family_id: UUID
                let user_id: UUID
                let type: String
                let payload: [String: String]?
                let created_at: String
            }
            
            let rawEvents: [EventDB] = try await client
                .from("social_events")
                .select()
                .eq("family_id", value: familyId)
                .order("created_at", ascending: false)
                .limit(20)
                .execute()
                .value
            
            // 3. Map
            self.events = rawEvents.map { event in
                let profile = profiles.first(where: { $0.id == event.user_id })
                return SocialEvent(
                    id: event.id,
                    family_id: event.family_id,
                    user_id: event.user_id,
                    type: event.type,
                    payload: event.payload,
                    created_at: event.created_at,
                    profile: profile
                )
            }
            
        } catch {
            print("Feed fetch error: \(error)")
        }
        
        isLoading = false
    }
}

struct SocialFeedView: View {
    let familyId: UUID
    @StateObject private var viewModel = SocialFeedViewModel()
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Family Feed")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)
            
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if viewModel.events.isEmpty {
                Text("No recent activity.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.events) { event in
                            HStack(alignment: .top) {
                                Image(systemName: "person.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.blue)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(event.profile?.display_name ?? "Someone")
                                            .fontWeight(.bold)
                                        Text(verbatim: timeAgo(from: event.created_at))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Text(description(for: event))
                                        .font(.body)
                                    
                                    // Rich Payload Display
                                    if let payload = event.payload, !payload.isEmpty {
                                        if event.type == "challenge_created" || event.type == "challenge_updated" {
                                            VStack(alignment: .leading, spacing: 2) {
                                                if let title = payload["title"] {
                                                    Text(title)
                                                        .font(.headline)
                                                        .foregroundStyle(.primary)
                                                }
                                                if let goal = payload["goal"] {
                                                    Text("Goal: \(goal)")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            .padding(8)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(8)
                                            .padding(.top, 4)
                                        } else if event.type == "goal_met" {
                                            HStack {
                                                if let goalType = payload["goal"], let value = payload["value"] {
                                                    Image(systemName: iconForGoal(goalType))
                                                        .foregroundStyle(colorForGoal(goalType))
                                                    Text("\(goalType): \(value)")
                                                        .font(.subheadline)
                                                        .fontWeight(.medium)
                                                }
                                            }
                                            .padding(8)
                                            .background(Color(.secondarySystemBackground))
                                            .cornerRadius(8)
                                            .padding(.top, 4)
                                        }
                                    }
                                }
                                Spacer()
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.fetchFeed(for: familyId)
        }
    }
    
    func description(for event: SocialEvent) -> String {
        switch event.type {
        case "workout_finished":
            return "finished a workout! 💪"
        case "goal_met":
            return "hit a daily goal! 🎯"
        case "challenge_won":
            return "won a challenge! 🏆"
        case "challenge_created":
            return "created a new challenge! ⚔️"
        case "challenge_updated":
            return "updated the challenge details. 📝"
        case "joined_family":
            return "joined the family! 👋"
        case "ring_closed_move":
            return "closed their Move ring! 🔥"
        case "ring_closed_exercise":
            return "closed their Exercise ring! 🟢"
        case "ring_closed_stand":
            return "closed their Stand ring! 🔵"
        default:
            return "did something cool."
        }
    }
    
    func timeAgo(from isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else { return "recently" }
        
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        return "\(Int(diff / 86400))d ago"
    }
    
    // MARK: - Helpers
    
    func iconForGoal(_ type: String) -> String {
        switch type {
        case "Steps": return "figure.walk"
        case "Calories": return "flame.fill"
        case "Flights": return "stairs"
        case "Distance": return "map.fill"
        default: return "star.fill"
        }
    }
    
    func colorForGoal(_ type: String) -> Color {
        switch type {
        case "Steps": return .blue
        case "Calories": return .orange
        case "Flights": return .purple
        case "Distance": return .green
        default: return .yellow
        }
    }
}
