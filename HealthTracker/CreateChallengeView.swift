//
//  CreateChallengeView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/4/26.
//

import SwiftUI

struct CreateChallengeView: View {
    let familyId: UUID
    @ObservedObject var viewModel: ChallengeViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var selectedMetric: ChallengeMetric = .steps
    @State private var selectedMetrics: Set<ChallengeMetric> = [.steps]
    @State private var targetValueStr = ""
    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var type: ChallengeType = .count
    @State private var enableRounds = false
    @State private var roundDuration: RoundDuration = .weekly
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Challenge Details") {
                    TextField("Title (e.g. Weekend Walkoff)", text: $title)
                    
                    Picker("Type", selection: $type) {
                        ForEach(ChallengeType.allCases, id: \.self) { type in
                            Label(type.title, systemImage: type.icon).tag(type)
                        }
                    }
                }
                
                Section("Goal") {
                    if type == .count {
                        ForEach(ChallengeMetric.allCases, id: \.self) { metric in
                            Button {
                                toggleMetric(metric)
                            } label: {
                                HStack {
                                    Label(metric.displayName, systemImage: metric.icon)
                                    Spacer()
                                    if selectedMetrics.contains(metric) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                        Text("Each metric awards one win. Tied leaders each receive a win.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Metric", selection: $selectedMetric) {
                            ForEach(ChallengeMetric.allCases, id: \.self) { metric in
                                Label(metric.displayName, systemImage: metric.icon).tag(metric)
                            }
                        }
                    }
                    
                    if type != .count {
                        HStack {
                            Text("Target")
                            TextField("Value", text: $targetValueStr)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                            Text(selectedMetric.unit)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("Timeline") {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    
                    if type == .count {
                        // Leaderboards must have an end date to define the winner
                        DatePicker("End Date", selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])
                    } else {
                        Toggle("Set End Date", isOn: $hasEndDate)

                        if hasEndDate {
                            DatePicker("End Date", selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])
                        }
                    }
                }
                
                if type == .count {
                    Section("Rounds") {
                        Toggle("Enable Rounds", isOn: $enableRounds)

                        if enableRounds {
                            Picker("Round Duration", selection: $roundDuration) {
                                ForEach(RoundDuration.allCases, id: \.self) { duration in
                                    Text(duration.displayName).tag(duration)
                                }
                            }

                            Text("Every selected metric awards wins in each round. Overall standings total all metric wins.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section {
                    Button {
                        create()
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Text("Create Challenge")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(
                        title.isEmpty
                        || (type == .count && selectedMetrics.isEmpty)
                        || (type != .count && targetValueStr.isEmpty)
                    )
                }
            }
            .navigationTitle("New Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onChange(of: type) { _, newType in
            if newType != .count {
                enableRounds = false
            }
        }
    }

    private func toggleMetric(_ metric: ChallengeMetric) {
        if selectedMetrics.contains(metric) {
            if selectedMetrics.count > 1 {
                selectedMetrics.remove(metric)
            }
        } else {
            selectedMetrics.insert(metric)
        }
    }
    
    private func create() {
        // For leaderboard, target is 0/ignored. For others, must be valid Int.
        var target = 0
        if type != .count {
            guard let val = Int(targetValueStr) else { return }
            target = val
        }
        
        Task {
            let success = await viewModel.createChallenge(
                familyId: familyId,
                title: title,
                type: type,
                metrics: type == .count
                    ? ChallengeMetric.allCases.filter(selectedMetrics.contains)
                    : [selectedMetric],
                target: target,
                startDate: startDate,
                endDate: (hasEndDate || type == .count) ? endDate : nil, // Force end date for count
                roundDuration: enableRounds ? roundDuration : nil
            )
            
            if success {
                dismiss()
            }
        }
    }
}
