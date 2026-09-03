# Candy Corn for iPhone

Candy Corn is a native, offline-first SwiftUI journal for continuity between mental health visits. Phase 3 adds optional organizer AI through OpenRouter while preserving the local care vault and every immutable source. A cloud request can begin only after the user reviews the exact source and character or image counts in a "What leaves this device" sheet and taps Send. The app remains fully usable with AI off.

The app targets iOS 26 in Swift 6 language mode with Observation and Swift Testing. The Xcode project is generated from `project.yml`. Never edit or commit the generated project.

All bundled sample content is fictional and belongs to Jamie Rivera. Do not use real patient content in screenshots, tests, logs, or commits.

## Generate, build, and test

Run these commands from `apps/candycorn-ios`:

```sh
/opt/homebrew/bin/xcodegen generate
xcodebuild -project CandyCorn.xcodeproj -scheme CandyCorn -scmProvider system -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/candycorn-ios-derived-data CODE_SIGNING_ALLOWED=NO build
xcodebuild -project CandyCorn.xcodeproj -scheme CandyCorn -scmProvider system -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/candycorn-ios-derived-data CODE_SIGNING_ALLOWED=NO test
```

If package resolution hangs during SwiftPM Keychain lookup, follow the SQLCipher artifact-placement procedure in the [host handoff](../../docs/HANDOFF-2026-09-02.md), then rerun the command with `-disableAutomaticPackageResolution` and `-scmProvider system`.

The tests cover vault migrations, SQLCipher availability and wrong-key rejection, repositories, Keychain behavior through test seams, FTS5 and LIKE search, exports, logging privacy, navigation, mood interactions, media state machines, runtime bootstrap, OpenRouter request shape, structured output validation, evidence rejection, retry policy, disclosure counts, immutable AI artifact persistence, and organizer workflows. Provider tests inject fake transports and do not make live network calls.

The app supports iPhone portrait orientation. Simulator builds disable code signing. Device builds require the operator's normal signing setup and must not add secrets to the repository.

## Runtime modes and storage

A normal launch uses the production dependency graph:

- `care.db` is stored below the app's Application Support directory and opened with the SQLCipher-enabled GRDB package.
- A 256-bit vault key is created once and kept in Keychain with this-device-only, after-first-unlock accessibility.
- Audio, images, and documents live below the vault attachment root in separate directories.
- Raw recordings and photos are immutable sources. Derived records remain separate and keep provenance.
- The OpenRouter key is stored in a dedicated, this-device-only Keychain item. It is never stored in UserDefaults, an export, a fixture, or the app bundle.
- Organizer and photo-to-text model identifiers are non-sensitive configuration. The production graph reads them at send time and uses an ephemeral URL session.
- AI mode can be Off, Organizer, or Reflection. Reflection currently performs Organizer operations and states that a reflective conversation is not yet available.
- Event logging accepts event names, durations, and counts only. It does not accept journal text, notes, titles, transcript text, payloads, or content-bearing paths.

The first normal launch seeds the fictional Jamie Rivera thread. In Settings, `Use sample content` removes or restores only fictional rows and sample attachments. User-created records remain. Restoring samples inserts missing fixtures without duplicating them.

Passing `-screen <route>` selects deterministic screenshot mode. That mode uses in-memory seeded data and fake recording, playback, photo, export, language-model, and vision adapters. It does not open the production vault, request permissions, make network calls, or write patient content. Add `-sheet <scenario>` to open a deterministic Phase 3 sheet. A normal launch without `-screen` is required for persistence and native media acceptance.

`Delete everything` requires the exact typed value `DELETE`. A successful deletion removes the database and attachments, rotates the vault key, leaves sample content off, and returns an empty usable vault.

## Routes

Pass `-screen <route>` at launch to open one screen deterministically. A missing, incomplete, or unknown route follows the normal onboarding path.

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

Phase 3 sheet acceptance uses these route and scenario pairs. Each scenario must open its sheet without manual interaction; failure to open is an implementation failure, not a reason to compose or substitute an image.

| Sheet | Route | Scenario | Screenshot |
| --- | --- | --- | --- |
| OpenRouter key | `/settings/ai` | `openrouter-key` | `25-openrouter-key-sheet.png` |
| Journal disclosure | `/journal/entry/football-and-guilt` | `journal-send` | `26-what-leaves-journal.png` |
| Photo disclosure | `/journal/photo` | `photo-send` | `27-what-leaves-photo.png` |
| Session disclosure | `/sessions/therapy-sep-2` | `session-send` | `28-what-leaves-session.png` |
| Appointment brief disclosure | `/prepare/therapy` | `prepare-send` | `29-what-leaves-prepare.png` |

The active appointment screenshot route prepares deterministic consent and recording state. Normal access still requires the user's acknowledgement and microphone authorization.

## Capture native screenshots

Use an iPhone 17 simulator after a successful named build:

```sh
open -a Simulator
xcrun simctl boot 'iPhone 17'
xcrun simctl bootstatus booted -b
xcrun simctl install booted /tmp/candycorn-ios-derived-data/Build/Products/Debug-iphonesimulator/CandyCorn.app
```

Launch and capture one route at a time, using the route and filename table above:

```sh
xcrun simctl launch --terminate-running-process booted dev.candycorn.app -screen /today
sleep 1
xcrun simctl io booted screenshot screenshots/02-today.png
```

For a Phase 3 sheet, include both deterministic arguments:

```sh
xcrun simctl launch --terminate-running-process booted dev.candycorn.app -screen /settings/ai -sheet openrouter-key
sleep 1
xcrun simctl io booted screenshot screenshots/25-openrouter-key-sheet.png
```

Wait for each route to settle before capture. A permission alert means screenshot mode did not initialize and the capture is invalid. Every accepted PNG must come directly from `simctl io`; do not resize a prototype render. Compare against `../candycorn-prototype/screenshots/` and the accepted pins in `../candycorn-prototype/design/sheet/`.

For Phase 3 accessibility acceptance, inspect Journal detail, Suggestions, Therapy session, Prepare for therapy, AI settings, the OpenRouter key sheet, and a disclosure sheet at an accessibility content size. Confirm every item remains reachable by scrolling, text wraps without clipping or overlap, the keyboard does not hide the active Save action, and controls remain at least 44 points. Repeat relevant transitions with Reduce Motion enabled and confirm state remains understandable without pulsing or required travel.

## Normal simulator acceptance

Do not pass `-screen` for these checks. Use only disposable fictional content.

1. Create a text journal, mood log, goal, and talking point. Terminate and relaunch the app, then confirm all four remain.
2. Turn off sample content. Confirm the Jamie Rivera examples disappear and the four user records remain. Turn samples back on twice and confirm no duplication.
3. Record and save a voice journal, play it from the saved screen and journal detail, then record an appointment for more than 15 seconds and confirm its duration survives relaunch.
4. Run a search that crosses journals, goals, and talking points. Confirm a no-results query shows the local empty state.
5. Create an export. Inspect its Markdown entries, `index.json`, and copied attachments before presenting the share sheet. Dismiss or complete sharing and confirm the temporary folder is removed.
6. Against disposable simulator data only, type `DELETE`, delete everything, and relaunch. Confirm the vault is empty, usable, and does not silently restore samples.

Export packages are assembled below the app's system temporary directory. The share sheet receives the completed folder only. Dismissing the sheet calls export cleanup; cancelled or failed assembly removes partial staging content.

## Test recording in the simulator

1. Boot and install the app, then configure the Simulator to use the Mac microphone as its audio input.
2. Launch normally. Tap Talk or Record appointment and accept the microphone prompt. The prompt must not appear before the tap.
3. Speak and confirm the timer advances and the waveform responds to real meter levels.
4. Stop and save. Play the recording from the saved screen and journal detail.
5. Record an appointment past 15 seconds. Confirm the displayed duration advances and the saved duration survives app relaunch.
6. Disconnect or change the simulator input route while recording. The app must stop, finalize the source, and show `Recording stopped` with `Saved on this device` when a valid file exists.
7. If the simulator exposes no camera source, confirm the unavailable state preserves existing content. Camera capture remains a real-device check.

Reset the simulator's microphone permission between prompt checks if needed:

```sh
xcrun simctl privacy booted reset microphone dev.candycorn.app
```

## Real-iPhone acceptance checklist

These items require a signed build on a real iPhone and are not proven by simulator tests or screenshot mode:

- Confirm the microphone prompt appears only after Talk or Start recording is tapped.
- Save a journal recording and play it from both the saved screen and journal detail.
- Record an appointment for more than 15 seconds, lock the phone, and confirm recording continues with background audio.
- Force termination after a 15-second checkpoint and confirm the last persisted duration supports recovery.
- Receive a phone call and invoke Siri during separate recordings. Each interruption must stop and save a valid source, then show a clear stopped state.
- Connect, switch, and disconnect Bluetooth input routes. Confirm route changes never discard a finalized recording.
- Navigate away from and back to an active appointment recording. Confirm recording state and duration remain coherent.
- Test camera permission denial, Settings recovery, cancellation, portrait rotation handling, focus, capture, and immutable JPEG display in journal detail.
- Reboot the phone. Before first unlock the vault should remain protected; after first unlock, protected files and background appointment behavior should work as documented.
- Complete and cancel the share sheet in separate exports. Confirm both temporary export folders are cleaned up.
- With disposable device data, type `DELETE`, delete everything, and confirm an empty relaunch with sample content still off.

Phase 3 adds Keychain, live BYOK, camera upload, connectivity-loss, provider-accounting, and no-audio-upload checks. Record those results with the evidence-safe template in `screenshots/PHASE3-DEVICE-CONTRACT.md`. Automated verification must never sign or install a device build, access a real key, or make a live provider request.

Record the device model, iOS version, audio route, and pass or fail result for each item. Do not record journal content, filenames containing user content, database paths, or media payloads.
