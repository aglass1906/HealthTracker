
import SwiftUI

// MARK: - Feed Summary Card
struct FeedSummaryCard: View {
    let events: [SocialEvent]
    @Binding var selectedTab: Int // To navigate to Community tab
    @Binding var communityTab: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Community Updates")
                    .font(.headline)
                
                Spacer()
                
                Button("See All") {
                    communityTab = 0 // Feed Tab
                    selectedTab = 2 // Switch to Community Tab
                }
                .font(.subheadline)
            }
            
            if events.isEmpty {
                Text("No recent updates.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(events) { event in
                        HStack(spacing: 12) {
                            // Avatar
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.1))
                                    .frame(width: 32, height: 32)
                                
                                Text(getInitials(for: event.profile))
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.blue)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(eventContent(for: event))
                                    .font(.subheadline)
                                    .lineLimit(1)
                                
                                Text(event.created_at.dateValue().formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
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
    
    
    private func getInitials(for profile: Profile?) -> String {
        guard let profile = profile else { return "?" }
        let name = profile.display_name ?? profile.email ?? "Someone"
        let components = name.components(separatedBy: " ")
        if let first = components.first?.first {
            if components.count > 1, let last = components.last?.first {
                return "\(first)\(last)".uppercased()
            }
            return "\(first)".uppercased()
        }
        return "?"
    }
    
    private func eventContent(for event: SocialEvent) -> String {
        let name = event.profile?.display_name ?? "Someone"
        
        switch event.type {
        case "joined_family":
            return "\(name) joined the family!"
        case "challenge_created":
            return "\(name) created a challenge!"
        case "challenge_won":
            return "\(name) won a challenge!"
        case "round_winner":
            return "\(name) won a round!"
        case "goal_met":
            return "\(name) met a goal!"
        case "workout_finished":
            return "\(name) finished a workout!"
        default:
            return "\(name) posted an update."
        }
    }
}
