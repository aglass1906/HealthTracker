//
//  EditProfileView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/4/26.
//

import SwiftUI
import Supabase

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authManager = AuthManager.shared
    
    @State private var displayName = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .center, spacing: 16) {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 80, height: 80)
                            .overlay {
                                Text(initials)
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.blue)
                            }
                        
                        Text(authManager.session?.user.email ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                
                Section("Display Name") {
                    TextField("Enter your name (e.g. Dad)", text: $displayName)
                        .textContentType(.name)
                }
                
                Section {
                    Button {
                        saveProfile()
                    } label: {
                        if isLoading {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            Text("Save Changes")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }
                    }
                    .listRowBackground(Color.blue)
                    .disabled(displayName.isEmpty || isLoading)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProfile()
                    }
                    .disabled(displayName.isEmpty || isLoading)
                }
            }
            .task {
                await loadProfile()
            }
            .disabled(isLoading)
        }
    }
    
    private var initials: String {
        if !displayName.isEmpty {
            let components = displayName.components(separatedBy: " ")
            let first = components.first?.prefix(1) ?? ""
            let last = components.count > 1 ? components.last?.prefix(1) ?? "" : ""
            return "\(first)\(last)".uppercased()
        }
        
        // Fallback to email
        if let email = authManager.session?.user.email {
            return String(email.prefix(2)).uppercased()
        }
        
        return "?"
    }
    
    private func loadProfile() async {
        isLoading = true
        if let profile = await authManager.fetchCurrentUserProfile() {
            if let name = profile.display_name {
                displayName = name
            }
        }
        isLoading = false
    }
    
    private func saveProfile() {
        isLoading = true
        Task {
            await authManager.updateProfile(displayName: displayName)
            isLoading = false
            dismiss()
        }
    }
}

#Preview {
    EditProfileView()
}
