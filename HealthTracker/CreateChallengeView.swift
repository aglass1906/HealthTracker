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
    @State private var type: ChallengeType = .race
    
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
                    
                    HStack {
                        Text("Target")
                        TextField("Value", text: $targetValueStr)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text(selectedMetric.unit)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Timeline") {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    
                    Toggle("Set End Date", isOn: $hasEndDate)
                    
                    if hasEndDate {
                        DatePicker("End Date", selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])
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
                    .disabled(title.isEmpty || targetValueStr.isEmpty)
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
        guard let target = Int(targetValueStr) else { return }
        
        Task {
            let success = await viewModel.createChallenge(
                familyId: familyId,
                title: title,
                type: type,
                metric: selectedMetric,
                target: target,
                startDate: startDate,
                endDate: hasEndDate ? endDate : nil
            )
            
            if success {
                dismiss()
            }
        }
    }
}
