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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    // Schedule refresh when app goes to background
                    BackgroundTaskManager.shared.scheduleBackgroundRefresh()
                }
        }
    }
}
