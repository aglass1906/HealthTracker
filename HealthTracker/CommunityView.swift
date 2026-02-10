//
//  FamilyView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/3/26.
//

import SwiftUI
import Supabase
import Combine

struct Family: Codable, Identifiable {
    let id: UUID
    let name: String
    let invite_code: String
}

struct Profile: Codable, Identifiable {
    let id: UUID
    let email: String?
    let display_name: String?
    let avatar_url: String?
    let family_id: UUID?
    // We will join daily_stats here usually, but keeping it simple for now
}

@MainActor
class FamilyViewModel: ObservableObject {
    @Published var family: Family?
    @Published var members: [Profile] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Create/Join State
    @Published var newFamilyName = ""
    @Published var joinCode = ""
    
    let client = AuthManager.shared.client
    
    func fetchFamily() async {
        guard let userId = AuthManager.shared.session?.user.id else { return }
        isLoading = true
        
        do {
            // 1. Get user's profile to find family_id
            let profile: Profile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            
            if let familyId = profile.family_id {
                // 2. Fetch Family Details
                let family: Family = try await client
                    .from("families")
                    .select()
                    .eq("id", value: familyId)
                    .single()
                    .execute()
                    .value
                
                self.family = family
                
                // 3. Fetch Members
                let members: [Profile] = try await client
                    .from("profiles")
                    .select()
                    .eq("family_id", value: familyId)
                    .execute()
                    .value
                
                self.members = members
            }
        } catch {
            print("Error fetching family: \(error)")
        }
        
        isLoading = false
    }
    
    func createFamily() async {
        guard let userId = AuthManager.shared.session?.user.id, !newFamilyName.isEmpty else { return }
        isLoading = true
        
        do {
            // Generate Random 6-digit code
            let inviteCode = String(format: "%06d", Int.random(in: 100000...999999))
            
            struct NewFamily: Encodable {
                let name: String
                let invite_code: String
            }
            
            // 1. Insert Family
            let family: Family = try await client
                .from("families")
                .insert(NewFamily(name: newFamilyName, invite_code: inviteCode))
                .select()
                .single()
                .execute()
                .value
            
            // 2. Update User Profile
            struct ProfileUpdate: Encodable {
                let family_id: UUID
            }
            
            try await client
                .from("profiles")
                .update(ProfileUpdate(family_id: family.id))
                .eq("id", value: userId)
                .execute()
            
            await fetchFamily()
        } catch {
            errorMessage = "Failed to create family: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func joinFamily() async {
        guard let userId = AuthManager.shared.session?.user.id, !joinCode.isEmpty else { return }
        isLoading = true
        
        do {
            // 1. Find family by code
            let family: Family = try await client
                .from("families")
                .select()
                .eq("invite_code", value: joinCode)
                .single()
                .execute()
                .value
            
            // 2. Join
            struct ProfileUpdate: Encodable {
                let family_id: UUID
            }
            
            try await client
                .from("profiles")
                .update(ProfileUpdate(family_id: family.id))
                .eq("id", value: userId)
                .execute()
            

            
            await fetchFamily()
            
            // Post to Feed
            Task {
                await SocialFeedManager.shared.post(type: .joined_family, familyId: family.id)
            }
        } catch {
            errorMessage = "Invalid code or failed to join."
        }
        
        isLoading = false
    }
    
    func leaveFamily() async {
        guard let userId = AuthManager.shared.session?.user.id else { return }
        isLoading = true
        
        do {
            struct ProfileUpdate: Encodable {
                let family_id: UUID? = nil
            }
            
            try await client
                .from("profiles")
                .update(ProfileUpdate())
                .eq("id", value: userId)
                .execute()
            
            family = nil
            members = []
        } catch {
            errorMessage = "Failed to leave family."
        }
        
        isLoading = false
    }
}

struct CommunityView: View {
    @StateObject private var viewModel = FamilyViewModel()
    @State private var selectedTab = 0
    @State private var showingSettings = false
    
    var body: some View {
        NavigationStack {
            VStack {
                if viewModel.isLoading {
                    ProgressView()
                } else if let family = viewModel.family {
                    // Active Community View
                    VStack(spacing: 0) {
                        Picker("View", selection: $selectedTab) {
                            Text("Feed").tag(0)
                            Text("Leaderboard").tag(1)
                            Text("Challenges").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .padding()
                        
                        TabView(selection: $selectedTab) {
                            SocialFeedView(familyId: family.id)
                                .tag(0)
                            
                            LeaderboardView(familyId: family.id)
                                .tag(1)
                            
                            ChallengesListView(familyId: family.id)
                                .tag(2)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    }
                } else {
                    // Create or Join View
                    ScrollView {
                        VStack(spacing: 30) {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.blue)
                            
                            Text("Community Challenges")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("Create a community or join one to compete with your friends and family!")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                            
                            VStack(spacing: 16) {
                                Text("Join a Community")
                                    .font(.headline)
                                
                                HStack {
                                    TextField("Enter 6-digit Code", text: $viewModel.joinCode)
                                        .textFieldStyle(.roundedBorder)
                                        .keyboardType(.numberPad)
                                    
                                    Button("Join") {
                                        Task { await viewModel.joinFamily() }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(viewModel.joinCode.count < 6)
                                }
                            }
                            .padding()
                            // Use system background for cards in light mode, secondary system background in dark mode if needed
                            // But here referencing Color(.secondarySystemBackground) fits standard iOS card style
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            
                            Text("OR")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            
                            VStack(spacing: 16) {
                                Text("Create New Community")
                                    .font(.headline)
                                
                                HStack {
                                    TextField("Community Name", text: $viewModel.newFamilyName)
                                        .textFieldStyle(.roundedBorder)
                                    
                                    Button("Create") {
                                        Task { await viewModel.createFamily() }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(viewModel.newFamilyName.isEmpty)
                                }
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                        .padding()
                    }
                }
            }

            .navigationTitle("Community")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.family != nil {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gear")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                CommunitySettingsView(viewModel: viewModel)
            }
            .task {
                await viewModel.fetchFamily()
            }
            .alert("Error", isPresented: Binding<Bool>(
                get: { viewModel.errorMessage != nil },
                set: { _ in viewModel.errorMessage = nil }
            )) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}
