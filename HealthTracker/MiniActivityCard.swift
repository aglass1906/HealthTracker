
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
            HStack(spacing: 16) {
                // Mini Rings
                if let rings = dataStore.todayData?.activityRings {
                    ZStack {
                        RingViewMock(progress: rings.move.progress, color: .red, size: 40, width: 4)
                        RingViewMock(progress: rings.exercise.progress, color: .green, size: 28, width: 4)
                        RingViewMock(progress: rings.stand.progress, color: .blue, size: 16, width: 4)
                    }
                    .frame(width: 40, height: 40)
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 40, height: 40)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Activity Today")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    if let steps = dataStore.todayData?.steps {
                        Text("\(Int(steps)) steps")
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
