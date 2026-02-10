//
//  HealthTrackerApp.swift
//  HealthTracker
//
//  Created by Alan Glass on 12/29/25.
//

import SwiftUI
import BackgroundTasks

@main
struct HealthTrackerApp: App {
    
    init() {
        // Register background tasks
        BackgroundTaskManager.shared.registerBackgroundTasks()
        
        // Initialize HealthKit manager to start observers if authorized
        _ = HealthKitManager.shared
    }
    
    @StateObject private var authManager = AuthManager.shared
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isRestoringSession {
                    // Splash Screen
                    ZStack {
                        Color(.systemBackground).ignoresSafeArea()
                        VStack(spacing: 20) {
                            Image(systemName: "heart.text.square.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 100, height: 100)
                                .foregroundStyle(.red)
                            
                            Text("HealthTracker")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            
                            ProgressView()
                                .controlSize(.large)
                        }
                    }
                } else if authManager.isAuthenticated {
                    ContentView()
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                            BackgroundTaskManager.shared.scheduleBackgroundRefresh()
                        }
                } else {
                    LoginView()
                }
            }
            .animation(.easeInOut, value: authManager.isRestoringSession)
        }
    }
}
