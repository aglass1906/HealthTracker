//
//  AchievementSummaryView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/11/26.
//

import SwiftUI

struct AchievementSummaryView: View {
    let event: SocialEvent
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 150, height: 150)
                
                Image(systemName: iconName)
                    .font(.system(size: 80))
                    .foregroundStyle(iconColor)
            }
            .padding(.bottom, 20)
            
            // Text
            VStack(spacing: 12) {
                Text(title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            
            // Value Card
            if let value = valueText {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(iconColor)
                    Text(value)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.top, 10)
            }
            
            Spacer()
            
            Text("Keep it up!")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
            
            Button {
                dismiss()
            } label: {
                Text("Awesome")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(16)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding()
    }
    
    // MARK: - Helpers
    
    var title: String {
        switch event.type {
        case "goal_met":
            return "Goal Met!"
        case "ring_closed_move":
            return "Move Ring Closed!"
        case "ring_closed_exercise":
            return "Exercise Ring Closed!"
        case "ring_closed_stand":
            return "Stand Ring Closed!"
        case "challenge_won":
            return "Challenge Won!"
        case "round_winner":
            return "Round Winner!"
        case "challenge_created":
            return "New Challenge!"
        case "challenge_updated":
            return "Challenge Updated!"
        default:
            return "Great Job!"
        }
    }
    
    var subtitle: String {
        guard let name = event.profile?.display_name else { return "Someone did something great." }
        
        switch event.type {
        case "goal_met":
            if let goal = event.payload?["goal"] {
                return "\(name) reached their daily goal for \(goal)!"
            }
            return "\(name) reached a goal!"
        case "ring_closed_move", "ring_closed_exercise", "ring_closed_stand":
            return "\(name) closed their activity ring!"
        case "challenge_won":
            if let winner = event.payload?["winner_name"] {
                if let title = event.payload?["challenge_title"] {
                    return "\(winner) won the '\(title)' challenge!"
                }
                return "\(winner) won a challenge!"
            }
            // Fallback to profile name if payload missing (unlikely for new events)
            if let title = event.payload?["challenge_title"] {
                return "\(name) won the '\(title)' challenge!"
            }
            return "\(name) won a challenge!"
            
        case "round_winner":
            if let winner = event.payload?["winner_name"] {
                 if let title = event.payload?["challenge_title"], let round = event.payload?["round_number"] {
                     return "\(winner) won Round \(round) of '\(title)'!"
                 }
                 return "\(winner) won a round!"
            }
             // Fallback
             if let title = event.payload?["challenge_title"], let round = event.payload?["round_number"] {
                 return "\(name) won Round \(round) of '\(title)'!"
             }
             return "\(name) won a round!"
             
        case "challenge_created":
            // For creation, the poster IS usually the creator, so 'name' is fine.
            if let title = event.payload?["title"] {
                return "\(name) created '\(title)'!"
            }
            return "\(name) created a new challenge!"
            
        case "challenge_updated":
             // Similarly for updates
            if let title = event.payload?["title"] {
                return "\(name) updated '\(title)'."
            }
            return "\(name) updated a challenge."
            
        default:
            return "Congratulations to \(name)!"
        }
    }
    
    var valueText: String? {
        if let value = event.payload?["value"] {
            // For challenges, we might want to append the metric unit if available
            if let metric = event.payload?["metric"] {
                return "\(value) \(metric)"
            }
            return value
        }
        if let goal = event.payload?["goal"] {
            return "Goal: \(goal)"
        }
        return nil
    }
    
    var iconName: String {
        switch event.type {
        case "goal_met": return "trophy.fill"
        case "ring_closed_move": return "flame.fill"
        case "ring_closed_exercise": return "figure.run"
        case "ring_closed_stand": return "figure.stand"
        case "challenge_won": return "trophy.circle.fill"
        case "round_winner": return "medal.fill"
        case "challenge_created": return "flag.checkered"
        case "challenge_updated": return "arrow.triangle.2.circlepath"
        default: return "star.fill"
        }
    }
    
    var iconColor: Color {
        switch event.type {
        case "goal_met": return .yellow
        case "ring_closed_move": return .red
        case "ring_closed_exercise": return .green
        case "ring_closed_stand": return .blue
        case "challenge_won": return .yellow
        case "round_winner": return .purple
        case "challenge_created": return .purple
        case "challenge_updated": return .cyan
        default: return .blue
        }
    }
}
