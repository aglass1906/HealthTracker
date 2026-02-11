//
//  AdminManager.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/10/26.
//

import Foundation
import Combine
import SwiftUI
import Supabase

class AdminManager: ObservableObject {
    static let shared = AdminManager()
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let functionName = "admin-actions"
    
    private init() {}
    
    struct AdminUser: Codable, Identifiable {
        let id: UUID
        let email: String?
        let display_name: String
        let created_at: String
    }
    
    struct AdminUserListResponse: Codable {
        let users: [AdminUser]
    }
    
    @MainActor
    func fetchUsers() async -> [AdminUser] {
        isLoading = true
        errorMessage = nil
        
        guard let session = AuthManager.shared.session else {
            isLoading = false
            errorMessage = "No active session"
            return []
        }
        
        do {
            let response: AdminUserListResponse = try await AuthManager.shared.client.functions
                .invoke(
                    functionName,
                    options: FunctionInvokeOptions(
                        headers: ["Authorization": "Bearer \(session.accessToken)"],
                        body: ["action": "get_users"]
                    )
                )
            
            isLoading = false
            return response.users
        } catch let error as FunctionsError {
            isLoading = false
            errorMessage = "Function Error: \(error.localizedDescription)"
            if case .httpError(let code, let data) = error {
                let responseString = String(data: data, encoding: .utf8) ?? "No data"
                print("Admin fetch failed with code \(code): \(responseString)")
                errorMessage = "Error \(code): \(responseString)"
            } else {
                 print("Admin fetch error (FunctionsError): \(error)")
            }
            return []
        } catch {
            isLoading = false
            errorMessage = "Failed to fetch users: \(error.localizedDescription)"
            print("Admin fetch error: \(error)")
            return []
        }
    }
    
    struct actionResponse: Decodable {
        let success: Bool
        let message: String
    }

    @MainActor
    func updateUserPassword(userId: UUID, newPassword: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        guard let session = AuthManager.shared.session else {
            isLoading = false
            errorMessage = "No active session"
            return false
        }
        
        do {
            let _: actionResponse = try await AuthManager.shared.client.functions
                .invoke(
                    functionName,
                    options: FunctionInvokeOptions(
                        headers: ["Authorization": "Bearer \(session.accessToken)"],
                        body: [
                            "action": "update_password",
                            "userId": userId.uuidString.lowercased(),
                            "newPassword": newPassword
                        ]
                    )
                )
            
            isLoading = false
            return true
        } catch let error as FunctionsError {
            isLoading = false
            errorMessage = "Function Error: \(error.localizedDescription)"
            if case .httpError(let code, let data) = error {
                let responseString = String(data: data, encoding: .utf8) ?? "No data"
                print("Admin update failed with code \(code): \(responseString)")
                errorMessage = "Error \(code): \(responseString)"
            } else {
                 print("Admin update error (FunctionsError): \(error)")
            }
            return false
        } catch {
            isLoading = false
            errorMessage = "Failed to update password: \(error.localizedDescription)"
            print("Admin update error: \(error)")
            return false
        }
    }
}
