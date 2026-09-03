# Phase 2 native acceptance comparison

Status on September 3, 2026: Blocked before native build, test execution, simulator interaction, and capture. The 24 PNGs in this directory are retained real Phase 1 iPhone 17 Pro captures from September 2. They were not presented as Phase 2 evidence and were not modified.

## Environment and gates

| Gate | Result |
| --- | --- |
| XcodeGen | Passed with 2.46.0 |
| Xcode | 26.6, build 17F113 |
| Simulator runtime | Not enumerable. CoreSimulatorService is disconnected and simdiskimaged is not registered. |
| Required iPhone 17 build | Blocked, exit 74 before source compilation |
| Required iPhone 17 test | Blocked, exit 74 before test execution |
| Swift Testing inventory | 108 declared tests in 23 suites, 0 executed in this pass |
| SQLCipher | The project resolves `sqlcipher/GRDB.swift` 7.11.1 and `SQLCipher.swift` 4.18.0 and has runtime cipher and wrong-key tests. Runtime encryption is unverified because the package graph and tests did not run. No fallback build was used. |
| New Phase 2 captures | 0 of 24 |
| Retained valid captures | 24 of 24, all Phase 1 |

The exact build and test commands both reported:

```text
CoreSimulatorService connection became invalid. Simulator services will no longer be available.
Unable to discover any Simulator runtimes.
xcodebuild: error: Could not resolve package dependencies:
You don’t have permission to save the file “ManifestLoading” in the folder “manifests”.
```

`xcrun simctl list devices available` additionally reported `Unable to locate device set` and `simdiskimaged crashed or is not responding`. The bundled Simulator executable aborted with exit 134, and launchd reported that neither CoreSimulatorService nor simdiskimaged was registered for this user session.

The retained images were opened as a contact sheet beside the 24 prototype references. The observations below describe only that Phase 1 baseline. Every Phase 2 status remains blocked until the route is freshly rendered from the integrated app.

## Route comparison

| Screen and route | Reference | Observed retained baseline | Remaining Phase 2 proof | Status |
| --- | --- | --- | --- | --- |
| 01 Welcome, `/welcome` | `candycorn-prototype/screenshots/01-welcome.png` | Native kernel, progress rule, headline, and anchored Continue action follow the reference composition. | Fresh safe-area and large-text render required. | Blocked |
| 02 Today, `/today` | `candycorn-prototype/screenshots/02-today.png`, `design/sheet/today.png` | Mood object, capture actions, and appointment appear, but the retained image has the old empty region and lacks the required visible Bring up rows. | Confirm flat-ended mood bands, cocoa See goals link, Bring up rows, Current goal, and no first-viewport void over 40 points. | Blocked |
| 03 Check-in, `/check-in` | `candycorn-prototype/screenshots/03-check-in.png` | The three values and optional note follow the reference order. The retained object has the old enclosing treatment and no visible 44-point minus and plus controls. | Tap-position, drag scrubbing, live numerals, end controls, exact-once save, and persistence require interaction proof. | Blocked |
| 04 Capture choice, `/capture` | `candycorn-prototype/screenshots/04-capture.png` | The retained action list and single Close control match the route job. | Confirm product-only copy, 44-point rows, and full-screen dismissal in the integrated build. | Blocked |
| 05 Voice journal, `/journal/voice` | `candycorn-prototype/screenshots/05-voice-rant.png`, `design/sheet/talk-recording.png` | Timer, waveform, and centered Stop action follow the pinned recorder skeleton. The retained image says `Simulated recording` and says no microphone is used. | Replace that stale proof with deterministic fake-media copy that says the source is saved on this device, then prove real metering and playback in normal mode. | Blocked |
| 06 Text journal, `/journal/write` | `candycorn-prototype/screenshots/06-text-journal.png` | The retained open editor, Cancel, and Save original actions align with the reference. | Confirm create, edit, delete, duplicate-save prevention, and relaunch persistence. | Blocked |
| 07 Photograph a page, `/journal/photo` | `candycorn-prototype/screenshots/07-journal-photo.png` | The retained page frame and full-width capture action match the visual skeleton. It explicitly says the camera is not used. | Fresh screenshot copy and normal-mode permission, cancellation, immutable JPEG, and detail-display proof required. | Blocked |
| 08 Journal detail, `/journal/entry/football-and-guilt` | `candycorn-prototype/screenshots/08-journal-detail.png`, `design/sheet/journal-result.png` | Original, cleaned, and summary structure plus provenance are present. The retained image shows the old duplicate back treatment. | Confirm one back control, immutable source separation, attachment playback, edit, delete, and no shell copy. | Blocked |
| 09 Suggestions, `/journal/suggestions` | `candycorn-prototype/screenshots/09-ai-suggestions.png` | The retained warm suggestion field and Add to next appointment actions align with the reference. | Confirm all Add actions persist and no AI artifact is created in Phase 2. | Blocked |
| 10 Goals, `/goals` | `candycorn-prototype/screenshots/10-goals.png`, `design/sheet/goals.png` | Cadence groups and provenance rows match the reference hierarchy. The retained capture shows the blurred circular back affordance reported on device. | Confirm no floating blurred back, direct root has no back, pushed access has one back, and goal lifecycle persists. | Blocked |
| 11 Bring up, `/bring-up` | `candycorn-prototype/screenshots/11-bring-up.png` | Retained rows preserve conversation-specific copy, provenance, Discussed, and Dismiss actions. | Confirm create from other screens, discuss, dismiss, and relaunch persistence. | Blocked |
| 12 Appointments, `/appointments` | `candycorn-prototype/screenshots/12-appointments.png` | Upcoming and completed visits with route actions align with the reference. | Confirm single pushed back behavior and persisted appointment updates. | Blocked |
| 13 Record appointment, `/appointments/record` | `candycorn-prototype/screenshots/13-record-appointment.png` | Visit-type choice, consent card, and disabled start state match the reference. Retained footer uses old simulation copy. | Confirm permission only after Start, 44-point consent control, real audio start, and product-only copy. | Blocked |
| 14 Active appointment, `/appointments/active` | `candycorn-prototype/screenshots/14-active-appointment.png` | The retained route shows the intended active timer and waveform instead of the prototype guard state, but labels the recording simulated. | Confirm deterministic saved-device copy, interruption state, duration checkpoint, and nonterminating navigation. | Blocked |
| 15 Therapy session, `/sessions/therapy-sep-2` | `candycorn-prototype/screenshots/15-therapy-session.png`, `design/sheet/session-detail.png` | Transcript, speaker provenance, playback scrubber, and session metadata match the pin's open-detail structure. The retained capture shows duplicate back affordances. | Confirm one back control, saved audio playback, manual notes, large text, and scroll reachability. | Blocked |
| 16 TMS pre-session, `/tms/pre-session` | `candycorn-prototype/screenshots/16-tms-pre.png` | Mood bands, distress control, note field, and provider action follow the reference. | Confirm 1 through 10 interaction, 44-point controls, provenance contrast, and saved check-in. | Blocked |
| 17 TMS post-session, `/tms/post-session` | `candycorn-prototype/screenshots/17-tms-post.png` | Mood bands, distress control, provider notes, and next-session field follow the reference. | Confirm input reachability, persistence, and one pushed back control. | Blocked |
| 18 Prepare therapy, `/prepare/therapy` | `candycorn-prototype/screenshots/18-prepare-therapy.png`, `design/sheet/prepare-brief.png` | The retained brief uses the pinned open-prose sections and anchored edit action. | Confirm one back control, source provenance, large-text scrolling, and edit persistence. | Blocked |
| 19 Prepare TMS, `/prepare/tms` | `candycorn-prototype/screenshots/19-prepare-tms.png` | The retained before-and-after narrative and compact mood object match the reference job. | Confirm no clipping, cocoa secondary copy, provenance weight, and pushed back behavior. | Blocked |
| 20 History, `/history` | `candycorn-prototype/screenshots/20-history.png` | Filters, dated timeline, event colors, and compact mood data align with the reference. | Confirm vault-backed ordering, filter results, destinations, empty state, and relaunch persistence. | Blocked |
| 21 Search, `/search` | `candycorn-prototype/screenshots/21-search.png` | Search field and local-memory result card follow the reference. | Confirm FTS5, bounded LIKE fallback, stale-query suppression, and no-results state. | Blocked |
| 22 Privacy settings, `/settings/privacy` | `candycorn-prototype/screenshots/22-settings-privacy.png` | Retained screen shows the three-section composition and privacy roles, but includes old shell wording. | Confirm Privacy is selected on deep link, section taps switch in place, content is product-only, and no push animation occurs. | Blocked |
| 23 AI settings, `/settings/ai` | `candycorn-prototype/screenshots/23-settings-ai.png` | Retained picker, processing status, and local-choice layout follow the reference. It includes old shell wording. | Confirm AI is selected on deep link, no network request, large-text reachability, and no stack mutation. | Blocked |
| 24 Data settings, `/settings/data` | `candycorn-prototype/screenshots/24-settings-data.png` | Retained retention choices match the reference, but export and reset are Phase 1 preview controls. | Confirm Data is selected, sample toggle, live export and cleanup states, typed deletion, empty relaunch, and in-place section switching. | Blocked |

## Required interaction results

- Shell repairs: Source tests are present for route ownership, deep-link section selection, in-place Settings switching, every back behavior family, mood position math, Today ordering, contrast, and banned product copy. None executed in this pass, and no integrated render was available.
- Today first viewport: Not verified. The retained Phase 1 Today image still shows the old dead zone and cannot evidence the new Bring up and Current goal order.
- Contrast and typography: Not verified by a new render. Static test declarations cover the approved colors and contrast ratios, but the suite did not execute.
- Large text and Reduce Motion: Not inspected because no simulator device set could be opened.
- Persistence: Not exercised. Text journal, mood, goal, talking point, sample removal, sample restoration, and relaunch behavior remain unverified in this pass.
- Recording and playback: Not exercised. The retained recorder screenshots contain stale simulation language and are not accepted as Phase 2 captures.
- Export and Delete everything: Not exercised because the app could not launch.
- Camera: Not exercised. Real capture remains a device-contract item even when the simulator lacks camera hardware.

## Source acceptance defect

The production runtime creates `AVRecordingService` with `NoOpRecordingCheckpointSink` in `CandyCorn/App/RuntimeBootstrap.swift`. The adapter's test seam proves 15-second callbacks, but the production graph does not persist them through `CareStore.saveAppointment`. Appointment checkpoint recovery therefore does not meet the Phase 2 contract and must return to the media or runtime implementation owner before final acceptance.

## Repository hygiene

Tracked status was clean before this acceptance pass. The generated `CandyCorn.xcodeproj` is ignored and must be removed after verification. No DerivedData, database, attachment, recording, temporary export, Keychain material, or secret was written inside `apps/candycorn-ios`.

The strict ignored-artifact check is not clean at repository scope: `.pnpm-store/`, `node_modules/`, `apps/candycorn-prototype/node_modules/`, and `apps/candycorn-prototype/dist/` already exist as ignored directories. They were not created, changed, or removed by this acceptance task.

## Rerun requirement

Run the exact README generation, named build, and named test commands in a macOS user session where CoreSimulatorService and simdiskimaged are registered and SwiftPM can write its manifest cache. Fix the production appointment checkpoint sink first. Then replace all 24 PNGs from `simctl io`, perform the normal-mode persistence and media checks, inspect the five required large-text routes plus Reduce Motion, and replace every Blocked result with direct evidence.
