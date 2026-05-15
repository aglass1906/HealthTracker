//
//  MorningBriefingView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/11/26.
//

import SwiftUI

struct MorningBriefingView: View {
    @ObservedObject private var briefingManager = MorningBriefingManager.shared
    @ObservedObject private var nutritionManager = NutritionManager.shared
    let data: DailyHealthData
    var onDismiss: () -> Void
    @State private var yesterdayNutritionTotals = NutritionDayTotals()
    @State private var isLoadingNutrition = false
    
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

            // Nutrition Summary
            nutritionSummary
            
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
        .task {
            await loadYesterdayNutrition()
        }
    }

    @ViewBuilder
    private var nutritionSummary: some View {
        if let goal = nutritionManager.activeGoal {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Nutrition")
                            .font(.headline)
                        Text(goal.goal_type.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isLoadingNutrition {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("\(formatWhole(yesterdayNutritionTotals.calories)) kcal")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 14) {
                    MacroCompletionRing(
                        label: "Protein",
                        grams: yesterdayNutritionTotals.protein_g,
                        targetGrams: goal.protein_g,
                        caloriePercent: macroCaloriePercent(grams: yesterdayNutritionTotals.protein_g, caloriesPerGram: 4),
                        color: .blue
                    )

                    MacroCompletionRing(
                        label: "Carbs",
                        grams: yesterdayNutritionTotals.carb_g,
                        targetGrams: goal.carb_g,
                        caloriePercent: macroCaloriePercent(grams: yesterdayNutritionTotals.carb_g, caloriesPerGram: 4),
                        color: .green
                    )

                    MacroCompletionRing(
                        label: "Fat",
                        grams: yesterdayNutritionTotals.fat_g,
                        targetGrams: goal.fat_g,
                        caloriePercent: macroCaloriePercent(grams: yesterdayNutritionTotals.fat_g, caloriesPerGram: 9),
                        color: .orange
                    )
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
        } else if isLoadingNutrition {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Loading nutrition")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    @MainActor
    private func loadYesterdayNutrition() async {
        isLoadingNutrition = true
        defer { isLoadingNutrition = false }

        await nutritionManager.loadActiveGoal()

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        yesterdayNutritionTotals = await nutritionManager.dailyTotals(for: yesterday)
    }

    private func macroCaloriePercent(grams: Double, caloriesPerGram: Double) -> Double {
        guard yesterdayNutritionTotals.calories > 0 else { return 0 }
        return (grams * caloriesPerGram) / yesterdayNutritionTotals.calories
    }

    private func formatWhole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
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

private struct MacroCompletionRing: View {
    let label: String
    let grams: Double
    let targetGrams: Double
    let caloriePercent: Double
    let color: Color

    private var progress: Double {
        guard targetGrams > 0 else { return 0 }
        return min(max(grams / targetGrams, 0), 1)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: 7)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(Int((caloriePercent * 100).rounded()))%")
                        .font(.subheadline)
                        .fontWeight(.bold)
                    Text("\(Int(grams.rounded()))/\(Int(targetGrams.rounded()))g")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(width: 76, height: 76)

            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(Int(grams.rounded())) of \(Int(targetGrams.rounded())) grams, \(Int((caloriePercent * 100).rounded())) percent of calories")
    }
}
