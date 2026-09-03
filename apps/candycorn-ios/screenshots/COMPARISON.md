# Phase 1 native acceptance comparison

Status: Captured on the host on September 2, 2026 after the simulator service was restored. The 24 PNGs in this directory are real iPhone 17 Pro (iOS 26.5) captures via `-screen <route>`. The full Swift Testing suite (10 suites) passed on the iPhone 17 simulator. The blocked table below is the worker's original record; the operator review that supersedes it is in the commit message and docs/PHASES.md Phase 2.

XcodeGen completed successfully with XcodeGen 2.46.0. Xcode 26.6 can compile the app and the complete Swift Testing bundle for the generic arm64 iOS Simulator destination when the Swift macro sandbox is disabled for this restricted runner. The required named iPhone 17 build and test commands cannot select a destination because CoreSimulatorService is disconnected and reports no available simulator devices or runtimes.

No PNG is present in this directory. Browser screenshots were not copied or resized. Visual results remain unevaluated until a real iPhone 17 simulator capture exists for every route.

| Screen | Route | Reference used | Result | Accepted native deviation |
| --- | --- | --- | --- | --- |
| 01 Welcome | `/welcome` | `candycorn-prototype/screenshots/01-welcome.png` | Blocked, no native capture | None evaluated |
| 02 Today | `/today` | `candycorn-prototype/screenshots/02-today.png`, `design/sheet/today.png` | Blocked, no native capture | None evaluated |
| 03 Quick mood check-in | `/check-in` | `candycorn-prototype/screenshots/03-check-in.png` | Blocked, no native capture | None evaluated |
| 04 Capture choice | `/capture` | `candycorn-prototype/screenshots/04-capture.png` | Blocked, no native capture | None evaluated |
| 05 Voice journal | `/journal/voice` | `candycorn-prototype/screenshots/05-voice-rant.png`, `design/sheet/talk-recording.png` | Blocked, no native capture | None evaluated |
| 06 Text journal | `/journal/write` | `candycorn-prototype/screenshots/06-text-journal.png` | Blocked, no native capture | None evaluated |
| 07 Photograph a page | `/journal/photo` | `candycorn-prototype/screenshots/07-journal-photo.png` | Blocked, no native capture | None evaluated |
| 08 Journal detail | `/journal/entry/football-and-guilt` | `candycorn-prototype/screenshots/08-journal-detail.png`, `design/sheet/journal-result.png` | Blocked, no native capture | None evaluated |
| 09 Journal suggestions | `/journal/suggestions` | `candycorn-prototype/screenshots/09-ai-suggestions.png` | Blocked, no native capture | None evaluated |
| 10 Goals | `/goals` | `candycorn-prototype/screenshots/10-goals.png`, `design/sheet/goals.png` | Blocked, no native capture | None evaluated |
| 11 Bring up next time | `/bring-up` | `candycorn-prototype/screenshots/11-bring-up.png` | Blocked, no native capture | None evaluated |
| 12 Appointments | `/appointments` | `candycorn-prototype/screenshots/12-appointments.png` | Blocked, no native capture | None evaluated |
| 13 Record appointment | `/appointments/record` | `candycorn-prototype/screenshots/13-record-appointment.png` | Blocked, no native capture | None evaluated |
| 14 Active appointment | `/appointments/active` | `candycorn-prototype/screenshots/14-active-appointment.png` | Blocked, no native capture | Expected native state is the seeded active simulated recorder, not the stale prototype deep-link guard |
| 15 Therapy session | `/sessions/therapy-sep-2` | `candycorn-prototype/screenshots/15-therapy-session.png`, `design/sheet/session-detail.png` | Blocked, no native capture | None evaluated |
| 16 TMS pre-session | `/tms/pre-session` | `candycorn-prototype/screenshots/16-tms-pre.png` | Blocked, no native capture | None evaluated |
| 17 TMS post-session | `/tms/post-session` | `candycorn-prototype/screenshots/17-tms-post.png` | Blocked, no native capture | None evaluated |
| 18 Prepare for therapy | `/prepare/therapy` | `candycorn-prototype/screenshots/18-prepare-therapy.png`, `design/sheet/prepare-brief.png` | Blocked, no native capture | None evaluated |
| 19 Prepare for TMS | `/prepare/tms` | `candycorn-prototype/screenshots/19-prepare-tms.png` | Blocked, no native capture | None evaluated |
| 20 History | `/history` | `candycorn-prototype/screenshots/20-history.png` | Blocked, no native capture | None evaluated |
| 21 Search and memory | `/search` | `candycorn-prototype/screenshots/21-search.png` | Blocked, no native capture | None evaluated |
| 22 Privacy settings | `/settings/privacy` | `candycorn-prototype/screenshots/22-settings-privacy.png` | Blocked, no native capture | None evaluated |
| 23 AI and processing settings | `/settings/ai` | `candycorn-prototype/screenshots/23-settings-ai.png` | Blocked, no native capture | None evaluated |
| 24 Data and export settings | `/settings/data` | `candycorn-prototype/screenshots/24-settings-data.png` | Blocked, no native capture | None evaluated |

## Verification record

- Project generation: Passed.
- Required iPhone 17 build: Blocked before compilation, exit 70, no matching simulator destination.
- Required iPhone 17 test: Blocked before execution, exit 70, no matching simulator destination.
- Generic arm64 iOS Simulator app build: Passed with `OTHER_SWIFT_FLAGS='-Xfrontend -disable-sandbox'`; this confirms the source compiles but does not replace the named build gate.
- Generic arm64 iOS Simulator test bundle build: Passed with the same runner-only flag; tests compiled but did not execute.
- Native route screenshots: Blocked, 0 of 24 captured.
- Per-screen visual comparison: Blocked, 0 of 24 evaluated.
- Accessibility content-size inspection: Blocked, no simulator.
- Reduce Motion waveform inspection: Blocked, no simulator.
- Device-contract static audit: Passed. The built app links Foundation, CoreGraphics, SwiftUI, and UIKit only. No AVFoundation, Photos, networking, database, Keychain, analytics, export implementation, or background-audio entitlement is present. Permission purpose strings exist for later phases, but Phase 1 code does not request either permission.
- Repository hygiene: Passed for tracked files. No generated project, DerivedData, build output, xcuserdata, `.build`, `.pnpm-store`, secrets, or app logs are tracked.

Blocking evidence from `xcrun simctl list devices available`: `Unable to locate device set`, caused by `CoreSimulatorService connection became invalid` and `simdiskimaged crashed or is not responding`.

Rerun the README build, test, and screenshot commands on a host where CoreSimulatorService exposes the documented iPhone 17 with iOS 26.5. Replace every blocked row only after inspecting its real native PNG.
