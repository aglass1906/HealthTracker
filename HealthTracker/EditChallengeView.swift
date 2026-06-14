//
//  EditChallengeView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/4/26.
//

import SwiftUI

struct EditChallengeView: View {
    let challenge: Challenge
    @ObservedObject var viewModel: ChallengeViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String
    @State private var targetValueStr: String
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var notifyFeed = true
    @State private var selectedMetric: ChallengeMetric
    @State private var selectedMetrics: Set<ChallengeMetric>
    
    @State private var showDeleteAlert = false
    
    var onDeleteSuccess: (() -> Void)?
    
    init(challenge: Challenge, viewModel: ChallengeViewModel, onDeleteSuccess: (() -> Void)? = nil) {
        self.challenge = challenge
        self.viewModel = viewModel
        self.onDeleteSuccess = onDeleteSuccess
        
        _title = State(initialValue: challenge.title)
        _targetValueStr = State(initialValue: String(challenge.target_value))
        _startDate = State(initialValue: challenge.start_date)
        _hasEndDate = State(initialValue: challenge.end_date != nil)
        _endDate = State(initialValue: challenge.end_date ?? Date())
        _selectedMetric = State(initialValue: challenge.metric)
        _selectedMetrics = State(initialValue: [challenge.metric])
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)

                    if challenge.type == .count {
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
                    } else {
                        Picker("Metric", selection: $selectedMetric) {
                            ForEach(ChallengeMetric.allCases, id: \.self) { metric in
                                Label(metric.displayName, systemImage: metric.icon).tag(metric)
                            }
                        }

                        HStack {
                            Text("Target (\(selectedMetric.unit))")
                            Spacer()
                            TextField("Value", text: $targetValueStr)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                
                Section("Timeline") {
                    DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    
                    Toggle("End Date", isOn: $hasEndDate)
                    
                    if hasEndDate {
                        DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])
                    }
                }
                
                Section {
                    Toggle("Notify Family Feed", isOn: $notifyFeed)
                }
                
                Section {
                    Button {
                        update()
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Text("Save Changes")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(
                        title.isEmpty
                        || (challenge.type == .count && selectedMetrics.isEmpty)
                        || (challenge.type != .count && targetValueStr.isEmpty)
                    )
                }
                
                Section {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Text("Delete Challenge")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .task {
                selectedMetrics = Set(await viewModel.fetchMetrics(for: challenge))
            }
            .navigationTitle("Edit Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Delete Challenge?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    delete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone. All progress data will be lost.")
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
    
    private func update() {
        let target = challenge.type == .count ? 0 : (Int(targetValueStr) ?? 0)
        
        Task {
            let success = await viewModel.updateChallenge(
                challenge: challenge,
                title: title,
                metrics: challenge.type == .count
                    ? ChallengeMetric.allCases.filter(selectedMetrics.contains)
                    : [selectedMetric],
                target: target,
                startDate: startDate,
                endDate: hasEndDate ? endDate : nil,
                notifyFeed: notifyFeed
            )
            
            if success {
                dismiss()
            }
        }
    }
    
    private func delete() {
        Task {
            let success = await viewModel.deleteChallenge(challengeId: challenge.id)
            if success {
                onDeleteSuccess?()
                dismiss() // Dimiss Edit View
            }
        }
    }
}
