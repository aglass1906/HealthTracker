import SwiftUI
import Supabase

struct ChallengeDetailView: View {
    let challenge: Challenge
    @StateObject private var viewModel = ChallengeViewModel()
    @State private var showingEdit = false
    @State private var selectedTab = 0
    @State private var leaderboardMode = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header

            if challenge.round_duration != nil {
                Picker("View", selection: $selectedTab) {
                    Text("Leaderboard").tag(0)
                    Text("Rounds").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
            }

            if selectedTab == 1, challenge.round_duration != nil {
                ChallengeRoundsView(challenge: challenge, viewModel: viewModel)
            } else {
                leaderboardView
            }
        }
        .navigationTitle("Challenge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if challenge.status != .completed,
               challenge.creator_id == AuthManager.shared.session?.user.id {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { showingEdit = true }
                }
            }
        }
        .sheet(isPresented: $showingEdit, onDismiss: reload) {
            EditChallengeView(challenge: challenge, viewModel: viewModel) {
                dismiss()
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: viewModel.challengeMetrics.count > 1 ? "square.grid.2x2.fill" : challenge.metric.icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.blue)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.title)
                        .font(.headline)
                        .fontWeight(.bold)
                    if let creatorName = viewModel.creatorName {
                        Text("by \(creatorName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            Divider()

            HStack {
                Text(goalText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(goalColor.opacity(0.1))
                    .foregroundStyle(goalColor)
                    .cornerRadius(8)
                Spacer()
                if let duration = challenge.roundDuration {
                    Text("\(duration.displayName) Rounds")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.purple)
                }
            }

            if !viewModel.challengeMetrics.isEmpty {
                Text(viewModel.challengeMetrics.map(\.displayName).joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label(challenge.start_date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                Spacer()
                if let endDate = challenge.end_date {
                    Label(endDate.formatted(date: .abbreviated, time: .shortened), systemImage: "flag.checkered")
                } else {
                    Text("Open Ended")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .padding(.horizontal)
        .padding(.top)
    }

    private var goalText: String {
        switch challenge.type {
        case .race:
            return "First to \(challenge.target_value) \(challenge.metric.unit)"
        case .streak:
            return "\(challenge.target_value) \(challenge.metric.unit) / day"
        case .count:
            return viewModel.challengeMetrics.count > 1 ? "Most metric wins" : "Most \(challenge.metric.displayName)"
        }
    }

    private var goalColor: Color {
        switch challenge.type {
        case .race: return .blue
        case .streak: return .orange
        case .count: return .purple
        }
    }

    private var leaderboardView: some View {
        ScrollView {
            if viewModel.isLoading {
                ProgressView().padding()
            } else if challenge.type == .count {
                multiMetricContent
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.participants) {
                        ParticipantRow(
                            participant: $0,
                            target: Double(challenge.target_value),
                            metric: challenge.metric,
                            type: challenge.type
                        )
                    }
                }
                .padding()
            }
        }
    }

    private var multiMetricContent: some View {
        VStack(spacing: 16) {
            if challenge.round_duration != nil {
                Picker("Standings", selection: $leaderboardMode) {
                    Text("Overall").tag(0)
                    Text("Current Round").tag(1)
                    Text("Totals").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top)
            }

            if leaderboardMode == 0 || challenge.round_duration == nil {
                standingsSection
            }

            let boards = challenge.round_duration != nil && leaderboardMode == 1
                ? viewModel.currentRoundLeaderboards
                : viewModel.metricLeaderboards

            if leaderboardMode != 0 || challenge.round_duration == nil {
                if boards.isEmpty {
                    Text("No activity yet")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ForEach(boards) { leaderboard in
                        MetricLeaderboardSection(leaderboard: leaderboard)
                    }
                }
            }
        }
        .padding(.bottom)
    }

    private var standingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(challenge.round_duration == nil ? "Overall Standings" : "Cumulative Metric Wins")
                .font(.headline)

            if viewModel.overallStandings.allSatisfy({ $0.wins == 0 }) {
                Text("No metric wins yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.overallStandings) { standing in
                    OverallStandingRow(standing: standing)
                }
            }
        }
        .padding()
    }

    private func load() async {
        await viewModel.loadProgress(for: challenge)
        if challenge.round_duration != nil {
            await viewModel.refreshRoundStatuses(for: challenge)
        }
    }

    private func reload() {
        Task { await load() }
    }
}

struct OverallStandingRow: View {
    let standing: ChallengeStanding

    var body: some View {
        HStack {
            Text("#\(standing.rank)")
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 32, height: 32)
                .background(standing.rank == 1 ? Color.yellow : Color.gray.opacity(0.2))
                .foregroundStyle(standing.rank == 1 ? .white : .primary)
                .clipShape(Circle())
            Text(standing.profile.display_name ?? "Unknown")
                .fontWeight(.semibold)
            Spacer()
            Text("\(standing.wins) \(standing.wins == 1 ? "win" : "wins")")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct MetricLeaderboardSection: View {
    let leaderboard: MetricLeaderboard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(leaderboard.metric.displayName, systemImage: leaderboard.metric.icon)
                .font(.headline)

            ForEach(leaderboard.participants) { participant in
                ParticipantRow(
                    participant: participant,
                    target: 0,
                    metric: leaderboard.metric,
                    type: .count
                )
            }
        }
        .padding(.horizontal)
    }
}

struct ParticipantRow: View {
    let participant: ChallengeParticipant
    let target: Double
    let metric: ChallengeMetric
    let type: ChallengeType

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("#\(participant.rank)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .frame(width: 32, height: 32)
                    .background(participant.rank == 1 ? Color.yellow : Color.gray.opacity(0.2))
                    .foregroundStyle(participant.rank == 1 ? .white : .primary)
                    .clipShape(Circle())

                VStack(alignment: .leading) {
                    Text(participant.profile.display_name ?? "Unknown")
                        .fontWeight(.semibold)
                    Text(valueText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if type == .race {
                    Text("\(Int(participant.progress * 100))%")
                        .font(.headline)
                        .foregroundStyle(participant.progress >= 1 ? .green : .blue)
                }
            }

            GeometryReader { geometry in
                Capsule()
                    .fill(Color.gray.opacity(0.1))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(participant.progress >= 1 ? Color.green : Color.blue)
                            .frame(width: min(geometry.size.width * participant.progress, geometry.size.width))
                    }
            }
            .frame(height: 12)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private var valueText: String {
        switch type {
        case .streak:
            return "\(Int(participant.value)) day streak"
        case .count:
            return "\(formatted(participant.value)) \(metric.unit)"
        case .race:
            return "\(formatted(participant.value)) / \(formatted(target)) \(metric.unit)"
        }
    }

    private func formatted(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}
