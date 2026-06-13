//
//  LeaderboardView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/3/26.
//

import SwiftUI
import Supabase
import Combine

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

enum LeaderboardMetric: String, CaseIterable, Identifiable {
    case steps
    case calories
    case distance
    case flights
    case exercise
    case workouts
    case moveRing
    case exerciseRing
    case standRing
    case allRingsClosed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .steps: return "Steps"
        case .calories: return "Calories"
        case .distance: return "Distance"
        case .flights: return "Flights"
        case .exercise: return "Exercise Minutes"
        case .workouts: return "Workouts"
        case .moveRing: return "Move Ring"
        case .exerciseRing: return "Exercise Ring"
        case .standRing: return "Stand Ring"
        case .allRingsClosed: return "All Rings Closed"
        }
    }

    var icon: String {
        switch self {
        case .steps: return "figure.walk"
        case .calories: return "flame.fill"
        case .distance: return "map.fill"
        case .flights: return "stairs"
        case .exercise: return "stopwatch"
        case .workouts: return "figure.run"
        case .moveRing, .exerciseRing, .standRing: return "circle.fill"
        case .allRingsClosed: return "circle.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .steps: return .blue
        case .calories: return .orange
        case .distance: return .green
        case .flights: return .purple
        case .exercise: return .teal
        case .workouts: return .indigo
        case .moveRing: return .red
        case .exerciseRing: return .green
        case .standRing: return .blue
        case .allRingsClosed: return .pink
        }
    }

    var unit: String {
        switch self {
        case .steps: return "steps"
        case .calories, .moveRing: return "kcal"
        case .distance: return "m"
        case .flights: return "flights"
        case .exercise, .exerciseRing: return "min"
        case .workouts: return "workouts"
        case .standRing: return "hrs"
        case .allRingsClosed: return "days"
        }
    }

    var databaseColumn: String {
        switch self {
        case .steps: return "steps"
        case .calories: return "calories"
        case .distance: return "distance"
        case .flights: return "flights"
        case .exercise: return "exercise_minutes"
        case .workouts: return "workouts_count"
        case .moveRing: return "move_ring_value"
        case .exerciseRing: return "exercise_ring_value"
        case .standRing: return "stand_ring_value"
        case .allRingsClosed: return "all_rings_closed"
        }
    }
}

struct LeaderboardEntry: Identifiable, Codable {
    let id = UUID() // Local ID for UI
    let user_id: UUID
    let date: String
    let steps: Int
    let calories: Int
    let flights: Int
    let distance: Double
    let exercise_minutes: Int
    let workouts_count: Int
    let move_ring_value: Double
    let exercise_ring_value: Double
    let stand_ring_value: Double
    let all_rings_closed: Int
    
    // Joined profile
    let profile: Profile?
    
    enum CodingKeys: String, CodingKey {
        case user_id
        case date
        case steps
        case calories
        case flights
        case distance
        case exercise_minutes
        case workouts_count
        case move_ring_value
        case exercise_ring_value
        case stand_ring_value
        case all_rings_closed
        case profile
    }
}

class LeaderboardViewModel: ObservableObject {
    @Published var entries: [LeaderboardEntry] = []
    @Published var isLoading = false
    @Published var selectedMetric: LeaderboardMetric = .steps {
        didSet {
            Task { await fetchLeaderboard(for: currentFamilyId) }
        }
    }
    @Published var selectedDate: Date = Date() {
        didSet {
            Task { await fetchLeaderboard(for: currentFamilyId) }
        }
    }

    private var currentFamilyId: UUID = UUID()
    let client = AuthManager.shared.client

    var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    func fetchLeaderboard(for familyId: UUID) async {
        isLoading = true
        currentFamilyId = familyId
        entries = []

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let today = formatter.string(from: selectedDate)
        
        do {
            // 1. Get all community members to map names
            let profiles = await CommunityMembershipManager.shared.fetchMembers(for: familyId)
            
            // 2. Get today's stats for these users
            let userIds = profiles.map { $0.id }
            
            struct DailyStat: Codable {
                let user_id: UUID
                let date: String
                let steps: Int
                let calories: Int
                let flights: Int
                let distance: Double
                let exercise_minutes: Int
                let workouts_count: Int
                let move_ring_value: Double
                let exercise_ring_value: Double
                let stand_ring_value: Double
                let all_rings_closed: Int
            }
            
            let stats: [DailyStat] = try await client
                .from("daily_stats")
                .select()
                .in("user_id", values: userIds)
                .eq("date", value: today)
                .order(selectedMetric.databaseColumn, ascending: false)
                .execute()
                .value
            
            // 3. Merge
            self.entries = stats.map { stat in
                let profile = profiles.first(where: { $0.id == stat.user_id })
                return LeaderboardEntry(
                    user_id: stat.user_id,
                    date: stat.date,
                    steps: stat.steps,
                    calories: stat.calories,
                    flights: stat.flights,
                    distance: stat.distance,
                    exercise_minutes: stat.exercise_minutes,
                    workouts_count: stat.workouts_count,
                    move_ring_value: stat.move_ring_value,
                    exercise_ring_value: stat.exercise_ring_value,
                    stand_ring_value: stat.stand_ring_value,
                    all_rings_closed: stat.all_rings_closed,
                    profile: profile
                )
            }
        } catch {
            print("Leaderboard fetch error: \(error)")
        }
        
        isLoading = false
    }
    
    func getMetricValue(for entry: LeaderboardEntry) -> Double {
        switch selectedMetric {
        case .steps: return Double(entry.steps)
        case .calories: return Double(entry.calories)
        case .distance: return entry.distance
        case .flights: return Double(entry.flights)
        case .exercise: return Double(entry.exercise_minutes)
        case .workouts: return Double(entry.workouts_count)
        case .moveRing: return entry.move_ring_value
        case .exerciseRing: return entry.exercise_ring_value
        case .standRing: return entry.stand_ring_value
        case .allRingsClosed: return Double(entry.all_rings_closed)
        }
    }
    
    func formatValue(for entry: LeaderboardEntry) -> String {
        let value = getMetricValue(for: entry)
        let unit = selectedMetric.unit
        
        if selectedMetric == .distance {
             return String(format: "%.2f %@", value, unit)
        } else if selectedMetric == .allRingsClosed {
            return value >= 1 ? "Closed" : "Not closed"
        } else {
             return String(format: "%.0f %@", value, unit)
        }
    }

    func relativeProgress(for entry: LeaderboardEntry) -> Double? {
        guard let leader = entries.first else { return nil }
        let maxValue = getMetricValue(for: leader)
        guard maxValue > 0 else { return nil }
        return min(max(getMetricValue(for: entry) / maxValue, 0), 1)
    }
    
    func copyToClipboard() {
        let dateLabel = isToday ? "Today" : selectedDate.formatted(date: .abbreviated, time: .omitted)
        var text = "🏆 \(selectedMetric.displayName) Leaderboard\n\(dateLabel)\n\n"
        
        for (index, entry) in entries.enumerated() {
            let rank = index + 1
            let name = entry.profile?.display_name ?? entry.profile?.email ?? "Unknown"
            let valueStr = formatValue(for: entry)
            
            text += "\(rank). \(name) - \(valueStr)\n"
        }
        
#if canImport(UIKit)
        UIPasteboard.general.string = text
#elseif canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
#endif
    }
}

struct LeaderboardView: View {
    let familyId: UUID
    @StateObject private var viewModel = LeaderboardViewModel()
    @State private var showCopiedAlert = false
    @State private var showingDatePicker = false
    
    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose a metric and date")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Picker("Metric", selection: $viewModel.selectedMetric) {
                        ForEach(LeaderboardMetric.allCases) { metric in
                            Label(metric.displayName, systemImage: metric.icon).tag(metric)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()

                    Button {
                        showingDatePicker = true
                    } label: {
                        Label(
                            viewModel.selectedDate.formatted(date: .abbreviated, time: .omitted),
                            systemImage: "calendar"
                        )
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)
            .padding(.top)
            
            HStack {
                Text("\(viewModel.selectedMetric.displayName) Leaderboard")
                    .font(.headline)

                Spacer()

                Button {
                    viewModel.copyToClipboard()
                    showCopiedAlert = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showCopiedAlert = false
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
            .padding(.top, 8)
            .padding(.horizontal)
            
            if showCopiedAlert {
                 Text("Copied to clipboard!")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .background(Capsule().fill(Color.black.opacity(0.7)))
                    .transition(.opacity)
            }
            
            if viewModel.isLoading {
                ProgressView()
                    .padding()
            } else if viewModel.entries.isEmpty {
                Text(viewModel.isToday ? "No data for today yet." : "No data for \(viewModel.selectedDate.formatted(date: .abbreviated, time: .omitted)).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List {
                    ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                        HStack {
                            Text("#\(index + 1)")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundStyle(viewModel.selectedMetric.color)
                                .frame(width: 40)
                            
                            VStack(alignment: .leading) {
                                Text(entry.profile?.display_name ?? entry.profile?.email ?? "Unknown")
                                    .fontWeight(.semibold)
                                Text(viewModel.formatValue(for: entry))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            // Visualize relative progress
                            if let progress = viewModel.relativeProgress(for: entry) {
                                Circle()
                                    .trim(from: 0, to: progress)
                                    .stroke(viewModel.selectedMetric.color, lineWidth: 4)
                                    .frame(width: 30, height: 30)
                                    .rotationEffect(.degrees(-90))
                                    .overlay {
                                        if index == 0 {
                                            Text("🏆")
                                                .font(.caption2)
                                        } else {
                                            Image(systemName: viewModel.selectedMetric.icon)
                                                .font(.caption2)
                                                .foregroundStyle(viewModel.selectedMetric.color)
                                        }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .animation(.easeInOut, value: showCopiedAlert)
        .task(id: familyId) {
            await viewModel.fetchLeaderboard(for: familyId)
        }
        .refreshable {
            await viewModel.fetchLeaderboard(for: familyId)
        }
        .sheet(isPresented: $showingDatePicker) {
            LeaderboardDatePickerSheet(selectedDate: $viewModel.selectedDate)
                .presentationDetents([.medium])
        }
    }
}

private struct LeaderboardDatePickerSheet: View {
    @Binding var selectedDate: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(
                "Leaderboard Date",
                selection: $selectedDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .onChange(of: selectedDate) {
                dismiss()
            }
            .navigationTitle("Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
