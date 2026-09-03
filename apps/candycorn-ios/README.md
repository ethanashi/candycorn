# Candy Corn for iPhone

This directory contains the Phase 1 native SwiftUI application shell. It uses iOS 26, Swift 6, Observation, and Swift Testing. The Xcode project is generated from `project.yml` and must not be edited or committed.

All content is seeded and fictional. Recording, camera capture, AI processing, export, and persistence are simulated. The app does not request permissions, access a device sensor, send a network request, create an export, or persist a change.

## Generate, build, and test

Run these commands from `apps/candycorn-ios`:

```sh
/opt/homebrew/bin/xcodegen generate
xcodebuild -project CandyCorn.xcodeproj -scheme CandyCorn -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/candycorn-ios-derived-data CODE_SIGNING_ALLOWED=NO build
xcodebuild -project CandyCorn.xcodeproj -scheme CandyCorn -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/candycorn-ios-derived-data CODE_SIGNING_ALLOWED=NO test
```

The app supports iPhone portrait orientation. Code signing, device installation, deployment, and App Store work are outside this phase.

## Routes

Pass `-screen <route>` at launch to open one screen deterministically. A missing, incomplete, or unknown route starts the welcome flow.

| Screen | Route | Screenshot |
| --- | --- | --- |
| Welcome | `/welcome` | `01-welcome.png` |
| Today | `/today` | `02-today.png` |
| Quick mood check-in | `/check-in` | `03-check-in.png` |
| Capture choice | `/capture` | `04-capture.png` |
| Voice journal | `/journal/voice` | `05-voice-rant.png` |
| Text journal | `/journal/write` | `06-text-journal.png` |
| Photograph a page | `/journal/photo` | `07-journal-photo.png` |
| Journal detail | `/journal/entry/football-and-guilt` | `08-journal-detail.png` |
| Journal suggestions | `/journal/suggestions` | `09-ai-suggestions.png` |
| Goals | `/goals` | `10-goals.png` |
| Bring up next time | `/bring-up` | `11-bring-up.png` |
| Appointments | `/appointments` | `12-appointments.png` |
| Record appointment | `/appointments/record` | `13-record-appointment.png` |
| Active appointment | `/appointments/active` | `14-active-appointment.png` |
| Therapy session | `/sessions/therapy-sep-2` | `15-therapy-session.png` |
| TMS pre-session | `/tms/pre-session` | `16-tms-pre.png` |
| TMS post-session | `/tms/post-session` | `17-tms-post.png` |
| Prepare for therapy | `/prepare/therapy` | `18-prepare-therapy.png` |
| Prepare for TMS | `/prepare/tms` | `19-prepare-tms.png` |
| History | `/history` | `20-history.png` |
| Search and memory | `/search` | `21-search.png` |
| Privacy settings | `/settings/privacy` | `22-settings-privacy.png` |
| AI and processing settings | `/settings/ai` | `23-settings-ai.png` |
| Data and export settings | `/settings/data` | `24-settings-data.png` |

The active appointment route prepares consent and a simulated running timer only when launched with that screenshot argument. Normal access without consent shows the recording guard.

## Capture simulator screenshots

Use the installed iPhone 17 simulator running iOS 26.5. After a successful build:

```sh
open -a Simulator
xcrun simctl boot 'iPhone 17'
xcrun simctl bootstatus booted -b
xcrun simctl install booted /tmp/candycorn-ios-derived-data/Build/Products/Debug-iphonesimulator/CandyCorn.app
mkdir -p screenshots
```

Launch and capture one route at a time:

```sh
xcrun simctl launch --terminate-running-process booted dev.candycorn.app -screen /today
sleep 1
xcrun simctl io booted screenshot screenshots/02-today.png
```

Repeat with every route and filename in the table. These files must come from the native simulator. The approved references are in `../candycorn-prototype/screenshots/`, with the strongest visual pins in `../candycorn-prototype/design/sheet/`.

For accessibility checks, set an accessibility content size in the simulator and inspect Today, Goals, Therapy session, Prepare for therapy, and AI settings. Copy and controls must remain readable, scrollable, and reachable.

## Navigation and simulated state

The app uses five retained `NavigationStack` instances and a custom floating bar for Today, Journal, Prepare, History, and Settings. Capture and recording routes are full-screen flows. Switching tabs preserves each tab path. State changes live only in memory and reset on relaunch.

## Future device contracts

These contracts guide later native adapters. None are implemented in Phase 1.

| Capability | Later contract | Phase 1 behavior |
| --- | --- | --- |
| Microphone and recording | Explain why access is needed, request consent at the action boundary, honor participant acknowledgement, handle interruptions and route changes, define background behavior, preserve the immutable source audio, and validate on a real device. | Simulated timer and waveform only. No permission request or audio session. |
| Camera | Request permission only when capture begins, handle denial and cancellation, preserve the immutable source photo beside extracted text, and validate focus, rotation, and memory use on a real device. | Static journal-page fixture only. No camera access. |
| Local vault | Encrypt originals and derived artifacts at rest, keep vault keys in Keychain, preserve provenance and source identifiers, and test recovery and migration. | Fresh in-memory seeded state on every launch. No database or Keychain access. |
| Cloud AI | Show what will leave the device, require an enabled mode and provider, minimize selected content, record provider and model provenance, preserve originals, and make failure safe and retryable. | Choice controls and deterministic suggestions only. No model or network call. |
| Export | Build a user-requested archive, show its contents before sharing, protect temporary files, and clean them up after the share flow. | Preview text only. No file is created. |
| Real-device proof | Validate permission prompts, interruptions, background transitions, thermal and memory behavior, accessibility, and source preservation on supported iPhones. | Simulator build, tests, and renders only. |

The protocol boundaries for recording, photo capture, processing, and export are declared in `CandyCorn/App/Capabilities.swift` so later device adapters can be added without changing product views.
