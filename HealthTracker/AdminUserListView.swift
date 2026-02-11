//
//  AdminUserListView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/10/26.
//

import SwiftUI

struct AdminUserListView: View {
    @StateObject private var adminManager = AdminManager.shared
    @State private var users: [AdminManager.AdminUser] = []
    
    var body: some View {
        List(users) { user in
            NavigationLink(destination: AdminUserDetailView(user: user)) {
                VStack(alignment: .leading) {
                    Text(user.display_name)
                        .font(.headline)
                    if let email = user.email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .navigationTitle("Admin: Users")
        .onAppear {
            Task {
                users = await adminManager.fetchUsers()
            }
        }
        .overlay {
            if adminManager.isLoading {
                ProgressView()
            }
        }
        .alert(item: Binding<String?>(
            get: { adminManager.errorMessage },
            set: { adminManager.errorMessage = $0 }
        )) { message in
            Alert(title: Text("Error"), message: Text(message), dismissButton: .default(Text("OK")))
        }
    }
}

// Extension to make String Identifiable for Alert
extension String: Identifiable {
    public var id: String { self }
}
