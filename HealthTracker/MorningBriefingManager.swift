//
//  MorningBriefingManager.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/11/26.
//

import Foundation
import UserNotifications
import Combine

class MorningBriefingManager: ObservableObject {
    static let shared = MorningBriefingManager()
    
    @Published var shouldShowBriefing = false
    @Published var briefingData: DailyHealthData?
    
    // Notification Settings
    @Published var isNotificationsEnabled: Bool {
        didSet {
            userDefaults.set(isNotificationsEnabled, forKey: notificationsEnabledKey)
            if isNotificationsEnabled {
                rescheduleNotification()
            } else {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["morning_briefing"])
            }
        }
    }
    
    @Published var preferredTime: Date {
        didSet {
            userDefaults.set(preferredTime, forKey: preferredTimeKey)
            if isNotificationsEnabled {
                rescheduleNotification()
            }
        }
    }
    
    private let userDefaults = UserDefaults.standard
    private let lastBriefedDateKey = "morning_briefing_last_date"
    private let notificationsEnabledKey = "morning_briefing_enabled"
    private let preferredTimeKey = "morning_briefing_time"
    
    private init() {
        // Load settings
        self.isNotificationsEnabled = userDefaults.bool(forKey: notificationsEnabledKey)
        
        if let savedTime = userDefaults.object(forKey: preferredTimeKey) as? Date {
            self.preferredTime = savedTime
        } else {
            // Default to 8:00 AM
            var components = DateComponents()
            components.hour = 8
            components.minute = 0
            self.preferredTime = Calendar.current.date(from: components) ?? Date()
        }
        
        checkBriefingStatus()
    }
    
    func rescheduleNotification() {
        guard isNotificationsEnabled else { return }
        
        let summary = generateSummary()
        let components = Calendar.current.dateComponents([.hour, .minute], from: preferredTime)
        
        let content = UNMutableNotificationContent()
        content.title = summary.title
        content.body = summary.body
        content.sound = .default
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "morning_briefing", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func checkBriefingStatus() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // 1. Check if we've already briefed today
        if let lastDate = userDefaults.object(forKey: lastBriefedDateKey) as? Date {
            if calendar.isDate(lastDate, inSameDayAs: today) {
                shouldShowBriefing = false
                return
            }
        }
        
        // 2. We only show it in the "morning" (e.g., before 11:00 AM)
        let hour = calendar.component(.hour, from: Date())
        guard hour < 11 else {
            shouldShowBriefing = false
            return
        }
        
        // 3. Get yesterday's data
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        if let data = HealthDataStore.shared.getDailyData(for: yesterday) {
            self.briefingData = data
            self.shouldShowBriefing = true
        } else {
            shouldShowBriefing = false
        }
    }
    
    func dismissBriefing() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        userDefaults.set(today, forKey: lastBriefedDateKey)
        shouldShowBriefing = false
    }
    
    func generateSummary() -> (title: String, body: String) {
        guard let data = briefingData else {
            return ("Good Morning!", "Ready to start your day?")
        }
        
        let steps = Int(data.steps)
        let calories = Int(data.calories)
        
        var body = "Yesterday you took \(steps) steps"
        if steps >= 10000 {
            body += " - Goal reached! 🎯"
        } else {
            body += "."
        }
        
        body += " You burned \(calories) kcal and closed \(data.activityRings?.move.progress ?? 0 >= 1.0 ? "all" : "your") rings."
        
        return ("Your Yesterday Summary", body)
    }
}
