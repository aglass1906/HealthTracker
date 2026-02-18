
import SwiftUI

struct ActiveChallengeCard: View {
    let challenge: Challenge
    @Binding var selectedTab: Int
    @Binding var communityTab: Int
    
    var body: some View {
        Button {
            communityTab = 2 // Challenges Tab
            selectedTab = 2 // Community Tab
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("Active Challenge")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    Text("Ends \(challenge.end_date?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Placeholder for leader info or progress bar
                // For now, simple indicator
                HStack {
                    Text(daysRemaining(challenge.end_date))
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.blue.opacity(0.1)))
                        .foregroundStyle(.blue)
                    
                    Spacer()
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
        .buttonStyle(.plain)
    }
    
    private func daysRemaining(_ date: Date?) -> String {
        guard let date = date else { return " ongoing" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days < 0 { return "Ended" }
        return "\(days) days left"
    }
}
