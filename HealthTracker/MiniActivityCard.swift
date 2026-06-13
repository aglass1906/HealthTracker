
import SwiftUI

struct MiniActivityCard: View {
    @ObservedObject var dataStore = HealthDataStore.shared
    @Binding var selectedTab: Int // To navigate to My Data tab
    @Binding var myDataScope: TimeScope
    @Binding var myDataReferenceDate: Date
    
    var body: some View {
        Button {
            myDataScope = .day
            myDataReferenceDate = Date()
            selectedTab = 1 // My Data Tab
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(.orange)
                        .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your Activity Today")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if let steps = dataStore.todayData?.steps {
                            Text("\(Int(steps).formatted()) steps")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No data yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }

                if let rings = dataStore.todayData?.activityRings {
                    HStack(spacing: 12) {
                        ActivityDashboardRing(
                            title: "Move",
                            ring: rings.move,
                            unit: "kcal",
                            color: .red
                        )
                        ActivityDashboardRing(
                            title: "Exercise",
                            ring: rings.exercise,
                            unit: "min",
                            color: .green
                        )
                        ActivityDashboardRing(
                            title: "Stand",
                            ring: rings.stand,
                            unit: "hrs",
                            color: .blue
                        )
                    }
                } else {
                    Text("Activity rings will appear after HealthKit syncs today's data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
    }
}

private struct ActivityDashboardRing: View {
    let title: String
    let ring: RingData
    let unit: String
    let color: Color

    private var percentage: Double {
        guard ring.goal > 0 else { return 0 }
        return ring.value / ring.goal
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

            Text("\(whole(ring.value))/\(whole(ring.goal)) \(unit)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var percentageText: String {
        guard ring.goal > 0 else { return "--" }
        return "\(Int((percentage * 100).rounded()))%"
    }

    private func whole(_ number: Double) -> String {
        number.formatted(.number.precision(.fractionLength(0)))
    }
}

struct RingViewMock: View {
    let progress: Double
    let color: Color
    let size: CGFloat
    let width: CGFloat
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: width)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}
