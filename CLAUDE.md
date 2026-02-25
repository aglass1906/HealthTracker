# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Verify

Always build after making code changes to verify correctness. Fix build errors before moving on.

```bash
# Build for simulator
xcodebuild build \
  -project HealthTracker.xcodeproj \
  -scheme HealthTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  | xcpretty || cat

# Build without xcpretty if not installed
xcodebuild build \
  -project HealthTracker.xcodeproj \
  -scheme HealthTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

There are no automated tests in this project. Verification is done by building successfully.

## Architecture

**Stack:** SwiftUI + MVVM, Supabase backend (PostgreSQL), HealthKit, no CoreData.

**Tab structure:** Dashboard → My Data → Community → Profile. Onboarding runs before the main tab view.

### Data Flow

HealthKit → `HealthKitManager` (fetch) → `HealthDataStore` (local UserDefaults cache) → `SyncManager` (upload to Supabase `daily_stats`) → `SocialFeedManager` (post feed events)

Background syncs go through `BackgroundTaskManager`, which coalesces rapid HealthKit delivery callbacks with a 2-second debounce before calling the same sync path.

### Key Singletons

| Class | Role |
|---|---|
| `AuthManager.shared` | Supabase session, profile fetch, `client` accessor |
| `SyncManager.shared` | Uploads `daily_stats`, triggers feed posts |
| `SocialFeedManager.shared` | Posts events to `social_events` table with local+server deduplication |
| `BackgroundTaskManager.shared` | BGAppRefresh + HealthKit background delivery handler |
| `HealthKitManager.shared` | All HealthKit queries |
| `MorningBriefingManager.shared` | Schedules/manages daily briefing notification |

### Feed Event Deduplication

`SocialFeedManager` uses a two-layer approach:
1. **Local:** UserDefaults keys (`posted_goal_{type}_{date}`, `posted_ring_{suffix}_{date}`, `posted_workout_{timestamp}_{type}`) — set **before** spawning the async `Task` to prevent race conditions between concurrent sync triggers.
2. **Server:** `hasPostedToday()` queries `social_events` — used for rings (one per type per day) and as a cross-device guard.

### Database Tables (Supabase)

- `profiles` — user identity, `family_id`, `is_admin`
- `daily_stats` — upserted by date per user (`user_id, date` unique constraint)
- `social_events` — community feed events with `type` and JSON `payload`
- `challenges`, `challenge_rounds`, `challenge_participants`, `round_participants`

### Challenge System

Three types: **Race** (first to cumulative X), **Streak** (consecutive days), **Count** (most by end date). Metrics: steps, calories, distance, exercise minutes, flights, workouts. Rounds can be daily/weekly/monthly within a challenge.

## Supabase Edge Functions

Located in `supabase/functions/`. Currently: `admin-actions` (Deno/TypeScript). Deploy via Supabase CLI.
