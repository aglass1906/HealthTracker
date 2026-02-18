//
//  MorningBriefingView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/11/26.
//

import SwiftUI

struct MorningBriefingView: View {
    @ObservedObject private var briefingManager = MorningBriefingManager.shared
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
            

            
            Spacer()
            
            Button {
                onDismiss()
            } label: {
                Text("Awesome, I'm Ready!")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(16)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        // Removed inner card styling as this now lives in a sheet
        .padding(.horizontal)
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
