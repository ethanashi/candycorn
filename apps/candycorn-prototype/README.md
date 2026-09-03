# Candy Corn patient prototype

Candy Corn Phase 0 is a static, clickable continuity prototype for one fictional patient, Jamie Rivera. It demonstrates the patient MVP’s visual language, navigation, and local interaction states. It has no backend, account system, persistence, analytics, real AI, media capture, or network API calls.

## Requirements and commands

- Node.js 22 or newer
- pnpm 9 or newer

Run these commands from the repository root:

```sh
pnpm dev
pnpm typecheck
pnpm test
pnpm build
pnpm preview
```

The production build is written to `apps/candycorn-prototype/dist`. Vite’s preview server serves that built output. Routes use URL hashes so direct links work on a static host.

## Screen index

| # | Screen | Hash route |
|---:|---|---|
| 1 | Welcome and privacy | `#/welcome` |
| 2 | Today | `#/today` |
| 3 | Quick mood check-in | `#/check-in` |
| 4 | Capture choice | `#/capture` |
| 5 | Voice journal | `#/journal/voice` |
| 6 | Text journal | `#/journal/write` |
| 7 | Photo journal | `#/journal/photo` |
| 8 | Journal detail | `#/journal/entry/football-and-guilt` |
| 9 | AI suggestions | `#/journal/suggestions` |
| 10 | Goals | `#/goals` |
| 11 | Bring up next time | `#/bring-up` |
| 12 | Appointments | `#/appointments` |
| 13 | Record appointment | `#/appointments/record` |
| 14 | Active appointment recording | `#/appointments/active` |
| 15 | Therapy session detail | `#/sessions/therapy-sep-2` |
| 16 | TMS pre-session | `#/tms/pre-session` |
| 17 | TMS post-session | `#/tms/post-session` |
| 18 | Prepare for therapy | `#/prepare/therapy` |
| 19 | Prepare for TMS | `#/prepare/tms` |
| 20 | History timeline | `#/history` |
| 21 | Search and memory | `#/search` |
| 22 | Settings privacy | `#/settings/privacy` |
| 23 | Settings AI and processing | `#/settings/ai` |
| 24 | Settings data and export | `#/settings/data` |

At desktop widths, the review rail links to all 24 screens. Unknown routes show a recovery view with links to Today and the complete screen index.

## Visual contract and evidence

The governing visual brief is `docs/design/BRIEF.md`. The concept sheet is `apps/candycorn-prototype/design/sheet.html`, and its six accepted render pins are in `apps/candycorn-prototype/design/sheet/`. Exact 390 by 844 route captures are in `apps/candycorn-prototype/screenshots/`.

The continuity kernel is the only illustration family. Orange marks what Jamie said or chose, cocoa marks provider material with its source time, and yellow marks what Candy Corn noticed or suggested. Today and check-in use the three-band mood kernel. Goals, talking points, brief lines, journal suggestions, and relevant memory rows include a kernel and a provenance line.

## Architecture and prototype boundaries

`src/App.tsx` discovers feature-owned `screens.tsx` modules and builds routing plus the desktop review rail from that single registry. Shared seeded state is immutable, in memory, and resets on reload. Recording, photo capture, processing, and export are represented by future capability interfaces only. Phase 0 controls simulate state and do not invoke browser media, storage, permission, or network APIs.

The production target is native iOS, but Phase 0 is intentionally a browser render and interaction contract. A 44 CSS pixel control floor approximates the future 44 point iOS floor. Lucide browser icons are mapped to future SF Symbol names in `src/core/icons.tsx`.

This browser build does not prove native compilation, simulator rendering, Dynamic Type, safe areas, SF Symbols, permission dialogs, encrypted local storage, background recording, recording interruptions, real camera capture, transcription or diarization, or native export. These require later SwiftUI simulator and real-device proof in Phase 1.

## Deployment

The Cloudflare Pages project is `candy-corn-mvp-prototype` with production branch `main`. Deployment uses Wrangler direct upload of `apps/candycorn-prototype/dist`. Operator credentials are read only at deployment time from `~/.nyx/secrets/CLOUDFLARE_API_TOKEN` and `~/.nyx/secrets/CLOUDFLARE_ACCOUNT_ID`; they must never be committed, logged, or copied into project files.
