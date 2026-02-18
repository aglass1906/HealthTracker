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
    @State private var showingEditProfile = false
    @State private var pendingAuthorization = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    @ObservedObject private var briefingManager = MorningBriefingManager.shared
    
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                if !hasCompletedOnboarding {
                    OnboardingView()
                } else {
                    TabView(selection: $selectedTab) {
                        DashboardView()
                            .tabItem {
                                Label("Dashboard", systemImage: "chart.bar.fill")
                            }
                            .tag(0)
                        
                        MyDataView()
                            .tabItem {
                                Label("My Data", systemImage: "chart.xyaxis.line")
                            }
                            .tag(1)
                        
                        CommunityView()
                            .tabItem {
                                Label("Community", systemImage: "person.3.fill")
                            }
                            .tag(2)
                        
                        ProfileView()
                            .tabItem {
                                Label("Profile", systemImage: "person.circle.fill")
                            }
                            .tag(3)
                    }
                    .tint(.blue)
                    .task {
                        // Import latest data on app startup
                        await dataStore.importLatestData()
                    }
                    .onChange(of: scenePhase) { newPhase in
                        if newPhase == .active {
                            Task {
                                await dataStore.importLatestData()
                            }
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                        Task {
                            await dataStore.importLatestData()
                        }
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
                    .sheet(isPresented: $briefingManager.shouldShowPopup) {
                        if let data = briefingManager.briefingData {
                            MorningBriefingView(data: data) {
                                briefingManager.dismissPopup()
                            }
                            .presentationDetents([.fraction(0.6), .large])
                            .presentationDragIndicator(.visible)
                        }
                    }
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
    @State private var selectedWorkout: WorkoutData?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("BETA Test")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.orange))
                            
                            Text(getAppVersion())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                        }
                        .padding(.bottom, 4)

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
                        
                        DailyGoalsCard(data: dataStore.todayData)
                            .padding(.horizontal)
                    }
                    

                    
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
                                        .onTapGesture {
                                            selectedWorkout = workout
                                        }
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
            .sheet(item: $dataStore.newlyFinishedWorkout) { workout in
                WorkoutSummaryView(workout: workout, profile: nil) // Current user
            }
            .sheet(item: $selectedWorkout) { workout in
                WorkoutSummaryView(workout: workout, profile: nil)
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
    
    private func getAppVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
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



// MARK: - Profile View

struct ProfileView: View {
    @StateObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var dataStore = HealthDataStore.shared
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var briefingManager = MorningBriefingManager.shared
    @State private var showingAuthorization = false
    @State private var showingUnauthorizeAlert = false
    @State private var showingSettingsAlert = false
    @State private var showingEditProfile = false
    @State private var currentProfile: Profile?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 60, height: 60)
                            .overlay {
                                Text(getInitials())
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.blue)
                            }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(getDisplayName())
                                    .font(.headline)
                                
                                Button {
                                    showingEditProfile = true
                                } label: {
                                    Image(systemName: "pencil.circle.fill")
                                        .foregroundStyle(.blue)
                                        .font(.title3)
                                }
                            }
                            
                            if let email = authManager.session?.user.email {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                
                Section("Notifications") {
                    Toggle(isOn: $briefingManager.isNotificationsEnabled) {
                        Label {
                            Text("Morning Briefing")
                        } icon: {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    if briefingManager.isNotificationsEnabled {
                        DatePicker("Delivery Time", selection: $briefingManager.preferredTime, displayedComponents: .hourAndMinute)
                            .tint(.blue)
                    }
                }
                
                if currentProfile?.is_admin == true {
                    Section("Admin") {
                        NavigationLink(destination: AdminUserListView()) {
                            Label("Admin Panel", systemImage: "shield.checkerboard")
                        }
                    }
                }
                
                Section("Developer") {
                    Button {
                        // Reset Flow
                        hasCompletedOnboarding = false
                        Task {
                            await AuthManager.shared.signOut()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .foregroundStyle(.orange)
                            Text("Reset Onboarding (Debug)")
                            Spacer()
                        }
                    }
                    
                    Button {
                        MorningBriefingManager.shared.resetBriefingStatus()
                    } label: {
                        HStack {
                            Image(systemName: "sun.max.fill")
                                .foregroundStyle(.orange)
                            Text("Reset Morning Briefing (Debug)")
                            Spacer()
                        }
                    }
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
                
                Section {
                    HStack {
                        Spacer()
                        Text(getAppVersion())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showingAuthorization) {
                AuthorizationView()
            }
            .sheet(isPresented: $showingEditProfile, onDismiss: {
                Task {
                    await fetchProfile()
                }
            }) {
                EditProfileView()
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
            .task {
                await fetchProfile()
            }
        }
    }
    
    private func fetchProfile() async {
        self.currentProfile = await AuthManager.shared.fetchCurrentUserProfile()
    }
    
    private func getDisplayName() -> String {
        return currentProfile?.display_name ?? authManager.session?.user.email ?? "Health Tracker"
    }
    
    private func getInitials() -> String {
        if let name = currentProfile?.display_name, !name.isEmpty {
            let components = name.components(separatedBy: " ")
            let first = components.first?.prefix(1) ?? ""
            let last = components.count > 1 ? components.last?.prefix(1) ?? "" : ""
            return "\(first)\(last)".uppercased()
        }
        
        if let email = authManager.session?.user.email {
            return String(email.prefix(2)).uppercased()
        }
        
        return "HT"
    }
    
    private func getAppVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "Version \(version) (\(build))"
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


struct DailyGoalsCard: View {
    let data: DailyHealthData?
    
    var exerciseMinutes: Int {
        guard let workouts = data?.workouts else { return 0 }
        return Int(workouts.reduce(0) { $0 + $1.duration } / 60)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Daily Activities")
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 16) {
                GoalRow(
                    title: "Steps",
                    icon: "figure.walk",
                    color: .blue,
                    current: data?.steps ?? 0,
                    target: Double(DailyHealthGoals.steps),
                    unit: "steps"
                )
                
                GoalRow(
                    title: "Calories",
                    icon: "flame.fill",
                    color: .orange,
                    current: data?.calories ?? 0,
                    target: Double(DailyHealthGoals.calories),
                    unit: "kcal"
                )
                
                GoalRow(
                    title: "Distance",
                    icon: "map.fill",
                    color: .cyan,
                    current: (data?.distance ?? 0) / 1000,
                    target: Double(DailyHealthGoals.distance) / 1000,
                    unit: "km",
                    format: "%.1f"
                )
                
                GoalRow(
                    title: "Flights",
                    icon: "stairs",
                    color: .green,
                    current: data?.flights ?? 0,
                    target: Double(DailyHealthGoals.flights),
                    unit: "floors"
                )
                
                GoalRow(
                    title: "Exercise",
                    icon: "figure.run",
                    color: .purple,
                    current: Double(exerciseMinutes),
                    target: Double(DailyHealthGoals.exerciseMinutes),
                    unit: "min"
                )
                
                GoalRow(
                    title: "Workouts",
                    icon: "dumbbell.fill",
                    color: .indigo,
                    current: Double(data?.workouts.count ?? 0),
                    target: Double(DailyHealthGoals.workouts),
                    unit: "workouts",
                    format: "%.0f"
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

struct GoalRow: View {
    let title: String
    let icon: String
    let color: Color
    let current: Double
    let target: Double
    let unit: String
    var format: String = "%.0f"
    
    var progress: Double {
        if target > 0 {
            return min(max(current / target, 0), 1.0)
        }
        return 0
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                }
                
                Spacer()
                
                Text("\(String(format: format, current)) / \(String(format: format, target)) \(unit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.secondarySystemBackground))
                        .frame(height: 8)
                    
                    Capsule()
                        .fill(color)
                        .frame(width: max(geometry.size.width * progress, 0), height: 8)
                }
            }
            .frame(height: 8)
        }
    }
}

#Preview {
    ContentView()
}
