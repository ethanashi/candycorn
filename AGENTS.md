# Agent instructions for the Candy Corn repository

Read before doing anything here.

## What this repo is

Candy Corn is a patient-first mental-health continuity app. The full product and engineering specification is `docs/SPEC.md`. Architecture decisions live in `docs/decisions/`. The current phase is Phase 0: a clickable visual prototype, described in `docs/design/BRIEF.md` with reference evidence in `docs/design/references.json`.

## Layout

```
apps/candycorn-prototype/   Phase 0 static React + Vite prototype (build this first)
apps/candycorn-ios/         Phase 1+ native SwiftUI app (do not start until Phase 0 is reviewed)
docs/SPEC.md                the specification
docs/design/                brief, reference evidence, concept sheet pins
docs/decisions/             architecture decision records
```

## Rules

- Authority order for visual work: pinned renders in `design/sheet/*.png`, then `docs/design/BRIEF.md`, then `docs/SPEC.md`, then reference evidence, then general taste.
- Sentence case everywhere. No all-caps text, no eyebrow tags, no pulsing indicators, no cream canvas, no gradients or glow. See the brief.
- Seeded fictional data only. Never add real patient data.
- Never commit, print, log, or write any secret into any file. Cloudflare credentials come from the operator's secret vault at deploy time and are injected into the process environment only. If the vault is unreachable, finish and verify locally, stop before deploying, and report the missing capability without asking for a token to be pasted anywhere.
- No analytics SDKs, no advertising, no third-party trackers, ever.
- Do not couple this repo to any orchestrator runtime. It must build on its own with Node 22 and pnpm.
- Copy style: concrete, honest, short. No em dashes.
