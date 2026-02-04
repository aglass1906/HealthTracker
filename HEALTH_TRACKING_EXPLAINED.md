# How Health Tracking Works

This document explains in plain English how the HealthTracker app integrates with Apple Health and handles user data.

### 1. The "Handshake" (Permission)
When you first open the app, it asks for permission to talk to the **Apple Health** app on your iPhone. We specifically ask for:
*   Steps
*   Flights Climbed
*   Active Energy (Calories)
*   Distance
*   Workouts

### 2. The Daily Check-in (Reading Data)
Every time you open the app (and periodically in the background), our app politely taps Apple Health on the shoulder and asks:
> *"Hey, what are the total numbers for **today** so far?"*

It doesn't track your location or monitor you second-by-second. It just asks for the **totals** (e.g., "5,432 steps today").

### 3. Local Copy (Saving)
Once Apple Health gives us those numbers, we save a copy of them inside the **HealthTracker app** on your phone. This ensures you can see your stats even if you are offline.

### 4. The Cloud Sync (Sharing)
This is the "Family" feature:
Immediately after we get the fresh numbers from Apple, we securely send a copy of **just those daily totals** to our backend (Supabase). This is how your family members can see your score on the leaderboard without needing access to your phone!
