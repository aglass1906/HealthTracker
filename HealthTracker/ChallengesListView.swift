//
//  ChallengesListView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/4/26.
//

import SwiftUI

struct ChallengesListView: View {
    let familyId: UUID
    @StateObject private var viewModel = ChallengeViewModel()
    @State private var showingCreate = false
    
    var body: some View {
        VStack {
            if viewModel.isLoading && viewModel.activeChallenges.isEmpty {
                ProgressView()
                    .padding()
            } else if viewModel.activeChallenges.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "flag.checkered.circle")
                        .font(.system(size: 60))
                        .foregroundStyle(.gray.opacity(0.3))
                    Text("No Active Challenges")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Start a race to compete with your family!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)
            } else {
                List {
                    ForEach(viewModel.activeChallenges) { challenge in
                        NavigationLink(destination: ChallengeDetailView(challenge: challenge)) {
                            HStack {
                                Image(systemName: challenge.metric.icon)
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading) {
                                    Text(challenge.title)
                                        .fontWeight(.semibold)
                                    Text("\(challenge.type.title) • Target: \(challenge.target_value) \(challenge.metric.unit)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            
            Spacer()
            
            Button {
                showingCreate = true
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("New Challenge")
                }
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding()
                .background(Color.blue)
                .cornerRadius(30)
                .shadow(radius: 5)
            }
            .padding(.bottom)
        }
        .task {
            // Refetch when view appears (e.g. switched tabs)
            await viewModel.fetchActiveChallenges(for: familyId)
        }
        .sheet(isPresented: $showingCreate, onDismiss: {
            // Refetch after dismissing creation sheet
            Task { await viewModel.fetchActiveChallenges(for: familyId) }
        }) {
            CreateChallengeView(familyId: familyId, viewModel: viewModel)
        }
    }
}
