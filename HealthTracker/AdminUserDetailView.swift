//
//  AdminUserDetailView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/10/26.
//

import SwiftUI

struct AdminUserDetailView: View {
    let user: AdminManager.AdminUser
    @StateObject private var adminManager = AdminManager.shared
    @State private var newPassword = ""
    @State private var successMessage: String?
    
    var body: some View {
        Form {
            Section(header: Text("User Details")) {
                LabeledContent("Display Name", value: user.display_name)
                LabeledContent("Email", value: user.email ?? "N/A")
                LabeledContent("User ID", value: user.id.uuidString)
                    .font(.caption)
                    .textSelection(.enabled)
                LabeledContent("Created At", value: user.created_at)
            }
            
            Section(header: Text("Reset Password")) {
                SecureField("New Password", text: $newPassword)
                Button("Update Password") {
                    Task {
                        let success = await adminManager.updateUserPassword(
                            userId: user.id,
                            newPassword: newPassword
                        )
                        if success {
                            newPassword = ""
                            successMessage = "Password updated successfully."
                        }
                    }
                }
                .disabled(newPassword.isEmpty || newPassword.count < 6)
            }
        }
        .navigationTitle(user.display_name)
        .overlay {
            if adminManager.isLoading {
                ProgressView()
            }
        }
        .alert(item: Binding<String?>(
            get: { adminManager.errorMessage ?? successMessage },
            set: { newValue in
                if newValue == adminManager.errorMessage {
                    adminManager.errorMessage = newValue
                } else {
                    successMessage = newValue
                }
            }
        )) { message in
            Alert(
                title: Text(message == successMessage ? "Success" : "Error"),
                message: Text(message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
