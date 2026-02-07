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
                    Picker("Metric", selection: $selectedMetric) {
                        ForEach(ChallengeMetric.allCases, id: \.self) { metric in
                            Label(metric.displayName, systemImage: metric.icon).tag(metric)
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
                
                Section("Rounds") {
                    Toggle("Enable Rounds", isOn: $enableRounds)
                    
                    if enableRounds {
                        Picker("Round Duration", selection: $roundDuration) {
                            ForEach(RoundDuration.allCases, id: \.self) { duration in
                                Text(duration.displayName).tag(duration)
                            }
                        }
                        
                        Text("Each round will have a winner. The overall champion is the player with the most round wins!")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    .disabled(title.isEmpty || (type != .count && targetValueStr.isEmpty))
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
                metric: selectedMetric,
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
