//
//  OnboardingView.swift
//  HealthTracker
//
//  Created by Alan Glass on 2/4/26.
//

import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentStep = 0
    @State private var displayName = ""
    @State private var isHealthAuthorized = false
    @StateObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var familyViewModel = FamilyViewModel() // Reuse existing logic
    @Environment(\.dismiss) private var dismiss
    
    // Transition namespace for smooth animations if we want them, 
    // but TabView with page style is robust.
    
    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(colors: [Color.blue.opacity(0.1), Color(.systemBackground)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            VStack {
                // Progress Indicator
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        Capsule()
                            .fill(index == currentStep ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: index == currentStep ? 20 : 8, height: 8)
                            .animation(.spring(), value: currentStep)
                    }
                }
                .padding(.top, 40)
                
                TabView(selection: $currentStep) {
                    // Step 1: Identity
                    IdentityStep(displayName: $displayName) {
                        nextStep()
                    }
                    .tag(0)
                    
                    // Step 2: Health
                    HealthPermissionStep(isAuthorized: $isHealthAuthorized) {
                        nextStep()
                    }
                    .tag(1)
                    
                    // Step 3: Family
                    FamilySetupStep(familyViewModel: familyViewModel) {
                        completeOnboarding()
                    }
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentStep)
            }
        }
        .interactiveDismissDisabled()
    }
    
    private func nextStep() {
        if currentStep == 0 {
            // Save Name
            Task {
                await AuthManager.shared.updateProfile(displayName: displayName)
            }
        }
        withAnimation {
            currentStep += 1
        }
    }
    
    private func completeOnboarding() {
        withAnimation {
            hasCompletedOnboarding = true
        }
    }
}

// MARK: - Step 1: Identity
struct IdentityStep: View {
    @Binding var displayName: String
    var onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 100))
                .foregroundStyle(.blue)
                .symbolEffect(.bounce, value: true)
            
            VStack(spacing: 12) {
                Text("Who are you?")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Choose a display name for the leaderboard.\nThis is how your family will see you.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            
            TextField("e.g. Dad, IronMan, Sarah", text: $displayName)
                .font(.title2)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
                .padding(.horizontal, 32)
                .multilineTextAlignment(.center)
                .submitLabel(.next)
                .onSubmit {
                    if !displayName.isEmpty { onNext() }
                }
            
            Spacer()
            
            Button(action: onNext) {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(displayName.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                    .cornerRadius(16)
            }
            .disabled(displayName.isEmpty)
            .padding(.horizontal, 32)
            .padding(.bottom, 50)
        }
    }
}

// MARK: - Step 2: Health Permissions
struct HealthPermissionStep: View {
    @StateObject private var healthKitManager = HealthKitManager.shared
    @Binding var isAuthorized: Bool
    var onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 100))
                .foregroundStyle(.pink)
                .symbolEffect(.pulse)
            
            VStack(spacing: 12) {
                Text("Power the Game")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("We need access to your Steps and Activity to track your progress on the family leaderboard.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "figure.walk", text: "Track Steps & Distance", color: .green)
                FeatureRow(icon: "flame.fill", text: "Count Calories Burned", color: .orange)
                FeatureRow(icon: "crown.fill", text: "Win Daily Challenges", color: .yellow)
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            if healthKitManager.isAuthorized {
                 Button(action: onNext) {
                    Label("Access Granted!", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
            } else {
                Button {
                    Task {
                        try? await healthKitManager.requestAuthorization()
                        // Wait a sec for UI to update
                        try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
                        if healthKitManager.isAuthorized {
                            isAuthorized = true
                            onNext() // Auto advance if successful? Or let them tap continue.
                        }
                    }
                } label: {
                    Text("Unlock Health Access")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - Step 3: Family Setup
struct FamilySetupStep: View {
    @ObservedObject var familyViewModel: FamilyViewModel
    var onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "person.3.fill")
                .font(.system(size: 80))
                .foregroundStyle(.indigo)
            
            VStack(spacing: 12) {
                Text("Join the Squad")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Join an existing family group to begin competing.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            
            // Join Family Input
            VStack(spacing: 16) {
                TextField("6-Digit Invite Code", text: $familyViewModel.joinCode)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 32)
                
                Button {
                    Task {
                        await familyViewModel.joinFamily()
                        onComplete()
                    }
                } label: {
                    Text("Join Existing Family")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(familyViewModel.joinCode.count < 6 ? Color.gray.opacity(0.3) : Color.blue)
                        .cornerRadius(16)
                }
                .disabled(familyViewModel.joinCode.count < 6)
                .padding(.horizontal, 32)
            }
            
            Spacer()
            
            Button("Skip for Now") {
                onComplete()
            }
            .foregroundStyle(.secondary)
            .padding(.bottom, 50)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 30)
            Text(text)
                .font(.headline)
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

#Preview {
    OnboardingView()
}
