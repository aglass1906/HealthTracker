# Info.plist Configuration for Background Refresh

Since modern iOS projects use Xcode's build settings instead of a traditional Info.plist file, you need to configure these settings manually in Xcode.

## Steps to Enable Background Modes

### 1. Open Project in Xcode

1. Open `HealthTracker.xcodeproj` in Xcode
2. Select the **HealthTracker** target in the left sidebar
3. Go to the **Signing & Capabilities** tab

### 2. Add Background Modes Capability

1. Click the **+ Capability** button
2. Search for and add **Background Modes**
3. In the Background Modes section, check:
  - ✅ **Background fetch**
  - ✅ **Background processing**

### 3. Register Background Task Identifier

1. Still in the project target settings
2. Go to the **Info** tab
3. Find or add a new key: `BGTaskSchedulerPermittedIdentifiers`
4. Set it as an Array type
5. Add one item to the array:
  - Value: `com.healthtracker.refresh`

## Visual Guide

```
Xcode Project Navigator
└── HealthTracker (target)
    └── Signing & Capabilities
        └── + Capability
            └── Background Modes
                ├── ☑ Background fetch
                └── ☑ Background processing

Xcode Project Navigator
└── HealthTracker (target)
    └── Info
        └── BGTaskSchedulerPermittedIdentifiers (Array)
            └── Item 0: "com.healthtracker.refresh"
```

## What These Settings Do

**Background fetch**: Allows iOS to wake your app periodically to sync data

**Background processing**: Allows longer-running tasks when conditions are met

**BGTaskSchedulerPermittedIdentifiers**: Whitelist of task identifiers your app can schedule

---

## Verification

After making these changes:

1. Build and run the app
2. Check the console for: `✅ Background tasks registered`
3. Put the app in background
4. Check console for: `✅ Background refresh scheduled for ~4 hours from now`

## Testing Background Refresh

In Xcode, you can manually trigger a background refresh:

1. Run the app on a device or simulator
2. Put the app in background (swipe up)
3. In Xcode, click **Debug** menu
4. Select **Simulate Background Fetch**
5. Check console for: `🔄 Background refresh started`

---

## Alternative: Using scheme arguments

If you want to test background tasks during development:

1. Edit the scheme (Product → Scheme → Edit Scheme)
2. Go to Run → Arguments
3. Add launch argument: `-BGTaskSchedulerSimulatedLaunchAtDate <timestamp>`

This will test background task execution at app launch.