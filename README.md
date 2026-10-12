# PickleMyBalls Watch

A standalone SwiftUI Apple Watch app for traditional pickleball scoring and an app-managed HealthKit workout. No iPhone app, account, network calls, backend, or third-party dependencies. Requires watchOS 10 or later and Xcode 16 or later (Xcode 26 recommended).

**Find the project**

Download this repository from GitHub using **Code → Download ZIP**, unzip it, and open **PickleMyBallsWatch.xcodeproj** inside the extracted folder. If you cloned it earlier, pull the latest changes first. Use this included project in Xcode.

**Run on a simulator**

1. Open `PickleMyBallsWatch.xcodeproj` in Xcode, select the **PickleMyBalls Watch** scheme, and install a watchOS simulator runtime in Xcode Settings → Components if needed.
2. Select an Apple Watch simulator and run. Scoring works without Health access. Use the gear button to edit names or choose singles/doubles and the opening side when starting a new game.
3. Use **Workout → Start pickleball** to request Health permissions. Simulator sensor data and Activity credit do not represent a physical Watch.

An unsigned simulator build can also be checked from the repository root:

```sh
xcodebuild -project PickleMyBallsWatch.xcodeproj -scheme "PickleMyBalls Watch" \
  -sdk watchsimulator -destination 'generic/platform=watchOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

**Run on a Watch**

Select a unique bundle identifier and your signing team in the **PickleMyBalls Watch** target's Signing & Capabilities pane. The project includes **HealthKit** and **Background Modes → Workout processing**. Use a team/provisioning profile that supports HealthKit. Enable Developer Mode on your paired Apple Watch, select it as the destination in Xcode, and run. Apple's device signing and distribution rules apply; the app uses no paid runtime services.

Start the workout while this app is open. Allow workout/active-energy writing and heart-rate/active-energy reading for full fitness integration. Workouts remain active when the wrist lowers, while navigating, and across game resets. **End & save workout** is a separate confirmed action. Saved workouts sync through Apple Health and appear in Fitness; Activity credit is determined by watchOS sensor measurements and permissions, and is not guaranteed for every elapsed minute. Denied permissions never disable scoring. A missing or stale heart-rate reading displays `— bpm`.

**Scoring decisions**

- Singles has one server; losing a rally causes a side-out. Serve from the right at an even score and the left at an odd score.
- Doubles calls the serving score, receiving score, then service number. The opening side starts at **0–0–2** and has only one server. Following side-outs start at server 1; the next lost rally passes service to their teammate (server 2); another loss causes a side-out.
- Player 1 begins on the right and Player 2 on the left for each team. Only the serving team changes courts after scoring. Each subsequent side-out starts with whoever currently occupies the right court. **Server 1/2 describes the service turn, not a fixed player identity.**
- A game ends at 11 or more with a lead of at least two; there is no cap. Undo restores all rally state, including a winning rally, without undoing name edits. Reset clears points, player positions, and undo history, preserves names, and leaves the workout alone.
- Every rally, undo, name edit, and reset saves an atomic, versioned local JSON file in the Watch app's Application Support directory. Undo history also survives relaunch. Corrupt/unsupported saves are preserved; a confirmed new game archives the unreadable file before replacing it. Saving errors are shown with a retry option.

**Workout APIs and constraints**

The app uses `HKWorkoutConfiguration.activityType = .pickleball`, `HKWorkoutSession(healthStore:configuration:)`, `associatedWorkoutBuilder()`, and `HKLiveWorkoutDataSource`. These APIs exist at the watchOS 10 deployment target; pickleball dates to watchOS 7. It requests only workout and active-energy write access, plus heart-rate and active-energy read access. It uses the live builder to collect sensor data and workout events; duration excludes paused time. After the session's ended delegate event, it calls `endCollection(at:)` followed by `finishWorkout`, treating a nil workout with no error as the documented successful locked-device save.

Only one **primary workout session** can run on the Watch. End a workout in Apple's Workout app (or another app) before starting one here; starting another app's workout can interrupt this app's session. This app cannot control, attach to, or promise to run a second tracking session alongside Apple's Workout app. Scoring can still be used while another app tracks exercise, but live metrics here belong only to this app's own workout. `recoverActiveWorkoutSession` and `handleActiveWorkoutRecovery` reattach this app's session after a system recovery; they do not recover another app's workout. Force-quitting or rebooting can prevent recovery; an in-memory unsaved builder cannot be guaranteed to survive those actions.

API names, availability, session-error meanings, pause-aware duration, recovery, and collection/save ordering were checked against **Apple-authored Xcode 26.0 SDK headers** available from a public SDK mirror:

- [HKWorkoutSession.h](https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS26.0.sdk/System/Library/Frameworks/HealthKit.framework/Headers/HKWorkoutSession.h)
- [HKWorkout.h](https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS26.0.sdk/System/Library/Frameworks/HealthKit.framework/Headers/HKWorkout.h)
- [HKWorkoutBuilder.h](https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS26.0.sdk/System/Library/Frameworks/HealthKit.framework/Headers/HKWorkoutBuilder.h)
- [HKHealthStore.h](https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS26.0.sdk/System/Library/Frameworks/HealthKit.framework/Headers/HKHealthStore.h)
- [HKDefines.h](https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS26.0.sdk/System/Library/Frameworks/HealthKit.framework/Headers/HKDefines.h)

Apple's live documentation host was blocked in the build environment. The official references for Mac-side follow-up are [HKWorkoutSession](https://developer.apple.com/documentation/healthkit/hkworkoutsession), [HKLiveWorkoutBuilder](https://developer.apple.com/documentation/healthkit/hkliveworkoutbuilder), and [running workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions). The SDK files are verification references, not bundled dependencies.

**Tests and remaining device checks**

Run `swift test` or `Scripts/check.sh` with Swift 6 or later. The package compiles the exact scoring, persistence, and workout-coordinator sources used by the Watch app. It tests first service, both doubles servers, real player court positions, singles parity, win-by-two beyond 11, game-over/undo, names/reset, 1,000 randomized rally/undo/serialization steps, file restoration/corruption/write failures, and workout authorization, recovery, pause/resume, startup races, interruptions, end/save ordering, retry, and reset independence. Workout tests use a fake client; they do not prove HealthKit behavior.

Validated in this cloud workspace with Swift 6.2: **28 tests across three suites passed**. Swift syntax and the Xcode project references, shared scheme, property lists, entitlements, and assets also passed structural checks. Apple-platform UI observation is conditionally compiled; Linux exercises the same coordinator logic without the Observation UI instrumentation.

The Linux build environment cannot run Xcode or an Apple Watch simulator. On a Mac, run the simulator build above, then check small-screen layout, large text/VoiceOver, name entry, reset cancel/confirm, and relaunch after scoring and undo. On a physical Watch, verify:

- Permission denial still allows scoring; granted permission shows live heart rate after a sensor reading.
- Start, pause, resume, and end/save produce one pickleball workout with pause-aware duration in Health/Fitness.
- Lowering the wrist for several minutes keeps tracking; resetting a game does not stop tracking.
- Opening another workout app reports any interruption; this app's collected workout is saved when HealthKit ends its session.
- Activity rings update according to Apple's measurements. Verify system-triggered recovery if available; simulator tests cannot establish sensor accuracy, background execution, signing, or ring credit.
