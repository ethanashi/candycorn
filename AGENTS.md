# Agent instructions for the Candy Corn repository

Read before doing anything here.

## What this repo is

Candy Corn is a patient-first mental-health continuity app. The full product and engineering specification is `docs/SPEC.md`. Architecture decisions live in `docs/decisions/`. The current phase is Phase 0: a clickable visual prototype, described in `docs/design/BRIEF.md` with reference evidence in `docs/design/references.json`.

## Layout

```
apps/candycorn-prototype/   Phase 0 static React + Vite prototype (build this first)
apps/candycorn-ios/         Phase 1+ native SwiftUI app (Phase 0 approved 2026-09-02; build phases in docs/PHASES.md)
docs/SPEC.md                the specification
docs/design/                brief, reference evidence, concept sheet pins
docs/decisions/             architecture decision records
```

## Rules for the iOS app (apps/candycorn-ios)

- The Xcode project is generated from `project.yml` with XcodeGen. Edit `project.yml`, never the generated `.xcodeproj` by hand, and do not commit `DerivedData`, `build/`, `xcuserdata`, or `.build`.
- iOS 26 deployment target, Swift 6 language mode, SwiftUI with Observation. Icons are SF Symbols using the mapping in `apps/candycorn-prototype/src/core/icons.tsx`. Type is Avenir Next through `Font.custom`.
- Design tokens come from `apps/candycorn-prototype/src/styles/tokens.css` and the pinned renders in `apps/candycorn-prototype/design/sheet/`. Screens are compared against `apps/candycorn-prototype/screenshots/`.
- Verify with `xcodegen generate`, then `xcodebuild` against an iOS 26 simulator with code signing disabled, run the tests, boot the simulator, and capture every screen with `xcrun simctl io booted screenshot`. Never attempt a device install or signing in the pipeline.
- Vault key and any API key live in Keychain only. Never log journal, transcript, or model content; log event names and durations.
- Raw sources (audio, original text, photos) are never overwritten by AI output. Every AI artifact records provider, model, and source ids.

## Rules

- Authority order for visual work: pinned renders in `design/sheet/*.png`, then `docs/design/BRIEF.md`, then `docs/SPEC.md`, then reference evidence, then general taste.
- Sentence case everywhere. No all-caps text, no eyebrow tags, no pulsing indicators, no cream canvas, no gradients or glow. See the brief.
- Seeded fictional data only. Never add real patient data.
- Never commit, print, log, or write any secret into any file. Cloudflare credentials come from the operator's secret vault at deploy time and are injected into the process environment only. If the vault is unreachable, finish and verify locally, stop before deploying, and report the missing capability without asking for a token to be pasted anywhere.
- No analytics SDKs, no advertising, no third-party trackers, ever.
- Do not couple this repo to any orchestrator runtime. It must build on its own with Node 22 and pnpm.
- Copy style: concrete, honest, short. No em dashes.
