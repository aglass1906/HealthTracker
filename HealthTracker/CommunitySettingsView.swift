//
//  CommunitySettingsView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/10/26.
//

import SwiftUI
import Supabase

struct CommunitySettingsView: View {
    @ObservedObject var viewModel: FamilyViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingCreateChallenge = false
    
    var body: some View {
        NavigationStack {
            List {
                if let family = viewModel.family {
                    // MARK: - Community Info
                    Section("Community Details") {
                        HStack {
                            Text("Name")
                            Spacer()
                            Text(family.name)
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack {
                            Text("Invite Code")
                            Spacer()
                            Text(family.invite_code)
                                .monospaced()
                                .fontWeight(.bold)
                            
                            Button {
                                UIPasteboard.general.string = family.invite_code
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    
                    Section("Join a Community") {
                        HStack {
                            TextField("Invite Code", text: $viewModel.joinCode)
                                .keyboardType(.numberPad)
                            
                            Button("Join") {
                                Task { await viewModel.joinFamily() }
                            }
                            .disabled(viewModel.joinCode.count < 6)
                        }
                    }

                    Section("Create a Community") {
                        HStack {
                            TextField("Community Name", text: $viewModel.newFamilyName)
                            
                            Button("Create") {
                                Task { await viewModel.createFamily() }
                            }
                            .disabled(viewModel.newFamilyName.isEmpty)
                        }
                    }
                    
                    // MARK: - Challenges
                    Section("Manage Challenges") {
                        Button {
                            showingCreateChallenge = true
                        } label: {
                            Label("Create New Challenge", systemImage: "plus.circle.fill")
                                .font(.headline)
                        }
                        
                        // Future: Add list of active/past challenges here for management (delete/edit)
                         NavigationLink {
                             ChallengesListView(familyId: family.id) // Reuse list for now, or create a specific "Manage" list
                         } label: {
                             Label("View All Challenges", systemImage: "list.bullet")
                         }
                    }
                    
                    // MARK: - Danger Zone
                    Section {
                        Button("Leave Community", role: .destructive) {
                            Task {
                                await viewModel.leaveFamily()
                                dismiss()
                            }
                        }
                    }
                } else {
                    Text("No Community Found")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingCreateChallenge) {
                if let family = viewModel.family {
                    CreateChallengeView(familyId: family.id, viewModel: ChallengeViewModel()) // Pass a new VM or share if needed
                }
            }
        }
    }
}
