//
//  ContentView.swift
//  HealthTracker
//
//  Created by Alan Glass on 12/29/25.
//

import SwiftUI
import Charts
import UIKit
import Supabase

struct ContentView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var selectedTab = 0
    @StateObject private var dataStore = HealthDataStore.shared
    @StateObject private var healthKitManager = HealthKitManager.shared
    @State private var showingImportAlert = false
    @State private var pendingAuthorization = false
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                TabView(selection: $selectedTab) {
                    DashboardView()
                        .tabItem {
                            Label("Dashboard", systemImage: "chart.bar.fill")
                        }
                        .tag(0)
                    
                    AllDataView()
                        .tabItem {
                            Label("All Data", systemImage: "list.bullet.rectangle")
                        }
                        .tag(1)
                    
                    SummaryView()
                        .tabItem {
                            Label("Summary", systemImage: "chart.line.uptrend.xyaxis")
                        }
                        .tag(2)
                    
                    FamilyView()
                        .tabItem {
                            Label("Family", systemImage: "person.3.fill")
                        }
                        .tag(3)
                    
                    ProfileView()
                        .tabItem {
                            Label("Profile", systemImage: "person.circle.fill")
                        }
                        .tag(4)
                }
                .tint(.blue)
                .task {
                    // Import latest data on app startup
                    await dataStore.importLatestData()
                }
                .onChange(of: healthKitManager.isAuthorized) { oldValue, newValue in
                    // When authorization changes to true, check if we should prompt for import
                    if newValue && !oldValue && !dataStore.hasImportedData {
                        showingImportAlert = true
                    }
                }
                .alert("Import Health Data", isPresented: $showingImportAlert) {
                    Button("Import Last 30 Days") {
                        Task {
                            await dataStore.importLast30Days()
                        }
                    }
                    Button("Not Now", role: .cancel) { }
                } message: {
                    Text("Would you like to import your health data for the last 30 days? This will sync your steps, flights, calories, workouts, and activity rings.")
                }
            } else {
                LoginView()
            }
        }
    }
}

struct DashboardView: View {
    @StateObject private var dataStore = HealthDataStore.shared
    @StateObject private var healthKitManager = HealthKitManager.shared
    @State private var showingDailySummary = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text(Date().formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    
                    // Activity Rings
                    if let rings = dataStore.todayData?.activityRings {
                        ActivityRingsView(rings: rings)
                            .padding(.horizontal)
                    }
                    
                    // Stats Grid
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        StatCard(
                            title: "Steps",
                            value: formatNumber(dataStore.todayData?.steps ?? 0),
                            icon: "figure.walk",
                            color: .blue
                        )
                        StatCard(
                            title: "Calories",
                            value: formatNumber(dataStore.todayData?.calories ?? 0),
                            icon: "flame.fill",
                            color: .orange
                        )
                        StatCard(
                            title: "Flights",
                            value: formatNumber(dataStore.todayData?.flights ?? 0),
                            icon: "stairs",
                            color: .green
                        )
                        StatCard(
                            title: "Workouts",
                            value: "\(dataStore.todayData?.workouts.count ?? 0)",
                            icon: "figure.run",
                            color: .purple
                        )
                    }
                    .padding(.horizontal)
                    
                    // Recent Workouts
                    if let workouts = dataStore.todayData?.workouts, !workouts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Today's Workouts")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .padding(.horizontal)
                            
                            VStack(spacing: 12) {
                                ForEach(workouts.prefix(5)) { workout in
                                    WorkoutRow(workout: workout)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Sync/Import Button - Show prominently if no data
                    if dataStore.allDailyData.isEmpty {
                        if healthKitManager.isAuthorized {
                            Button {
                                Task {
                                    await dataStore.importLast30Days()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.title2)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Import Health Data")
                                            .font(.headline)
                                        Text("Sync last 30 days of data")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if dataStore.isLoading {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.blue.opacity(0.1))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                        }
                                }
                            }
                            .disabled(dataStore.isLoading)
                            .padding(.horizontal)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "heart.text.square")
                                    .font(.system(size: 50))
                                    .foregroundStyle(.orange)
                                Text("No Health Data")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                Text("Go to the Profile tab to authorize HealthKit and start tracking your health data")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal)
                        }
                    }
                    
                    // Daily Summary Button
                    if !dataStore.allDailyData.isEmpty {
                        Button {
                            showingDailySummary = true
                        } label: {
                            HStack {
                                Image(systemName: "calendar")
                                Text("View Daily Summary")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .padding()
                            .background {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue.opacity(0.1))
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Debug Error Message
                    if let error = dataStore.lastErrorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal)
                            .onTapGesture {
                                dataStore.lastErrorMessage = nil
                            }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Health Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            Task {
                                await dataStore.refreshTodayData()
                            }
                        } label: {
                            Label("Refresh Today", systemImage: "arrow.clockwise")
                        }
                        
                        if healthKitManager.isAuthorized {
                            Button {
                                Task {
                                    await dataStore.importLast30Days()
                                }
                            } label: {
                                Label("Import Last 30 Days", systemImage: "arrow.down.circle")
                            }
                            
                            Button {
                                Task {
                                    await dataStore.importLatestData()
                                }
                            } label: {
                                Label("Sync Latest Data", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingDailySummary) {
                DailySummaryView(date: Date())
            }
            .overlay {
                if dataStore.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
        }
    }
    
    private func formatNumber(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        return String(format: "%.0f", value)
    }
}

struct ActivityRingsView: View {
    let rings: ActivityRings
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Activity Rings")
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 20) {
                // Move Ring (Red)
                RingView(
                    progress: rings.move.progress,
                    color: .red,
                    title: "Move",
                    value: String(format: "%.0f", rings.move.value),
                    goal: String(format: "%.0f", rings.move.goal),
                    unit: "kcal"
                )
                
                // Exercise Ring (Green)
                RingView(
                    progress: rings.exercise.progress,
                    color: .green,
                    title: "Exercise",
                    value: String(format: "%.0f", rings.exercise.value),
                    goal: String(format: "%.0f", rings.exercise.goal),
                    unit: "min"
                )
                
                // Stand Ring (Blue)
                RingView(
                    progress: rings.stand.progress,
                    color: .blue,
                    title: "Stand",
                    value: String(format: "%.0f", rings.stand.value),
                    goal: String(format: "%.0f", rings.stand.goal),
                    unit: "hrs"
                )
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
    }
}

struct RingView: View {
    let progress: Double
    let color: Color
    let title: String
    let value: String
    let goal: String
    let unit: String
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 12)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: progress)
                
                VStack(spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .fontWeight(.bold)
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text("\(value)/\(goal)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
    }
}

struct WorkoutRow: View {
    let workout: WorkoutData
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 50, height: 50)
                Image(systemName: "figure.run")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.workoutType)
                    .font(.headline)
                Text(formatDuration(workout.duration))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(workout.startDate.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 1)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - All Data View

struct AllDataView: View {
    @StateObject private var dataStore = HealthDataStore.shared
    @State private var selectedData: DailyHealthData?
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(dataStore.allDailyData) { data in
                    Button {
                        selectedData = data
                    } label: {
                        DailyDataRow(data: data)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("All Logged Data")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await dataStore.refreshAllData()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(item: $selectedData) { data in
                DailySummaryView(date: data.date)
            }
            .overlay {
                if dataStore.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
        }
    }
}

struct DailyDataRow: View {
    let data: DailyHealthData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(data.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.headline)
                Spacer()
                Text(data.date.formatted(date: .omitted, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 20) {
                Label("\(formatNumber(data.steps))", systemImage: "figure.walk")
                    .font(.subheadline)
                Label("\(formatNumber(data.flights))", systemImage: "stairs")
                    .font(.subheadline)
                Label("\(formatNumber(data.calories))", systemImage: "flame.fill")
                    .font(.subheadline)
                if !data.workouts.isEmpty {
                    Label("\(data.workouts.count)", systemImage: "figure.run")
                        .font(.subheadline)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private func formatNumber(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        return String(format: "%.0f", value)
    }
}

// MARK: - Daily Summary View

struct DailySummaryView: View {
    let date: Date
    @StateObject private var dataStore = HealthDataStore.shared
    @Environment(\.dismiss) private var dismiss
    
    var dailyData: DailyHealthData? {
        dataStore.getDailyData(for: date)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(date.formatted(date: .long, time: .omitted))
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    
                    if let data = dailyData {
                        // Activity Rings
                        if let rings = data.activityRings {
                            ActivityRingsView(rings: rings)
                                .padding(.horizontal)
                        }
                        
                        // Stats
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ], spacing: 16) {
                            StatCard(
                                title: "Steps",
                                value: formatNumber(data.steps),
                                icon: "figure.walk",
                                color: .blue
                            )
                            StatCard(
                                title: "Flights",
                                value: formatNumber(data.flights),
                                icon: "stairs",
                                color: .green
                            )
                            StatCard(
                                title: "Calories",
                                value: formatNumber(data.calories),
                                icon: "flame.fill",
                                color: .orange
                            )
                            StatCard(
                                title: "Workouts",
                                value: "\(data.workouts.count)",
                                icon: "figure.run",
                                color: .purple
                            )
                        }
                        .padding(.horizontal)
                        
                        // Workouts
                        if !data.workouts.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Workouts")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal)
                                
                                VStack(spacing: 12) {
                                    ForEach(data.workouts) { workout in
                                        WorkoutRow(workout: workout)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    } else {
                        Text("No data available for this date")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Daily Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatNumber(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        return String(format: "%.0f", value)
    }
}

// MARK: - Summary View (Time Range)

struct SummaryView: View {
    @StateObject private var dataStore = HealthDataStore.shared
    @State private var selectedRange: TimeRange = .week
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var showingCustomRange = false
    
    enum TimeRange: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case custom = "Custom"
    }
    
    var summary: HealthSummary {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: Date())
        let startDate: Date
        
        switch selectedRange {
        case .week:
            startDate = calendar.date(byAdding: .day, value: -7, to: endDate)!
        case .month:
            startDate = calendar.date(byAdding: .month, value: -1, to: endDate)!
        case .custom:
            startDate = calendar.startOfDay(for: customStartDate)
        }
        
        return dataStore.getSummary(for: startDate, to: endDate)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Range Selector
                    Picker("Time Range", selection: $selectedRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    
                    if selectedRange == .custom {
                        DatePicker("Start Date", selection: $customStartDate, displayedComponents: .date)
                            .padding(.horizontal)
                        DatePicker("End Date", selection: $customEndDate, displayedComponents: .date)
                            .padding(.horizontal)
                    }
                    
                    // Summary Stats
                    VStack(spacing: 16) {
                        SummaryStatCard(
                            title: "Total Steps",
                            value: formatNumber(summary.totalSteps),
                            average: formatNumber(summary.averageSteps),
                            color: .blue
                        )
                        SummaryStatCard(
                            title: "Total Flights",
                            value: formatNumber(summary.totalFlights),
                            average: formatNumber(summary.averageFlights),
                            color: .green
                        )
                        SummaryStatCard(
                            title: "Total Calories",
                            value: formatNumber(summary.totalCalories),
                            average: formatNumber(summary.averageCalories),
                            color: .orange
                        )
                        SummaryStatCard(
                            title: "Total Workouts",
                            value: "\(summary.totalWorkouts)",
                            average: nil,
                            color: .purple
                        )
                    }
                    .padding(.horizontal)
                    
                    // Charts
                    if !summary.dailyData.isEmpty {
                        VStack(spacing: 24) {
                            ChartView(
                                title: "Steps",
                                data: summary.dailyData.map { ($0.date, $0.steps) },
                                color: .blue,
                                unit: "steps"
                            )
                            
                            ChartView(
                                title: "Flights",
                                data: summary.dailyData.map { ($0.date, $0.flights) },
                                color: .green,
                                unit: "flights"
                            )
                            
                            ChartView(
                                title: "Calories",
                                data: summary.dailyData.map { ($0.date, $0.calories) },
                                color: .orange,
                                unit: "kcal"
                            )
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Summary")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await dataStore.refreshAllData()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .overlay {
                if dataStore.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
        }
    }
    
    private func formatNumber(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        return String(format: "%.0f", value)
    }
}

struct SummaryStatCard: View {
    let title: String
    let value: String
    let average: String?
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            if let average = average {
                Text("Avg: \(average)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.1))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                }
        }
    }
}

struct ChartView: View {
    let title: String
    let data: [(Date, Double)]
    let color: Color
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            
            Chart {
                ForEach(data, id: \.0) { item in
                    LineMark(
                        x: .value("Date", item.0, unit: .day),
                        y: .value(title, item.1)
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("Date", item.0, unit: .day),
                        y: .value(title, item.1)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color.opacity(0.3), color.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
            }
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: max(1, data.count / 7))) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(formatValue(doubleValue))
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
        }
    }
    
    private func formatValue(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        return String(format: "%.0f", value)
    }
}

// MARK: - Profile View

struct ProfileView: View {
    @StateObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var dataStore = HealthDataStore.shared
    @State private var showingAuthorization = false
    @State private var showingUnauthorizeAlert = false
    @State private var showingSettingsAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 60, height: 60)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                            }
                        VStack(alignment: .leading, spacing: 4) {
                            if let email = AuthManager.shared.session?.user.email {
                                Text(email)
                                    .font(.headline)
                            } else {
                                Text("Health Tracker")
                                    .font(.headline)
                            }
                            Text(healthKitManager.isAuthorized ? "Connected" : "Not Connected")
                                .font(.subheadline)
                                .foregroundStyle(healthKitManager.isAuthorized ? .green : .orange)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section {
                    if !healthKitManager.isAuthorized {
                        Button {
                            showingAuthorization = true
                        } label: {
                            HStack {
                                Image(systemName: "heart.text.square.fill")
                                    .foregroundStyle(.red)
                                Text("Authorize HealthKit")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("HealthKit Authorized")
                        }
                        
                        Button {
                            Task {
                                await dataStore.importLast30Days()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundStyle(.blue)
                                Text("Import Last 30 Days")
                                Spacer()
                                if dataStore.isLoading {
                                    ProgressView()
                                } else {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(dataStore.isLoading)
                        
                        Button {
                            Task {
                                await dataStore.importLatestData()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundStyle(.blue)
                                Text("Sync Latest Data")
                                Spacer()
                                if dataStore.isLoading {
                                    ProgressView()
                                } else {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(dataStore.isLoading)
                        
                        Button(role: .destructive) {
                            showingUnauthorizeAlert = true
                        } label: {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text("Unauthorize HealthKit")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Health Data")
                } footer: {
                    if healthKitManager.isAuthorized {
                        Text("Import Last 30 Days will fetch historical data. Sync Latest Data will update recent days.")
                    }
                }
                
                Section {
                    SettingsRow(icon: "info.circle.fill", title: "About", color: .gray)
                    SettingsRow(icon: "questionmark.circle.fill", title: "Help & Support", color: .gray)
                }
                
                Section {
                    Button(role: .destructive) {
                        Task {
                            await AuthManager.shared.signOut()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showingAuthorization) {
                AuthorizationView()
            }
            .alert("Unauthorize HealthKit", isPresented: $showingUnauthorizeAlert) {
                Button("Clear Data & Open Settings", role: .destructive) {
                    // Clear local data and authorization state
                    dataStore.clearAllData()
                    healthKitManager.clearAuthorizationState()
                    showingSettingsAlert = true
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will clear all stored health data from this app. To fully revoke HealthKit permissions, you'll need to do so in iOS Settings. Continue?")
            }
            .alert("Open Settings", isPresented: $showingSettingsAlert) {
                Button("Open Settings") {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
                Button("Later", role: .cancel) { }
            } message: {
                Text("To fully revoke HealthKit permissions:\n\n1. Open Settings\n2. Go to Privacy & Security\n3. Select Health\n4. Find HealthTracker\n5. Turn off all permissions")
            }
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(title)
                .font(.body)
        }
        .padding(.vertical, 4)
    }
}

struct AuthorizationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var healthKitManager = HealthKitManager.shared
    @State private var isAuthorizing = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.red)
                
                Text("Health Data Access")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("HealthTracker needs access to your health data to track your steps, flights, calories, workouts, and activity rings.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 12) {
                    Label("Steps and Flights", systemImage: "figure.walk")
                    Label("Active Calories", systemImage: "flame.fill")
                    Label("Workouts", systemImage: "figure.run")
                    Label("Activity Rings", systemImage: "circle.dotted")
                }
                .font(.subheadline)
                
                Button {
                    isAuthorizing = true
                    Task {
                        do {
                            try await healthKitManager.requestAuthorization()
                            dismiss()
                        } catch {
                            print("Authorization failed: \(error)")
                        }
                        isAuthorizing = false
                    }
                } label: {
                    HStack {
                        if isAuthorizing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Authorize HealthKit")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .disabled(isAuthorizing)
                .padding(.horizontal)
                
                Button("Cancel") {
                    dismiss()
                }
                .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Authorization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
