//
//  CommunityMembershipManager.swift
//  HealthTracker
//

import Foundation
import Supabase

struct FamilyMembership: Codable, Identifiable {
    let id: UUID?
    let family_id: UUID
    let user_id: UUID
    let role: String?
    let joined_at: String?
}

struct CommunityWithMembership: Identifiable {
    let family: Family
    let membership: FamilyMembership?

    var id: UUID { family.id }
}

class CommunityMembershipManager {
    static let shared = CommunityMembershipManager()

    private let client = AuthManager.shared.client

    private init() {}

    func fetchCommunityIdsForCurrentUser() async -> [UUID] {
        guard let userId = AuthManager.shared.session?.user.id else { return [] }

        do {
            let memberships: [FamilyMembership] = try await client
                .from("family_memberships")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value

            if memberships.isEmpty,
               let legacyFamilyId = await backfillLegacyMembershipIfNeeded(userId: userId) {
                return [legacyFamilyId]
            }

            return memberships.map(\.family_id)
        } catch {
            print("Fetch community ids error: \(error)")

            if let legacyFamilyId = await fetchLegacyFamilyId(userId: userId) {
                return [legacyFamilyId]
            }

            return []
        }
    }

    func fetchCommunitiesForCurrentUser() async -> [Family] {
        let communityIds = await fetchCommunityIdsForCurrentUser()
        guard !communityIds.isEmpty else { return [] }

        do {
            let families: [Family] = try await client
                .from("families")
                .select()
                .in("id", values: communityIds)
                .execute()
                .value

            return families.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            print("Fetch communities error: \(error)")
            return []
        }
    }

    func fetchMembers(for familyId: UUID) async -> [Profile] {
        do {
            let memberships: [FamilyMembership] = try await client
                .from("family_memberships")
                .select()
                .eq("family_id", value: familyId)
                .execute()
                .value

            let userIds = memberships.map(\.user_id)
            guard !userIds.isEmpty else { return [] }

            let profiles: [Profile] = try await client
                .from("profiles")
                .select()
                .in("id", values: userIds)
                .execute()
                .value

            return profiles.sorted {
                ($0.display_name ?? $0.email ?? "").localizedCaseInsensitiveCompare($1.display_name ?? $1.email ?? "") == .orderedAscending
            }
        } catch {
            print("Fetch community members error: \(error)")
            return []
        }
    }

    func addCurrentUser(to familyId: UUID, role: String = "member") async throws {
        guard let userId = AuthManager.shared.session?.user.id else { return }

        struct MembershipInsert: Encodable {
            let family_id: UUID
            let user_id: UUID
            let role: String
        }

        let membership = MembershipInsert(
            family_id: familyId,
            user_id: userId,
            role: role
        )

        try await client
            .from("family_memberships")
            .upsert(membership, onConflict: "family_id,user_id")
            .execute()
    }

    func removeCurrentUser(from familyId: UUID) async throws {
        guard let userId = AuthManager.shared.session?.user.id else { return }

        try await client
            .from("family_memberships")
            .delete()
            .eq("family_id", value: familyId)
            .eq("user_id", value: userId)
            .execute()
    }

    @discardableResult
    func backfillLegacyMembershipIfNeeded(userId: UUID) async -> UUID? {
        guard let legacyFamilyId = await fetchLegacyFamilyId(userId: userId) else { return nil }

        struct MembershipInsert: Encodable {
            let family_id: UUID
            let user_id: UUID
            let role: String
        }

        do {
            try await client
                .from("family_memberships")
                .upsert(
                    MembershipInsert(family_id: legacyFamilyId, user_id: userId, role: "member"),
                    onConflict: "family_id,user_id"
                )
                .execute()
        } catch {
            print("Legacy membership backfill error: \(error)")
        }

        return legacyFamilyId
    }

    private func fetchLegacyFamilyId(userId: UUID) async -> UUID? {
        do {
            let profile: Profile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            return profile.family_id
        } catch {
            print("Fetch legacy family id error: \(error)")
            return nil
        }
    }
}
