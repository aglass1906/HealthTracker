//
//  LoginView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/3/26.
//

import SwiftUI

struct LoginView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var email = ""
    @State private var otpCode = ""
    @State private var isCodeSent = false
    @FocusState private var focusedField: Field?
    
    enum Field {
        case email
        case code
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "figure.social.dance")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue)
                    
                    Text("HealthTracker Family")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text(isCodeSent ? "Enter the code sent to your email" : "Sign in to join family challenges")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                // Form
                VStack(spacing: 16) {
                    if !isCodeSent {
                        TextField("Email Address", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .focused($focusedField, equals: .email)
                            .submitLabel(.go)
                            .onSubmit {
                                sendCode()
                            }
                        
                        Button {
                            sendCode()
                        } label: {
                            HStack {
                                if authManager.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Send Code")
                                }
                            }
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isValidEmail ? Color.blue : Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(!isValidEmail || authManager.isLoading)
                    } else {
                        TextField("6-Digit Code", text: $otpCode)
                            .keyboardType(.numberPad)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .focused($focusedField, equals: .code)
                            .submitLabel(.join)
                            .onSubmit {
                                verifyCode()
                            }
                        
                        Button {
                            verifyCode()
                        } label: {
                            HStack {
                                if authManager.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Verify & Sign In")
                                }
                            }
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(otpCode.count >= 6 ? Color.blue : Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(otpCode.count < 6 || authManager.isLoading)
                        
                        Button("Send New Code") {
                            isCodeSent = false
                            otpCode = ""
                        }
                        .font(.subheadline)
                        .padding(.top)
                    }
                }
                .padding(.horizontal)
                
                if let error = authManager.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                }
                
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
        }
    }
    
    private var isValidEmail: Bool {
        email.contains("@") && email.contains(".")
    }
    
    private func sendCode() {
        Task {
            await authManager.signInWithOTP(email: email)
            if authManager.errorMessage == nil {
                withAnimation {
                    isCodeSent = true
                    focusedField = .code
                }
            }
        }
    }
    
    private func verifyCode() {
        Task {
            await authManager.verifyOTP(email: email, token: otpCode)
        }
    }
}

#Preview {
    LoginView()
}
