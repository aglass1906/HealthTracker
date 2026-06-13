import SwiftUI

struct MiniNutritionCard: View {
    @ObservedObject var nutritionManager = NutritionManager.shared
    @Binding var selectedTab: Int
    @State private var totals = NutritionDayTotals()
    @State private var isLoading = false

    var body: some View {
        Button {
            selectedTab = 3
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Image(systemName: "leaf.circle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(.green)
                        .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Nutrition Today")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if let goal = nutritionManager.activeGoal {
                            Text(goal.goal_type.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else if totals.calories > 0 {
                            Text("\(formatWhole(totals.calories)) kcal logged")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Set a nutrition goal")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }

                if let goal = nutritionManager.activeGoal {
                    VStack(spacing: 8) {
                        miniProgressRow(
                            "Calories",
                            current: totals.calories,
                            target: goal.daily_calories,
                            unit: "kcal",
                            color: .orange
                        )

                        HStack(spacing: 12) {
                            DashboardNutritionMacroRing(
                                title: "Protein",
                                value: totals.protein_g,
                                goal: goal.protein_g,
                                color: .blue
                            )
                            DashboardNutritionMacroRing(
                                title: "Carbs",
                                value: totals.carb_g,
                                goal: goal.carb_g,
                                color: .orange
                            )
                            DashboardNutritionMacroRing(
                                title: "Fat",
                                value: totals.fat_g,
                                goal: goal.fat_g,
                                color: .purple
                            )
                        }

                        HStack(spacing: 10) {
                            miniNutrient("Sugar", value: totals.sugar_g, target: goal.sugar_g, unit: "g", isLimit: true)
                            miniNutrient("Sodium", value: totals.sodium_mg, target: goal.sodium_mg, unit: "mg", isLimit: true)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .task {
            await refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task { await refresh() }
        }
        .onChange(of: selectedTab) { _, newValue in
            guard newValue == 0 else { return }
            Task { await refresh() }
        }
    }

    private func miniProgressRow(_ title: String, current: Double, target: Double, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(targetText(current: current, target: target, unit: unit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if target > 0 {
                ProgressView(value: progress(current: current, target: target))
                    .tint(color)
            }
        }
    }

    private func miniNutrient(
        _ title: String,
        value: Double,
        target: Double,
        unit: String,
        isLimit: Bool = false,
        showsPercent: Bool = false
    ) -> some View {
        let overLimit = isLimit && target > 0 && value > target

        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if showsPercent {
                Text(percentUsed(value, target))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
            }
            Text("\(formatWhole(value))/\(formatWhole(target))\(unit)")
                .font(showsPercent ? .caption2 : .caption)
                .fontWeight(.regular)
                .foregroundStyle(overLimit ? Color.red : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            if overLimit {
                Text("+\(formatWhole(value - target))")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        await nutritionManager.loadActiveGoal()
        totals = await nutritionManager.dailyTotals(for: Date())
    }

    private func progress(current: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        return min(max(current / target, 0), 1)
    }

    private func formatWhole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    private func targetText(current: Double, target: Double, unit: String) -> String {
        guard target > 0 else {
            return "\(formatWhole(current)) \(unit)"
        }
        return "\(formatWhole(current)) / \(formatWhole(target)) \(unit)"
    }

    private func percentUsed(_ current: Double, _ target: Double) -> String {
        guard target > 0 else { return "--" }
        return "\(Int((100 * current / target).rounded()))%"
    }
}

private struct DashboardNutritionMacroRing: View {
    let title: String
    let value: Double
    let goal: Double
    let color: Color

    private var percentage: Double {
        guard goal > 0 else { return 0 }
        return value / goal
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 9)

                Circle()
                    .trim(from: 0, to: min(max(percentage, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text(percentageText)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 64, height: 64)
            .animation(.easeInOut, value: percentage)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)

            Text("\(whole(value))/\(whole(goal))g")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private var percentageText: String {
        guard goal > 0 else { return "--" }
        return "\(Int((percentage * 100).rounded()))%"
    }

    private func whole(_ number: Double) -> String {
        number.formatted(.number.precision(.fractionLength(0)))
    }
}
