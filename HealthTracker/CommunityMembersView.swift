//
//  CommunityMembersView.swift
//  HealthTracker
//

import SwiftUI
import Supabase
import Combine

struct CommunityMemberSummary: Codable {
    let stat_date: String?
    let steps: Int?
    let calories: Int?
    let distance: Double?
    let exercise_minutes: Int?
    let workouts_count: Int?
    let move_ring_value: Double?
    let exercise_ring_value: Double?
    let stand_ring_value: Double?
    let nutrition_date: String?
    let nutrition_calories: Double?
    let protein_g: Double?
    let carb_g: Double?
    let fat_g: Double?
    let protein_goal_g: Double?
    let carb_goal_g: Double?
    let fat_goal_g: Double?
    let last_update_at: String?
    let last_update_type: String?
}

@MainActor
final class CommunityMembersViewModel: ObservableObject {
    @Published var summaries: [UUID: CommunityMemberSummary] = [:]
    @Published var isLoading = false

    func fetchSummaries(familyId: UUID, members: [Profile]) async {
        isLoading = true
        defer { isLoading = false }

        var fetched: [UUID: CommunityMemberSummary] = [:]
        for member in members {
            fetched[member.id] = await Self.fetchSummary(
                familyId: familyId,
                memberId: member.id
            )
        }
        summaries = fetched
    }

    static func fetchSummary(
        familyId: UUID,
        memberId: UUID
    ) async -> CommunityMemberSummary? {
        do {
            let rows: [CommunityMemberSummary] = try await AuthManager.shared.client
                .rpc(
                    "community_member_summary",
                    params: [
                        "community_id": familyId.uuidString,
                        "member_id": memberId.uuidString
                    ]
                )
                .execute()
                .value
            return rows.first
        } catch {
            print("Community member summary fetch error: \(error)")
            return nil
        }
    }
}

struct CommunityMembersView: View {
    let family: Family
    let members: [Profile]

    @StateObject private var viewModel = CommunityMembersViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                inviteCodeCard

                if viewModel.isLoading && viewModel.summaries.isEmpty {
                    ProgressView("Loading members...")
                        .padding(.top, 32)
                } else if members.isEmpty {
                    ContentUnavailableView(
                        "No Members Yet",
                        systemImage: "person.2",
                        description: Text("Share the invite code to grow this community.")
                    )
                    .padding(.top, 24)
                } else {
                    ForEach(members) { member in
                        NavigationLink {
                            CommunityMemberDetailView(
                                familyId: family.id,
                                member: member,
                                initialSummary: viewModel.summaries[member.id]
                            )
                        } label: {
                            CommunityMemberRow(
                                member: member,
                                summary: viewModel.summaries[member.id]
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .refreshable {
            await viewModel.fetchSummaries(familyId: family.id, members: members)
        }
        .task(id: family.id) {
            await viewModel.fetchSummaries(familyId: family.id, members: members)
        }
    }

    private var inviteCodeCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.badge.plus")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 42, height: 42)
                .background(.blue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Invite people to \(family.name)")
                    .font(.subheadline.weight(.semibold))
                Text(family.invite_code)
                    .font(.title3.monospaced().weight(.bold))
                    .tracking(2)
            }

            Spacer()

            ShareLink(item: "Join my \(family.name) community in HealthTracker with code \(family.invite_code)") {
                Image(systemName: "square.and.arrow.up")
                    .font(.headline)
                    .padding(10)
                    .background(Color(.tertiarySystemBackground), in: Circle())
            }
            .accessibilityLabel("Share invite code")
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct CommunityMemberRow: View {
    let member: Profile
    let summary: CommunityMemberSummary?

    var body: some View {
        HStack(spacing: 12) {
            MemberAvatar(profile: member, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(member.display_name ?? member.email ?? "Community Member")
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 5) {
                    Image(systemName: updateIcon)
                    Text(updateText)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var updateText: String {
        guard let summary,
              let rawDate = summary.last_update_at,
              let date = rawDate.dateValueOptional else {
            return "No updates yet"
        }

        return "\(summary.last_update_type?.memberDisplayName ?? "Updated") \(date.relativeDescription)"
    }

    private var updateIcon: String {
        summary?.last_update_type?.memberUpdateIcon ?? "clock"
    }
}

struct CommunityMemberDetailView: View {
    let familyId: UUID
    let member: Profile
    let initialSummary: CommunityMemberSummary?

    @State private var summary: CommunityMemberSummary?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    MemberAvatar(profile: member, size: 76)
                    Text(member.display_name ?? member.email ?? "Community Member")
                        .font(.title2.bold())
                    if let updateDescription {
                        Label(updateDescription, systemImage: summary?.last_update_type?.memberUpdateIcon ?? "clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top)

                if isLoading && summary == nil {
                    ProgressView()
                        .padding(.top, 30)
                } else {
                    activityCard
                    activityRingsCard
                    nutritionCard
                    nutritionRingsCard
                }
            }
            .padding()
        }
        .navigationTitle("Member Summary")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            summary = initialSummary
            isLoading = true
            summary = await CommunityMembersViewModel.fetchSummary(
                familyId: familyId,
                memberId: member.id
            ) ?? initialSummary
            isLoading = false
        }
    }

    private var activityCard: some View {
        SummarySectionCard(
            title: "Exercise",
            subtitle: summary?.stat_date.map { "Latest data: \($0.formattedDatabaseDate)" },
            icon: "figure.run",
            color: .orange,
            metrics: [
                SummaryMetric(title: "Steps", value: summary?.steps.formattedValue ?? "--"),
                SummaryMetric(title: "Exercise", value: summary?.exercise_minutes.map { "\($0) min" } ?? "--"),
                SummaryMetric(title: "Workouts", value: summary?.workouts_count.formattedValue ?? "--"),
                SummaryMetric(title: "Distance", value: summary?.distance.map { Self.distanceFormatter.string(from: NSNumber(value: $0 / 1609.344)) ?? "--" } ?? "--")
            ]
        )
    }

    private var nutritionCard: some View {
        SummarySectionCard(
            title: "Nutrition",
            subtitle: summary?.nutrition_date.map { "Latest data: \($0.formattedDatabaseDate)" },
            icon: "leaf.fill",
            color: .green,
            metrics: [
                SummaryMetric(title: "Calories", value: summary?.nutrition_calories.roundedValue ?? "--"),
                SummaryMetric(title: "Protein", value: summary?.protein_g.gramsValue ?? "--"),
                SummaryMetric(title: "Carbs", value: summary?.carb_g.gramsValue ?? "--"),
                SummaryMetric(title: "Fat", value: summary?.fat_g.gramsValue ?? "--")
            ]
        )
    }

    private var activityRingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Activity Rings", systemImage: "circle.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.pink)

                Spacer()

                if let statDate = summary?.stat_date {
                    Text("Latest data: \(statDate.formattedDatabaseDate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let summary,
               summary.move_ring_value != nil ||
               summary.exercise_ring_value != nil ||
               summary.stand_ring_value != nil {
                HStack(spacing: 12) {
                    memberRing(
                        value: summary.move_ring_value ?? 0,
                        goal: 600,
                        color: .red,
                        title: "Move",
                        unit: "kcal"
                    )
                    memberRing(
                        value: summary.exercise_ring_value ?? 0,
                        goal: 30,
                        color: .green,
                        title: "Exercise",
                        unit: "min"
                    )
                    memberRing(
                        value: summary.stand_ring_value ?? 0,
                        goal: 12,
                        color: .blue,
                        title: "Stand",
                        unit: "hrs"
                    )
                }
                .frame(maxWidth: .infinity)

                Text("Progress uses HealthTracker standard targets.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text("No activity ring data yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var nutritionRingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Nutrition Rings", systemImage: "chart.pie.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                Spacer()

                if let nutritionDate = summary?.nutrition_date {
                    Text("Latest data: \(nutritionDate.formattedDatabaseDate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let summary,
               let proteinGoal = summary.protein_goal_g,
               let carbGoal = summary.carb_goal_g,
               let fatGoal = summary.fat_goal_g {
                HStack(spacing: 12) {
                    NutritionMacroRing(
                        title: "Protein",
                        value: summary.protein_g ?? 0,
                        goal: proteinGoal,
                        color: .blue
                    )
                    NutritionMacroRing(
                        title: "Carbs",
                        value: summary.carb_g ?? 0,
                        goal: carbGoal,
                        color: .orange
                    )
                    NutritionMacroRing(
                        title: "Fat",
                        value: summary.fat_g ?? 0,
                        goal: fatGoal,
                        color: .purple
                    )
                }
            } else {
                Text("No active macro goals yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func memberRing(
        value: Double,
        goal: Double,
        color: Color,
        title: String,
        unit: String
    ) -> some View {
        RingView(
            progress: min(max(value / goal, 0), 1),
            color: color,
            title: title,
            value: value.formatted(.number.precision(.fractionLength(0))),
            goal: goal.formatted(.number.precision(.fractionLength(0))),
            unit: unit
        )
        .scaleEffect(0.9)
        .frame(maxWidth: .infinity)
    }

    private var updateDescription: String? {
        guard let summary,
              let rawDate = summary.last_update_at,
              let date = rawDate.dateValueOptional else { return nil }
        return "\(summary.last_update_type?.memberDisplayName ?? "Updated") \(date.relativeDescription)"
    }

    private static let distanceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.positiveSuffix = " mi"
        return formatter
    }()
}

private struct NutritionMacroRing: View {
    let title: String
    let value: Double
    let goal: Double
    let color: Color

    private var percentage: Double {
        guard goal > 0 else { return 0 }
        return value / goal
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 10)

                Circle()
                    .trim(from: 0, to: min(max(percentage, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text(percentageText)
                    .font(.headline.bold())
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 76, height: 76)
            .animation(.easeInOut, value: percentage)

            Text(title)
                .font(.caption.weight(.semibold))

            Text("\(whole(value))/\(whole(goal))g")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private var percentageText: String {
        guard goal > 0 else { return "--" }
        return "\(Int((percentage * 100).rounded()))%"
    }

    private func whole(_ number: Double) -> String {
        number.formatted(.number.precision(.fractionLength(0)))
    }
}

private struct SummaryMetric {
    let title: String
    let value: String
}

private struct SummarySectionCard: View {
    let title: String
    let subtitle: String?
    let icon: String
    let color: Color
    let metrics: [SummaryMetric]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(color)
                Spacer()
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(metric.value)
                            .font(.title3.weight(.semibold))
                        Text(metric.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct MemberAvatar: View {
    let profile: Profile
    let size: CGFloat

    var body: some View {
        Group {
            if let avatar = profile.avatar_url, let url = URL(string: avatar) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initials
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: some View {
        Text(String((profile.display_name ?? profile.email ?? "?").prefix(1)).uppercased())
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.blue)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.blue.opacity(0.12))
    }
}

private extension String {
    var dateValueOptional: Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: self) ?? ISO8601DateFormatter().date(from: self)
    }

    var formattedDatabaseDate: String {
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: self) else { return self }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    var memberDisplayName: String {
        switch self {
        case "nutrition": return "Logged nutrition"
        case "activity": return "Synced activity"
        case "workout_finished": return "Finished a workout"
        case "goal_met": return "Hit a goal"
        case "joined_family": return "Joined the community"
        case let value where value.hasPrefix("ring_closed"): return "Closed an activity ring"
        case let value where value.contains("challenge"): return "Updated a challenge"
        default: return "Posted an update"
        }
    }

    var memberUpdateIcon: String {
        switch self {
        case "nutrition": return "leaf.fill"
        case "activity": return "figure.walk"
        case "workout_finished": return "figure.run"
        case "goal_met": return "target"
        case "joined_family": return "person.badge.plus"
        case let value where value.hasPrefix("ring_closed"): return "circle.fill"
        case let value where value.contains("challenge"): return "flag.checkered"
        default: return "clock"
        }
    }
}

private extension Date {
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

private extension Optional where Wrapped == Int {
    var formattedValue: String? {
        map { $0.formatted() }
    }
}

private extension Optional where Wrapped == Double {
    var roundedValue: String? {
        map { Int($0.rounded()).formatted() }
    }

    var gramsValue: String? {
        map { "\(Int($0.rounded()).formatted()) g" }
    }
}
