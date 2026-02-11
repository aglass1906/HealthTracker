//
//  SocialFeedView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/3/26.
//

import SwiftUI
import Supabase
import HealthKit
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
        
        // Background check for challenge completions to ensure feed is up to date
        Task {
            let challengeVM = ChallengeViewModel()
            await challengeVM.fetchActiveChallenges(for: familyId)
        }
    }
}

struct SocialFeedView: View {
    let familyId: UUID
    @StateObject private var viewModel = SocialFeedViewModel()
    @StateObject private var briefingManager = MorningBriefingManager.shared
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Family Feed")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)
            
            if viewModel.isLoading && viewModel.events.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if viewModel.events.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "newspaper")
                        .font(.system(size: 60))
                        .foregroundStyle(.gray.opacity(0.3))
                    Text("No Family Activity Yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Complete a workout or join a challenge to see updates here!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if briefingManager.shouldShowBriefing, let data = briefingManager.briefingData {
                            MorningBriefingView(data: data) {
                                withAnimation {
                                    briefingManager.dismissBriefing()
                                }
                            }
                            .padding(.top, 8)
                        }
                        
                        ForEach(viewModel.events) { event in
                            SocialFeedItem(event: event)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.bottom)
                }
                .refreshable {
                    await viewModel.fetchFeed(for: familyId)
                }
            }
        }
        .task {
            if viewModel.events.isEmpty {
                await viewModel.fetchFeed(for: familyId)
            }
        }
    }
    
}

// MARK: - Helpers

private func iconForGoal(_ type: String) -> String {
    switch type {
    case "Steps": return "figure.walk"
    case "Calories": return "flame.fill"
    case "Flights": return "stairs"
    case "Distance": return "map.fill"
    default: return "star.fill"
    }
}

private func colorForGoal(_ type: String) -> Color {
    switch type {
    case "Steps": return .blue
    case "Calories": return .orange
    case "Flights": return .purple
    case "Distance": return .green
    default: return .yellow
    }
}

struct SocialFeedItem: View {
    let event: SocialEvent
    @State private var selectedWorkout: WorkoutData?
    @State private var selectedChallenge: Challenge?
    @State private var showingAchievement = false
    @State private var showingWelcome = false
    @State private var hapticTrigger = false

    @StateObject private var challengeVM = ChallengeViewModel()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                // Avatar
                if let avatarUrl = event.profile?.avatar_url, let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.gray.opacity(0.3))
                    }
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.gray.opacity(0.3))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    if (event.type == "challenge_won" || event.type == "round_winner"),
                       let winnerName = event.payload?["winner_name"] {
                        Text(winnerName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    } else {
                        Text(event.profile?.display_name ?? "Someone")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    
                    Text(timeAgo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Icon based on type
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(iconColor)
            }
            
            // Content
            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
            
            // Payload Display
            if let payload = event.payload {
                if event.type == "workout_finished" {
                    workoutStatsView(payload: payload)
                } else if event.type == "goal_met" {
                    HStack {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(.yellow)
                        Text(payload["goal"] ?? "Goal")
                            .fontWeight(.bold)
                        Spacer()
                        Text(payload["value"] ?? "")
                            .font(.headline)
                    }
                    .padding()
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(12)
                } else if event.type == "round_winner" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(payload["challenge_title"] ?? "")
                            .font(.headline)
                        
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(.yellow)
                            Text("Round \(payload["round_number"] ?? "1") Winner")
                                .font(.subheadline)
                                .fontWeight(.bold)
                        }
                        
                        HStack {
                            Text("Winner:")
                                .foregroundStyle(.secondary)
                            Text(payload["winner_name"] ?? "")
                                .fontWeight(.bold)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(12)
                } else if event.type == "challenge_created",
                          let title = payload["title"],
                          let goal = payload["goal"] {
                    HStack {
                        Image(systemName: "flag.checkered")
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading) {
                            Text(title)
                                .fontWeight(.semibold)
                            Text("Goal: \(goal)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(12)
                } else if event.type == "challenge_updated",
                          let title = payload["title"],
                          let status = payload["status"] {
                    HStack {
                        Image(systemName: "flag.checkered")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text(title)
                                .fontWeight(.semibold)
                            Text("Status: \(status.capitalized)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                } else if event.type == "challenge_won" {
                    VStack(alignment: .leading, spacing: 4) {
                        if let challengeTitle = payload["challenge_title"] {
                            HStack {
                                Image(systemName: "trophy.fill")
                                    .foregroundStyle(.yellow)
                                Text(challengeTitle)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                            }
                        }
                        if let metric = payload["metric"], let value = payload["value"] {
                            Text("\(value) \(metric)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.yellow)
                        }
                    }
                    .padding(8)
                    .background(Color.yellow.opacity(0.15))
                    .cornerRadius(8)
                    .padding(.top, 4)
                } else if event.type.starts(with: "ring_closed") {
                   HStack {
                       Image(systemName: iconName)
                           .foregroundStyle(iconColor)
                       Text("Closed Ring")
                           .fontWeight(.semibold)
                       Spacer()
                   }
                   .padding()
                   .background(iconColor.opacity(0.1))
                   .cornerRadius(12)
               }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .onTapGesture {
            handleTap()
        }
        .sheet(item: $selectedWorkout) { workout in
            WorkoutSummaryView(workout: workout, profile: event.profile)
        }
        .sheet(item: $selectedChallenge) { challenge in
            NavigationView {
                ChallengeDetailView(challenge: challenge)
            }
        }
        .sheet(isPresented: $showingAchievement) {
            AchievementSummaryView(event: event)
        }
        .alert("Welcome!", isPresented: $showingWelcome) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Welcome \(event.profile?.display_name ?? "User") to the family!")
        }
        .sensoryFeedback(.impact, trigger: hapticTrigger)
    }
    
    // MARK: - Navigation Logic
    
    private func handleTap() {
        hapticTrigger.toggle()
        print("DEBUG: Tapped event type: \(event.type)")
        print("DEBUG: Payload: \(String(describing: event.payload))")
        
        if event.type == "workout_finished" {
            selectedWorkout = reconstructWorkout(from: event.payload)
        } else if event.type.starts(with: "challenge_") || event.type == "round_winner" {
            // Need challenge ID
            if let uuidString = event.payload?["challenge_id"] {
                print("DEBUG: Found challenge_id: \(uuidString)")
                if let uuid = UUID(uuidString: uuidString) {
                    Task {
                        print("DEBUG: Fetching challenge \(uuid)...")
                        if let challenge = await challengeVM.fetchChallenge(id: uuid) {
                            print("DEBUG: Challenge fetched successfully: \(challenge.title)")
                            await MainActor.run {
                                self.selectedChallenge = challenge
                            }
                        } else {
                            print("DEBUG: Failed to fetch challenge")
                            await MainActor.run {
                                // Fallback to summary view if challenge deleted/not found
                                self.showingAchievement = true
                            }
                        }
                    }
                } else {
                    print("DEBUG: Invalid UUID string")
                     // Fallback to summary view
                    showingAchievement = true
                }
            } else {
                print("DEBUG: No challenge_id in payload")
                 // Fallback to summary view
                showingAchievement = true
            }
        } else if event.type == "goal_met" || event.type.starts(with: "ring_closed") {
            showingAchievement = true
        } else if event.type == "joined_family" {
            showingWelcome = true
        }
    }
    
    private func workoutStatsView(payload: [String: String]) -> some View {
        HStack(spacing: 16) {
            if let duration = payload["duration"] {
                Label(duration, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if let calories = payload["calories"] {
                Label("\(calories) kcal", systemImage: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if let distance = payload["distance"] {
                Label("\(distance) km", systemImage: "location.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }
    
    private func reconstructWorkout(from payload: [String: String]?) -> WorkoutData? {
        guard let payload = payload else { return nil }
        
        return WorkoutData(
            id: UUID().uuidString,
            workoutType: payload["workout_type"] ?? "Workout",
            startDate: Date(),
            endDate: Date(),
            duration: 0,
            totalEnergyBurned: Double(payload["calories"] ?? "0"),
            totalDistance: (Double(payload["distance"] ?? "0") ?? 0) * 1000
        )
    }
    
    var timeAgo: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Try parsing with fractional seconds first
        var date = formatter.date(from: event.created_at)
        
        // Fallback to standard ISO8601 if failed
        if date == nil {
            date = ISO8601DateFormatter().date(from: event.created_at)
        }
        
        guard let validDate = date else { return "Just now" }
        
        let diff = Date().timeIntervalSince(validDate)
        
        // Just now for < 1 minute
        if diff < 60 && diff > -60 {
            return "Just now"
        }
        
        // Relative for < 24 hours
        if diff < 86400 {
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.unitsStyle = .abbreviated
            return relativeFormatter.localizedString(for: validDate, relativeTo: Date())
        }
        
        // Absolute date for older events
        let absoluteFormatter = DateFormatter()
        absoluteFormatter.dateFormat = "MMM d 'at' h:mm a"
        return absoluteFormatter.string(from: validDate)
    }
    
    var description: String {
        switch event.type {
        case "joined_family":
            return "joined the family!"
        case "challenge_created":
            return "created a new challenge!"
        case "challenge_won":
            return "won the challenge! 🏆"
        case "round_winner":
            return "won a round! 🥇"
        case "goal_met":
            return "crushed a goal! 🎯"
        case "workout_finished":
            if let type = event.payload?["workout_type"] {
                return "finished a \(type) workout! 💪"
            }
            return "finished a workout! 💪"
        case "ring_closed_move":
            return "closed their Move ring! 🔴"
        case "ring_closed_exercise":
            return "closed their Exercise ring! 🟢"
        case "ring_closed_stand":
            return "closed their Stand ring! 🔵"
        case "challenge_updated":
            return "updated a challenge 🔄"
        default:
            return "did something cool."
        }
    }
    
    var iconName: String {
        switch event.type {
        case "joined_family": return "person.2.fill"
        case "challenge_created": return "flag.checkered"
        case "challenge_won": return "trophy.fill"
        case "round_winner": return "medal.fill"
        case "goal_met": return "target"
        case "workout_finished": return "figure.run"
        case "ring_closed_move": return "circle.fill"
        case "ring_closed_exercise": return "circle.fill"
        case "ring_closed_stand": return "circle.fill"
        case "challenge_updated": return "arrow.triangle.2.circlepath"
        default: return "star.fill"
        }
    }
    
    var iconColor: Color {
        switch event.type {
        case "joined_family": return .blue
        case "challenge_created": return .purple
        case "challenge_won": return .yellow
        case "goal_met": return .green
        case "workout_finished": return .orange
        case "ring_closed_move": return .red
        case "ring_closed_exercise": return .green
        case "ring_closed_stand": return .blue
        case "challenge_updated": return .cyan
        default: return .gray
        }
    }
}
