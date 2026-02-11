//
//  MyDataView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/10/26.
//

import SwiftUI
import Charts

enum TimeScope: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case sixMonths = "6 Months"
    case custom = "Custom"
    
    var id: String { self.rawValue }
}

// HealthMetric enum moved to HealthMetric.swift

struct MyDataView: View {
    @StateObject private var dataStore = HealthDataStore.shared
    @State private var selectedScope: TimeScope = .week
    @State private var selectedMetric: HealthMetric = .steps
    @State private var referenceDate = Date()
    
    // For Custom Range
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var showingCustomRange = false
    
    // For Navigation
    @State private var selectedDay: DailyHealthData?
    
    // Derived Data
    var currentRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        
        switch selectedScope {
        case .day:
            return (today, today)
        case .week:
            // Last 7 days ending today, or standard week? Let's do standard week (Sun-Sat) containing ref date
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
            let startOfWeek = calendar.date(from: components)!
            let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek)!
            return (startOfWeek, endOfWeek)
        case .month:
            let components = calendar.dateComponents([.year, .month], from: today)
            let startOfMonth = calendar.date(from: components)!
            let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!.addingTimeInterval(-1)
            let endOfMonthDay = calendar.startOfDay(for: endOfMonth)
            return (startOfMonth, endOfMonthDay)
        case .sixMonths:
            // 6 months ending at ref date
            let end = today
            let start = calendar.date(byAdding: .month, value: -5, to: end)! // Current month + previous 5
            // Align start to start of month
            let startComponents = calendar.dateComponents([.year, .month], from: start)
            let startOfMonth = calendar.date(from: startComponents)!
             // Align end to end of month
            let endComponents = calendar.dateComponents([.year, .month], from: end)
            let startOfEndMonth = calendar.date(from: endComponents)!
            let endOfEndMonth = calendar.date(byAdding: .month, value: 1, to: startOfEndMonth)!.addingTimeInterval(-1)
            return (startOfMonth, calendar.startOfDay(for: endOfEndMonth))

        case .custom:
             return (calendar.startOfDay(for: customStartDate), calendar.startOfDay(for: customEndDate))
        }
    }
    
    var filteredData: [DailyHealthData] {
        let range = currentRange
        return dataStore.allDailyData.filter {
            $0.date >= range.start && $0.date <= range.end
        }.sorted { $0.date < $1.date } // Sort ascending for chart
    }
    
    var totalValue: Double {
        filteredData.reduce(0) { total, data in
            total + getValue(for: data, metric: selectedMetric)
        }
    }
    
    var averageValue: Double {
        guard !filteredData.isEmpty else { return 0 }
        return totalValue / Double(filteredData.count)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Scope Pivot
                    Picker("Time Range", selection: $selectedScope) {
                        ForEach(TimeScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    
                    // Date Navigation & Label
                    HStack {
                         Button(action: { moveDate(by: -1) }) {
                             Image(systemName: "chevron.left")
                                 .padding(8)
                                 .background(Color(.systemGray6))
                                 .clipShape(Circle())
                         }
                         .disabled(selectedScope == .custom)
                        
                        Text(dateRangeLabel)
                             .font(.headline)
                             .frame(maxWidth: .infinity)
                             .onTapGesture {
                                 // Allow tapping to pick custom range if we want, or rely on picker
                                 if selectedScope == .custom {
                                     showingCustomRange = true
                                 }
                             }
                        
                         Button(action: { moveDate(by: 1) }) {
                             Image(systemName: "chevron.right")
                                 .padding(8)
                                 .background(Color(.systemGray6))
                                 .clipShape(Circle())
                         }
                         .disabled(selectedScope == .custom || isFuture(referenceDate))
                     }
                     .padding(.horizontal)
                    
                    if selectedScope == .custom {
                        Button("Edit Date Range") {
                            showingCustomRange = true
                        }
                        .font(.subheadline)
                    }

                    // Summary Section (Metric Selector + Big Number)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Menu {
                                ForEach(HealthMetric.allCases) { metric in
                                    Button {
                                        selectedMetric = metric
                                    } label: {
                                        Label(metric.rawValue, systemImage: metric.icon)
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(selectedMetric.rawValue)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    Image(systemName: "chevron.down")
                                        .font(.headline)
                                }
                                .foregroundStyle(selectedMetric.color)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                Text("TOTAL")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(formatValue(totalValue, metric: selectedMetric))
                                    .font(.headline)
                                    .fontWeight(.bold)
                            }
                            
                            VStack(alignment: .trailing) {
                                Text("AVG")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(formatValue(averageValue, metric: selectedMetric))
                                    .font(.headline)
                                    .fontWeight(.bold)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Chart
                    if !filteredData.isEmpty {
                        Chart {
                            ForEach(filteredData) { data in
                                BarMark(
                                    x: .value("Date", data.date, unit: .day),
                                    y: .value(selectedMetric.rawValue, getValue(for: data, metric: selectedMetric))
                                )
                                .foregroundStyle(selectedMetric.color.gradient)
                            }
                            
                            if !filteredData.isEmpty {
                                RuleMark(y: .value("Average", averageValue))
                                    .foregroundStyle(.gray.opacity(0.5))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                                    .annotation(position: .leading, alignment: .bottom) {
                                        Text("Avg")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                            }
                        }
                        .frame(height: 180)
                        .padding(.horizontal)
                    } else {
                        ContentUnavailableView("No Data", systemImage: "chart.bar.xaxis", description: Text("No data available for this time range."))
                            .frame(height: 180)
                    }
                    
                    // List
                    VStack(alignment: .leading, spacing: 0) {
                        Text(selectedScope == .day ? "Details" : "Daily Breakdown")
                            .font(.headline)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        
                        
                        if selectedScope == .day {
                            // Single Day View (Drill Down automatically)
                            if let data = filteredData.first {
                                DailyDetailView(data: data)
                            }
                        } else {
                            // List for longer ranges
                            LazyVStack(spacing: 0) {
                                ForEach(filteredData.reversed()) { data in // Descending order for list
                                    Button {
                                        selectedDay = data
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(data.date.formatted(Date.FormatStyle().weekday(.abbreviated).month().day()))
                                                    .font(.body)
                                                    .fontWeight(.medium)
                                            }
                                            
                                            Spacer()
                                            
                                            VStack(alignment: .trailing) {
                                                Text(formatValue(getValue(for: data, metric: selectedMetric), metric: selectedMetric))
                                                    .font(.headline)
                                                    .foregroundStyle(selectedMetric.color)
                                                
                                                // Secondary metric (Steps if not steps)
                                                if selectedMetric != .steps {
                                                    Text(formatValue(data.steps, metric: .steps))
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding()
                                        .background(Color(.systemBackground))
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Divider()
                                        .padding(.leading)
                                }
                            }
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("My Data")
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showingCustomRange) {
                NavigationStack {
                    Form {
                        DatePicker("Start Date", selection: $customStartDate, displayedComponents: .date)
                        DatePicker("End Date", selection: $customEndDate, displayedComponents: .date)
                    }
                    .navigationTitle("Custom Range")
                    .toolbar {
                         Button("Done") {
                             showingCustomRange = false
                         }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(item: $selectedDay) { data in
                DailySummaryView(date: data.date)
            }
            .toolbar {
                if !dataStore.hasImportedData {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Import") {
                            Task { await dataStore.importLast30Days() }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func getValue(for data: DailyHealthData, metric: HealthMetric) -> Double {
        switch metric {
        case .steps: return data.steps
        case .calories: return data.calories
        case .distance: return data.distance ?? 0
        case .flights: return data.flights
        case .exercise: return data.activityRings?.exercise.value ?? 0
        case .workouts: return Double(data.workouts.count)
        }
    }
    
    private func formatValue(_ value: Double, metric: HealthMetric) -> String {
        switch metric {
        case .steps:
            return String(format: "%.0f", value)
        case .calories:
            return String(format: "%.0f kcal", value)
        case .distance:
            return String(format: "%.2f km", value / 1000)
        case .flights:
            return String(format: "%.0f", value)
        case .exercise:
            return String(format: "%.0f min", value)
        case .workouts:
            return String(format: "%.0f", value)
        }
    }
    
    private func moveDate(by value: Int) {
        let calendar = Calendar.current
        switch selectedScope {
        case .day:
            referenceDate = calendar.date(byAdding: .day, value: value, to: referenceDate) ?? referenceDate
        case .week:
            referenceDate = calendar.date(byAdding: .weekOfYear, value: value, to: referenceDate) ?? referenceDate
        case .month:
            referenceDate = calendar.date(byAdding: .month, value: value, to: referenceDate) ?? referenceDate
        case .sixMonths:
             referenceDate = calendar.date(byAdding: .month, value: value * 6, to: referenceDate) ?? referenceDate
        case .custom:
            break
        }
    }
    
    private func isFuture(_ date: Date) -> Bool {
        return date > Date()
    }
    
    private var dateRangeLabel: String {
        let range = currentRange
        let fmt = Date.FormatStyle().month(.abbreviated).day()
        
        switch selectedScope {
        case .day:
            return range.start.formatted(date: .abbreviated, time: .omitted)
        case .week:
            return "\(range.start.formatted(fmt)) - \(range.end.formatted(fmt))"
        case .month:
            return range.start.formatted(Date.FormatStyle().month(.wide).year())
        case .sixMonths:
            return "\(range.start.formatted(Date.FormatStyle().month(.abbreviated).year())) - \(range.end.formatted(Date.FormatStyle().month(.abbreviated).year()))"
        case .custom:
             return "\(range.start.formatted(date: .numeric, time: .omitted)) - \(range.end.formatted(date: .numeric, time: .omitted))"
        }
    }
}

// Embedded Daily Detail for "Day" scope
struct DailyDetailView: View {
    let data: DailyHealthData
    
    var body: some View {
        VStack(spacing: 20) {
            if let rings = data.activityRings {
                ActivityRingsView(rings: rings)
                    .padding(.horizontal)
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                 StatCard(title: "Steps", value: String(format: "%.0f", data.steps), icon: "figure.walk", color: .blue)
                 StatCard(title: "Calories", value: String(format: "%.0f", data.calories), icon: "flame.fill", color: .orange)
                 StatCard(title: "Distance", value: String(format: "%.2f km", (data.distance ?? 0) / 1000), icon: "map.fill", color: .green)
                 StatCard(title: "Flights", value: String(format: "%.0f", data.flights), icon: "stairs", color: .purple)
                 
                 // Exercise & Workouts
                 StatCard(title: "Exercise", value: String(format: "%.0f min", data.activityRings?.exercise.value ?? 0), icon: "stopwatch", color: .teal)
                 StatCard(title: "Workouts", value: "\(data.workouts.count)", icon: "figure.run", color: .indigo)
            }
            .padding(.horizontal)
            
            if !data.workouts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Workouts")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ForEach(data.workouts) { workout in
                        WorkoutRow(workout: workout)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
