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
    
    @State private var showDeleteAlert = false
    
    init(challenge: Challenge, viewModel: ChallengeViewModel) {
        self.challenge = challenge
        self.viewModel = viewModel
        
        _title = State(initialValue: challenge.title)
        _targetValueStr = State(initialValue: String(challenge.target_value))
        _startDate = State(initialValue: challenge.start_date)
        _hasEndDate = State(initialValue: challenge.end_date != nil)
        _endDate = State(initialValue: challenge.end_date ?? Date())
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    
                    HStack {
                        Text("Target (\(challenge.metric.unit))")
                        Spacer()
                        TextField("Value", text: $targetValueStr)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
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
                    .disabled(title.isEmpty || targetValueStr.isEmpty)
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
    
    private func update() {
        guard let target = Int(targetValueStr) else { return }
        
        Task {
            let success = await viewModel.updateChallenge(
                challenge: challenge,
                title: title,
                target: target,
                startDate: startDate,
                endDate: hasEndDate ? endDate : nil
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
                dismiss() // Dimiss Edit View
                // Note: The DetailView will likely need to pop too, handled by parent/env usually or state observation
                // In iOS 16+ NavigationStack, deleting the item usually pops the detail view if logic is sound.
            }
        }
    }
}
