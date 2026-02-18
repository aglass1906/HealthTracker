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
    
    @Published var shouldShowPopup = false
    @Published var shouldShowBriefing = false // This controls the feed item
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
    private let lastBriefedDateKey = "morning_briefing_last_date" // For feed
    private let popupShownDateKey = "morning_briefing_popup_shown_date" // For popup
    private let notificationsEnabledKey = "morning_briefing_enabled"
    private let preferredTimeKey = "morning_briefing_time"
    
    private var cancellables = Set<AnyCancellable>()
    
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
        
        // Initial check
        checkBriefingStatus()
        
        // Subscribe to data updates to re-check when data helps
        HealthDataStore.shared.$allDailyData
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.checkBriefingStatus()
            }
            .store(in: &cancellables)
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
        
        // 1. Time Check: We only show it in the "morning" (e.g., before 11:00 AM)
        let hour = calendar.component(.hour, from: Date())
        guard hour < 11 else {
            shouldShowBriefing = false
            shouldShowPopup = false
            return
        }
        
        // 2. Data Check: Get yesterday's data
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        guard let data = HealthDataStore.shared.getDailyData(for: yesterday) else {
            // No data yet, wait for sync
            shouldShowBriefing = false
            shouldShowPopup = false
            return
        }
        
        self.briefingData = data
        
        // 3. Feed Status Check
        if let lastDate = userDefaults.object(forKey: lastBriefedDateKey) as? Date,
           calendar.isDate(lastDate, inSameDayAs: today) {
            shouldShowBriefing = false
        } else {
            shouldShowBriefing = true
        }
        
        // 4. Popup Status Check
        if let lastPopupDate = userDefaults.object(forKey: popupShownDateKey) as? Date,
           calendar.isDate(lastPopupDate, inSameDayAs: today) {
            shouldShowPopup = false
        } else {
            shouldShowPopup = true
        }
    }
    
    func dismissBriefing() {
        // Dismiss from feed
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        userDefaults.set(today, forKey: lastBriefedDateKey)
        shouldShowBriefing = false
    }
    
    func dismissPopup() {
        // Dismiss popup only
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        userDefaults.set(today, forKey: popupShownDateKey)
        shouldShowPopup = false
    }
    
    func resetBriefingStatus() {
        userDefaults.removeObject(forKey: lastBriefedDateKey)
        userDefaults.removeObject(forKey: popupShownDateKey)
        checkBriefingStatus()
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
