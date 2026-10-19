# BE

One calm place for the health data that matters, from an Apple Watch, a Fitbit (through Google Health) and anything else that writes to Apple Health. No accounts: Apple Health is the only data store, and BE's own state (plan, habits, streaks, XP) stays on the iPhone.

## Status (17 October 2026)

First build increment. The core logic is compiled and unit-tested (29 tests, Swift 6.2). **The iOS, widget and watch targets have only been syntax-checked, not compiled**: they were written on Linux without Xcode. Expect a round of compile fixes on first build.

| Area | State |
|---|---|
| `Packages/BECore`: metrics, coach, gamification, streaks, habits, meal validation, plan recommender | Built and tested on Linux |
| iOS app: onboarding, widget Home, metric detail with coach, Snap, Streaks, Plan, Settings | Written, not yet compiled |
| Home Screen and Lock Screen widgets with an interactive water button | Written, not yet compiled |
| Watch app (today view, water logging through the phone) | Written, not yet compiled |
| BE relay (stateless server holding the OpenAI key, App Attest) | **Not built.** The app's client is ready; until it's deployed, photo estimates show a "not set up" message and manual entry works |

## Build

On a Mac with Xcode 26 or later:

```sh
brew install xcodegen
xcodegen generate
open BE.xcodeproj
```

1. In `project.yml`, set `DEVELOPMENT_TEAM` and replace `com.example` and `group.com.example.be` with your own bundle ids and App Group, then run `xcodegen generate` again.
2. HealthKit needs a real iPhone for meaningful data. The Simulator works for UI, using sample data added in its Health app.
3. Core tests: `cd Packages/BECore && swift test`.

## How it works

- **Live sync.** `HealthStore` registers an `HKObserverQuery` for every type BE shows, with background delivery turned on. Changes from the watch, Google Health or other apps refresh just the affected metric (coalesced over 0.5 s), then re-run the game and push a snapshot to the widgets (App Group) and the watch (WatchConnectivity).
- **No double counting.** Daily values use `HKStatisticsCollectionQueryDescriptor`, which merges overlapping Watch and Fitbit samples using the source order set in the Health app. Sleep samples are merged by interval union (`MetricsEngine.mergedDuration`).
- **Coach.** `CoachLibrary` gives every metric a short "what it means" and "what to do", compared with your own 90-day baseline. When Apple Intelligence is available, `CoachService` rewrites the wording on device from aggregated numbers only. Safety messages (`Thresholds`) are never rewritten.
- **Gamification.** XP for plan targets, habits, meal logs and three daily quests. Levels, badges and a streak with rest days and earned freezes. Rules avoid rewarding extremes: calories count only within ±10% of target, and sleep only within a healthy window.
- **Snap.** Photo → resized JPEG with metadata stripped → BE relay → OpenAI vision → `MealValidator` flags doubtful items → you review and edit → saved to Apple Health as a food correlation. Nothing leaves the device without explicit in-app consent (App Review Guideline 5.1.2(i)).

## Check in the Phase 0 spike (unverified assumptions)

- What the Google Health app actually writes to Apple Health for a Fitbit Air, and its source name (`HealthStore.detectedSources` matches "Fitbit" or "Google Health").
- `HKActivitySummary.exerciseTimeGoal` and `standHoursGoal` (used for ring goals).
- Whether `LogWaterIntent` can write to HealthKit from the widget extension. If not, it queues the write and the app flushes it on next launch (already handled).
- Foundation Models availability and output quality on your iPhone.
- iOS 27 adds image input to Foundation Models. Once verified against the shipping SDK, add an on-device meal estimator so photos never leave the phone.

## Not medical advice

The safety thresholds in `Thresholds.swift` are conservative placeholders and need clinical review. Sending meal photos to OpenAI is a cross-border disclosure under the Australian Privacy Principles. Have a privacy professional review the consent text and privacy policy, and get regulatory advice on TGA software-as-a-medical-device rules before release.
