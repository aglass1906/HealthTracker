# Family Challenge App Implementation Plan

## Goal
Transform the local-only `HealthTracker` app into a social fitness experience where family members can compete in challenges, track shared goals, and view leaderboards.

## Tech Stack Recommendation
*   **Backend**: **Supabase** (Postgres DB + Auth).
    *   *Why*: Native support for Passwordless/OTP login, real-time feeds, and relational data for complex challenges.
*   **Frontend**: SwiftUI.

## Core Features

### 1. User Authentication
*   **Flexible Sign-In**:
    *   **Magic Link / OTP**: Sign in via a 6-digit code sent to email (Encryption-free user experience).
    *   **Passkeys**: Biometric login (FaceID/TouchID).
    *   **Traditional**: Email & Password (optional fallback).
*   **Profile**: Display Name, Avatar (or Initials).

### 2. Family Groups
*   **Create Family**: User creates a group and gets a unique 6-digit Invite Code.
*   **Join Family**: Other users enter the code to join.
*   **Management**: Admin can remove members.

### 3. Challenges
*   **Types**:
    *   **Multi-Metric**: Challenges can track multiple goals simultaneously (e.g., "The Trifecta": 10k steps + 30 active mins + 500 calories).
    *   **Single Metric**: Standard step or distance races.
*   **Scoring**:
    *   **Race**: Cumulative total (First to X).
    *   **Daily Streaks**: Consecutive days hitting all targets.
*   **Duration**: Daily, Weekly, Monthly, or Custom.

### 4. Social Feed & Kudos (New)
*   **Activity Feed**: A timeline showing family achievements (e.g., "Mom finished a 30m run", "Dad hit his step goal").
*   **Interactions**:
    *   **Congrats/Reactions**: One-tap reactions (🔥, 👏, ❤️) to celebrate wins.
    *   **Automated Milestones**: System posts when a challenge leader updates.

### 5. Data Syncing (Crucial)
*   **Logic**: Periodic background fetch of HealthKit data -> Upsert to Supabase `daily_stats`.
*   **Privacy**: Only share aggregate metrics defined in the family context.

## Data Model (Supabase)

### `profiles`
*   `id` (UUID, PK) ...

### `families`
*   `id` (UUID, PK) ...

### `daily_stats`
*   `user_id` (FK), `date`, `steps`, `calories`, `flights`, `distance` (New)

### `challenges`
*   `id` (UUID, PK)
*   `family_id` (FK)
*   `title`
*   `metrics` (JSON: e.g., `{"steps": 10000, "calories": 500}`)
*   `type` (race, daily_goal)
*   `status`
*   `type` (workout_finished, goal_met, challenge_won)
*   `payload` (JSON details)
*   `created_at` (Timestamp)

## Implementation Roadmap

### Phase 1: Foundation (Backend & Auth)
1.  Initialize Supabase project.
2.  Install `Supabase` Swift SDK.
3.  Implement `AuthManager` supporting **OTP/Magic Links**.

### Phase 2: Data Sync Logic
1.  Update `HealthDataStore` to upload data to Supabase.
2.  Implement `SyncManager`.

### Phase 3: Social & Family UI
1.  **Family Tab**: Member list and **Social Feed**.
2.  **Leaderboard**: Real-time stats ranking.
3.  **Kudos**: Interaction logic on feed items.

### Phase 4: Advanced Challenges
1.  Context-aware creation UI (Select multiple metrics).
2.  Complex scoring logic on Backend or Client.

## Next Steps
1.  **Confirm**: Does this updated plan cover everything?
2.  **Action**: I can start setting up the **Supabase Auth (OTP)** integration now.
