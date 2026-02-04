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
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private init() {
        self.client = SupabaseClient(supabaseURL: supabaseUrl, supabaseKey: supabaseKey)
        
        Task {
            await checkSession()
        }
    }
    
    @MainActor
    func checkSession() async {
        do {
            let session = try await client.auth.session
            self.session = session
            self.isAuthenticated = true
        } catch {
            self.isAuthenticated = false
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
        } catch {
            errorMessage = "Verification Error: \(error.localizedDescription)"
        }
        
        isLoading = false
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
