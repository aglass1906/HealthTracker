//
//  MorningBriefingView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/11/26.
//

import SwiftUI

struct MorningBriefingView: View {
    @StateObject private var briefingManager = MorningBriefingManager.shared
    let data: DailyHealthData
    var onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Good Morning!")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Here's how yesterday went")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            
            // Rings Summary
            if let rings = data.activityRings {
                HStack(spacing: 15) {
                    MiniRing(progress: rings.move.progress, color: .red, icon: "flame.fill")
                    MiniRing(progress: rings.exercise.progress, color: .green, icon: "figure.run")
                    MiniRing(progress: rings.stand.progress, color: .blue, icon: "figure.stand")
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(data.steps)) steps")
                            .font(.headline)
                        Text("\(Int(data.calories)) kcal burned")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 10)
                    
                    Spacer()
                }
                .padding(.vertical, 10)
            }
            
            // Highlight Message
            if data.steps >= 10000 {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.orange)
                    Text("You hit your 10k step goal!")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }
            
            // Notification Discovery (for existing users or those who skipped)
            if !briefingManager.isNotificationsEnabled {
                Button {
                    Task {
                        let granted = await NotificationManager.shared.requestAuthorization()
                        if granted {
                            withAnimation {
                                briefingManager.isNotificationsEnabled = true
                                briefingManager.rescheduleNotification()
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "bell.badge.fill")
                            .foregroundStyle(.orange)
                        Text("Want this as a daily alert?")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("Enable")
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(12)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 15, x: 0, y: 5)
        }
        .padding(.horizontal)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct MiniRing: View {
    let progress: Double
    let color: Color
    let icon: String
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 6)
                .frame(width: 45, height: 45)
            
            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 45, height: 45)
                .rotationEffect(.degrees(-90))
            
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
        }
    }
}
