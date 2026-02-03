# HealthTracker Setup Instructions

## HealthKit Configuration

To enable HealthKit in your Xcode project, follow these steps:

1. **Open the project in Xcode**
   - Open `HealthTracker.xcodeproj` in Xcode

2. **Enable HealthKit Capability**
   - Select the project in the navigator
   - Select the "HealthTracker" target
   - Go to the "Signing & Capabilities" tab
   - Click the "+ Capability" button
   - Search for and add "HealthKit"
   - This will automatically configure the necessary entitlements

3. **Build and Run**
   - The app will request HealthKit permissions on first launch
   - Grant permissions in the authorization screen
   - The app will automatically start syncing health data

## Features

✅ **Automatic Health Data Logging**
- Steps and Flights Climbed
- Active Calories
- Activity Rings (Move, Exercise, Stand)
- Workouts

✅ **Data Persistence**
- All data is saved locally and persists between app launches
- Data is automatically refreshed when the app opens

✅ **Views**
- **Dashboard**: Today's overview with activity rings and stats
- **All Data**: Complete list of all logged daily data
- **Summary**: Time range summaries (Week/Month/Custom) with charts
- **Profile**: HealthKit authorization status

✅ **Charts**
- Curvy line charts using Swift Charts
- Shows Steps, Flights, and Calories over time
- Smooth interpolation for beautiful visualizations

## Requirements

- iOS 17.0+ (for Swift Charts)
- Xcode 15.0+
- Physical device or simulator with HealthKit support
- HealthKit capability enabled in Xcode

## Notes

- HealthKit requires a physical device or a simulator that supports HealthKit
- The app requests read-only access to health data
- Activity rings are calculated based on active energy, exercise minutes, and stand hours
- Data is cached locally for offline access

