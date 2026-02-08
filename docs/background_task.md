# Background Refresh & Social Sync Explained

This document explains how HealthTracker keeps data in sync between your devices (Apple Watch, iPhone), the local app, and the Supabase backend, as well as how social feed events are generated.

## High-Level Data Flow

```mermaid
graph TD
    A[Apple Watch] -->|Syncs via iCloud/BT| B[iPhone HealthKit]
    B -->|Background Delivery Trigger| C[HealthTracker App (Background)]
    C -->|Fetch & Aggregate| D[Local DailyHealthData]
    D -->|Upsert Sync| E[Supabase DB: daily_stats]
    D -->|Check Goals & Achievements| F[SocialFeedManager]
    F -->|Insert Event| G[Supabase DB: social_events]
    G -->|Query / Subscription| H[Others' Feed]
```

## Detailed Process

### 1. The Trigger: HealthKit Background Delivery
- **Source**: Your **Apple Watch** records a workout or steps. It syncs this data to your **iPhone's HealthKit** database (managed by iOS).
- **Wake Up**: The `HealthKitManager` in our app has registered **Observer Queries** for specific data types:
  - **Workouts**: Set to `.immediate` (tries to wake app as soon as workout ends).
  - **Steps/Calories/etc**: Set to `.hourly` (iOS creates a batch update to save battery).
- **Debounce**: When iOS wakes our app, it might fire multiple signals at once (e.g., one for steps, one for calories). Our `BackgroundTaskManager` waits **2 seconds** to collect these signals and then runs a **single** sync operation.

### 2. The Fetch: Getting Fresh Data
Once the sync starts, the app asks HealthKit for the latest totals for **Today**:
- **Steps, Calories, Flights, Distance**: Cumulative totals for the day.
- **Rings**: Active Energy, Exercise Minutes, Stand Hours.
- **Workouts**: A list of workouts completed today.

> [!NOTE] 
> The app trusts HealthKit as the "source of truth" for the device.

### 3. The Sync: Updating Supabase
The gathered data is bundled into a `DailyHealthData` object and sent to Supabase:
- **Table**: `daily_stats`
- **Operation**: `UPSERT` (Insert or Update).
- **Key**: Matches on `(user_id, date)`.
- **Result**: If an entry exists for today, it is *overwritten* with the new, higher numbers. If not, a new row is created.

### 4. Social Feed Events: "How do others see it?"
After the data sync, the app checks if any **Social Events** should be posted. This happens in `SocialFeedManager`.

#### A. Goal Achievements
The app checks if you've crossed specific thresholds (e.g., 10,000 steps).
- **Logic**: `if steps >= 10000 && !posted_today`
- **Storage**: If true, it inserts a record into the `social_events` table.
- **Debounce**: It saves a flag in `UserDefaults` (e.g., `posted_goal_Steps_2026-02-08`) so it doesn't post the same achievement twice in one day.

#### B. Workout Completion
If a new workout is detected:
- **Logic**: Checks if this specific workout (ID/Time) has been posted.
- **Storage**: Inserts a `workout_finished` event into `social_events`.
- **Debounce**: Saves a flag using the workout's timestamp (e.g., `posted_workout_1745829300_Running`).

### 5. Viewing the Feed
When other users open the **Social Feed**:
1. Their app queries the `social_events` table (joined with user profiles).
2. They see your "Goal Met" or "Workout Finished" events in chronological order.
3. Because the events are just rows in a database table, they persist even if your app goes back to sleep.

## 6. Does this work without opening the app?
**Yes**, but with some important conditions:

1.  **Phone Must Be Unlocked (Sometimes)**
    - HealthKit data is encrypted with your passcode.
    - If your phone is **locked** when the background sync triggers (e.g., in your pocket), the app might wake up but fail to *read* the new data.
    - **Fail-Safe**: The app handles this gracefully (it just logs the error) and skips the update. It does not crash.
    - The sync will retry or succeed the next time you unlock your phone.
    
2.  **Don't Force Quit**
    - **Effect**: Syncing **STOPS** completely.
    - If you double-swipe up to "kill" the app, strict iOS rules prevent any background activity. 
    - **Recovery**: You must open the app again to restart the background process. It will not restart on its own.
    - **Stability**: It does **NOT** crash. It simply ceases to run.

3.  **Internet Required**
    - The app needs a data connection to send updates to Supabase.
