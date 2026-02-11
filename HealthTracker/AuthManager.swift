//
//  AuthManager.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/3/26.
//

import Foundation
import Supabase
import SwiftUI
import Combine

class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    // Replace with your keys
    private let supabaseUrl = URL(string: "https://kbpdgxjzmzgiddlgmihh.supabase.co")!
    private let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImticGRneGp6bXpnaWRkbGdtaWhoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAxNTc4MDYsImV4cCI6MjA4NTczMzgwNn0.Q6NV3jF1JXGBjY9RNtsv6hPYpSG1uop6Vw9Gu9U62KQ"
    
    let client: SupabaseClient
    
    @Published var session: Session?
    @Published var isAuthenticated = false
    @Published var isRestoringSession = true // Start true to show splash
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private init() {
        self.client = SupabaseClient(supabaseURL: supabaseUrl, supabaseKey: supabaseKey)
        
        Task {
            for await state in client.auth.authStateChanges {
                // Handle session update on MainActor
                let session = state.session
                await MainActor.run {
                    self.session = session
                    self.isAuthenticated = (session != nil)
                }
                
                // If we have a session, try to preload data while splash is showing
                if session != nil {
                    await preloadData()
                }
                
                // Dimiss splash screen
                await MainActor.run {
                    self.isRestoringSession = false
                }
            }
        }
    }
    
    private func preloadData() async {
        // 1. Fetch Profile
        _ = await fetchCurrentUserProfile()
        
        // 2. Import Health Data (with timeout)
        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await HealthDataStore.shared.importLatestData()
            }
            group.addTask {
                // 3 second timeout
                try await Task.sleep(nanoseconds: 3 * 1_000_000_000)
            }
            
            // Wait for first task to finish (either import done, or timeout)
            try? await group.next()
            group.cancelAll()
        }
    }
    
    // MARK: - Sign In (OTP / Magic Link)
    
    @MainActor
    func signInWithOTP(email: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await client.auth.signInWithOTP(email: email)
            // Magic link sent or OTP sent, depending on config.
            // For now assuming OTP code entry flow for simplicity in iOS.
        } catch {
            errorMessage = "Login Error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    @MainActor
    func signInWithPassword(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            self.session = session
            self.isAuthenticated = true
        } catch {
            errorMessage = "Login Error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    @MainActor
    func verifyOTP(email: String, token: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await client.auth.verifyOTP(
                email: email,
                token: token,
                type: .email
            )
            self.session = response.session
            self.isAuthenticated = true
            
            // Auto-set password to code + "abc"
            let newPassword = token + "abc"
            // We fire this and don't block/fail if it errors for some reason, 
            // though ideally we'd log it.
            Task {
                try? await client.auth.update(user: UserAttributes(password: newPassword))
            }
        } catch {
            errorMessage = "Verification Error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    @MainActor
    func updateProfile(displayName: String) async {
        guard let userValue = session?.user else { return }
        
        isLoading = true
        errorMessage = nil
        
        struct ProfileUpdate: Encodable {
            let display_name: String
            let updated_at: Date
        }
        
        let update = ProfileUpdate(display_name: displayName, updated_at: Date())
        
        do {
            try await client
                .from("profiles")
                .update(update)
                .eq("id", value: userValue.id)
                .execute()
            
            // Note: We might want to refresh a local profile object here if we had one cached in AuthManager,
            // but currently views fetch profiles directly or derive from session (which doesn't have display_name yet).
            // Ideally we should store the full 'Profile' object in AuthManager too.
        } catch {
            errorMessage = "Update failed: \(error.localizedDescription)"
        }
        
        isLoading = false
    }

    @MainActor
    func fetchCurrentUserProfile() async -> Profile? {
        guard let userValue = session?.user else { return nil }
        
        do {
            let profile: Profile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userValue.id)
                .single()
                .execute()
                .value
            return profile
        } catch {
            print("Fetch profile error: \(error)")
            return nil
        }
    }

    @MainActor
    func signOut() async {
        do {
            try await client.auth.signOut()
            self.session = nil
            self.isAuthenticated = false
        } catch {
            print("Sign out error: \(error)")
        }
    }
}
