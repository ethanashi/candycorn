# Candy Corn build phases

Phase 0 (the clickable prototype) was approved on 2026-09-02. The prototype at `apps/candycorn-prototype/` and its pinned renders in `apps/candycorn-prototype/design/sheet/` are the visual contract for everything below.

The real product is a native SwiftUI iPhone app at `apps/candycorn-ios/`. Each phase ends with something you can install and use. Phases run one at a time on the build pipeline; each one starts from the merged result of the previous one.

## Phase 1. SwiftUI shell that matches the prototype

Goal: the real app looks like the prototype and navigates like it, with seeded data and no persistence yet.

- XcodeGen project (`project.yml`), iOS 26 deployment target, Swift 6, SwiftUI, Observation.
- Design tokens in Swift derived from the prototype CSS: canvas white, orange, yellow, cocoa, cocoa soft, hairline, sage, rose; Avenir Next type scale; 16 and 20 point radii.
- Shared components: kernel glyph (three voices), three-band mood object, provenance line, primary and secondary buttons, floating tab bar, screen layout with back action.
- All 24 screens as SwiftUI views with the prototype's seeded content, wired through a navigation model with the five tabs plus modal capture and recording flows.
- SF Symbols in place of Lucide, using the mapping in the prototype's `src/core/icons.tsx`.
- Simulator build passes; screenshots of every screen at iPhone 17 size are compared against the prototype screenshots.

Done when the SwiftUI app is close enough to the prototype that later functional work needs no information-architecture changes.

## Phase 2. Care vault and manual capture

Goal: a useful private journal and appointment-prep tool with AI off.

- GRDB with SQLCipher. Vault key generated once, stored in Keychain, never logged.
- Migrations for journals, mood logs, appointments, goals, goal progress, talking points, AI artifacts, attachments, providers, and FTS5 indexes.
- Journal, mood, goal, and talking-point create, edit, and delete. Pin to next appointment from any screen.
- Voice journal recording with AVAudioSession, saved to the attachments directory before anything else happens.
- Photo journal capture: camera, save the image as the source attachment.
- History timeline and text search over the vault.
- Export and delete: a plain folder export of originals and notes, and delete everything.

Done when the app is a working local journal you could use daily with no network.

## Phase 3. Organizer AI through the router

Goal: the day-one AI value, routed through OpenRouter to `deepseek/deepseek-v4-flash-0731` behind the `CandyCornLanguageModel` protocol (decision 0001).

- Provider protocols from spec section 23 and an `OpenRouterLanguageModel` implementation with structured JSON output, retries, and redacted logging.
- Journal rewrite (original preserved), summary, talking-point suggestions, explicit-commitment extraction as candidate goals the user confirms.
- Photo page to text through a vision model on the router, then the same organizer steps.
- AI modes Off, Organizer, Reflection, and a "what leaves this device" preview before each send.
- Key handling per spec section 39: bring your own key stored in Keychain, or a laptop dev gateway. No key in the app bundle.
- Every artifact records provider, model, and source ids.
- `AppleFoundationModelProvider` stub behind the same protocol for later on-device use.

Done when a rant becomes a cleaned version, a summary, and useful talking points on a real phone.

## Phase 4. Appointment audio

Goal: record a consented appointment and get a trustworthy speaker-labeled transcript.

- Consent screen, background recording while locked, interruption and route-change handling, periodic persistence.
- SpeechAnalyzer and SpeechTranscriber for local transcription with timestamps.
- FluidAudio diarization; alignment into You, Provider, Unknown segments; editable speaker labels; optional local patient voice profile.
- Structured therapy and TMS summaries through the organizer model, every item linked to a transcript timestamp.
- Homework and provider-assigned goals extracted with provider provenance, confirmed by the user.

Done when a real session becomes a speaker-labeled transcript and a structured summary you trust.

## Phase 5. Memory and Prepare

Goal: the hero feature works for real.

- Retrieval over the vault (FTS5 first, embeddings later) to assemble a working context packet.
- Prepare for therapy and Prepare for TMS briefs generated from the last session, homework, goals, pinned items, journals since, and mood trend. Editable before use.
- Goal progress suggestions from new entries, confirmed by the user.
- Weekly consolidation summary.

Done when the brief you read before an appointment is genuinely useful.

## Phase 6. Use it for real

Install on your phone and use it through actual therapy and TMS appointments. The question to answer before any web app or sync work: did it make the appointment easier and more productive?

## What is needed from you

| Item | Why | When |
|---|---|---|
| Sign in to Xcode with your Apple ID (Xcode, Settings, Accounts) | Creates the free development signing identity needed to install on your phone. Simulator builds do not need it. | Before Phase 1 device install |
| Your iPhone on iOS 26, plugged in once with Developer Mode enabled | SpeechAnalyzer and Foundation Models need iOS 26. Device install and lock-screen recording tests need the real phone. | Phase 1 device install, Phase 4 |
| OpenRouter key | Already in your vault; Phase 3 wires it through the dev gateway or Keychain, never the bundle. | Phase 3 |
| Choice of vision model on OpenRouter for handwritten pages | Photo journaling to text. | Phase 3 |
| A recorded practice conversation, with consent | To test transcription and diarization before a real appointment. | Phase 4 |

## What is already in place

- Xcode 26.6, Swift 6.3, iOS 26.5 simulators, XcodeGen on the build Mac.
- The build pipeline's native lane: xcodebuild, simulator screenshots, comparison against pinned renders.
- Cloudflare and OpenRouter credentials in the operator vault.
- Prototype screenshots for all 24 screens as the visual target.
