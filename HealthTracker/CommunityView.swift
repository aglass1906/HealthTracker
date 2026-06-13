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



@MainActor
class FamilyViewModel: ObservableObject {
    @Published var communities: [Family] = []
    @Published var selectedCommunity: Family?
    @Published var members: [Profile] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Create/Join State
    @Published var newFamilyName = ""
    @Published var joinCode = ""
    
    let client = AuthManager.shared.client
    private let membershipManager = CommunityMembershipManager.shared
    
    var family: Family? {
        selectedCommunity
    }
    
    func fetchFamily() async {
        guard let userId = AuthManager.shared.session?.user.id else { return }
        isLoading = true
        
        defer { isLoading = false }
        
        if communities.isEmpty {
            await membershipManager.backfillLegacyMembershipIfNeeded(userId: userId)
        }
        
        let fetchedCommunities = await membershipManager.fetchCommunitiesForCurrentUser()
        communities = fetchedCommunities
        
        if let selectedCommunity,
           fetchedCommunities.contains(where: { $0.id == selectedCommunity.id }) {
            await selectCommunity(selectedCommunity)
        } else if let firstCommunity = fetchedCommunities.first {
            await selectCommunity(firstCommunity)
        } else {
            selectedCommunity = nil
            members = []
        }
    }
    
    func selectCommunity(_ community: Family) async {
        selectedCommunity = community
        members = await membershipManager.fetchMembers(for: community.id)
        
        Task {
            await SocialFeedManager.shared.checkAndPostJoin(familyId: community.id)
        }
    }
    
    func selectCommunity(id: UUID) async {
        guard let community = communities.first(where: { $0.id == id }) else { return }
        await selectCommunity(community)
    }
    
    private func refreshAfterMembershipChange(select family: Family? = nil) async {
        let fetchedCommunities = await membershipManager.fetchCommunitiesForCurrentUser()
        communities = fetchedCommunities
        
        if let family,
           fetchedCommunities.contains(where: { $0.id == family.id }) {
            await selectCommunity(family)
        } else if let current = selectedCommunity,
                  fetchedCommunities.contains(where: { $0.id == current.id }) {
            await selectCommunity(current)
        } else if let first = fetchedCommunities.first {
            await selectCommunity(first)
        } else {
            selectedCommunity = nil
            members = []
        }
    }
    
    private func updateLegacyFamilyIdIfEmpty(_ familyId: UUID) async {
        guard let userId = AuthManager.shared.session?.user.id else { return }
        
        do {
            let profile: Profile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            
            guard profile.family_id == nil else { return }
            
            struct ProfileUpdate: Encodable {
                let family_id: UUID
            }
            
            try await client
                .from("profiles")
                .update(ProfileUpdate(family_id: familyId))
                .eq("id", value: userId)
                .execute()
        } catch {
            print("Legacy family_id update error: \(error)")
        }
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
            
            // 2. Add creator membership
            try await membershipManager.addCurrentUser(to: family.id)
            await updateLegacyFamilyIdIfEmpty(family.id)
            
            newFamilyName = ""
            await refreshAfterMembershipChange(select: family)
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
            try await membershipManager.addCurrentUser(to: family.id)
            await updateLegacyFamilyIdIfEmpty(family.id)
            
            joinCode = ""
            await refreshAfterMembershipChange(select: family)
            
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
        guard let familyId = selectedCommunity?.id else { return }
        isLoading = true
        
        do {
            try await membershipManager.removeCurrentUser(from: familyId)
            await refreshAfterMembershipChange()
        } catch {
            errorMessage = "Failed to leave family."
        }
        
        isLoading = false
    }
}

struct CommunityView: View {
    @StateObject private var viewModel = FamilyViewModel()
    @Binding var communityTab: Int
    @State private var showingSettings = false
    
    var body: some View {
        NavigationStack {
            VStack {
                if viewModel.isLoading {
                    ProgressView()
                } else if let family = viewModel.family {
                    // Active Community View
                    VStack(spacing: 0) {
                        if viewModel.communities.count > 1 {
                            Picker("Community", selection: Binding(
                                get: { viewModel.selectedCommunity?.id ?? family.id },
                                set: { newValue in
                                    Task { await viewModel.selectCommunity(id: newValue) }
                                }
                            )) {
                                ForEach(viewModel.communities) { community in
                                    Text(community.name).tag(community.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(.horizontal)
                            .padding(.top)
                        }
                        
                        Picker("View", selection: $communityTab) {
                            Text("Feed").tag(0)
                            Text("Leaders").tag(1)
                            Text("Challenges").tag(2)
                            Text("Members").tag(3)
                        }
                        .pickerStyle(.segmented)
                        .padding()
                        
                        TabView(selection: $communityTab) {
                            SocialFeedView(familyId: family.id)
                                .tag(0)
                            
                            LeaderboardView(familyId: family.id)
                                .tag(1)
                            
                            ChallengesListView(familyId: family.id)
                                .tag(2)

                            CommunityMembersView(
                                family: family,
                                members: viewModel.members
                            )
                            .tag(3)
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
