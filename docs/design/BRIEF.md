# Candy Corn Phase 0 design brief

This is the operator's brief for the clickable prototype. It sits above the specification wherever the two disagree on visual matters, and below it on everything else. Read the spec's sections 6 through 19, 49, 50, 64, 76, and 77 for screen content; read this for how it should look and feel.

## What we are making

A high-fidelity, click-through prototype of every patient MVP screen, as a static React, TypeScript, and Vite app in `apps/candycorn-prototype/`. Seeded fictional data only. No backend, no real AI, no real recording, no accounts. It is the visual contract for the native SwiftUI app that follows, so it must be finished enough to show a stranger and specific enough that the iOS build can copy it.

Primary viewport is a phone (390 by 844). It must also render cleanly at 430 by 932 and in a desktop browser at 1280 by 800, where the app sits centered at phone width inside a quiet review shell with a list of every screen down the left side so a reviewer can jump between them. The review shell is white and unbranded; the app inside it is the design.

## Audience and promise

A person in treatment for depression, anxiety, or trauma, often tired and sometimes overwhelmed, who wants to stop reconstructing their life from memory every time they sit down with a therapist or TMS provider. Promise: be messy in private, let the app organize what matters, walk into the appointment prepared.

## Primary job

Capture in seconds, then arrive prepared. The one path that must work: open, log how you feel, talk or write, see it organized, pin what to bring up, read the prep brief before the appointment. Every screen is scored against that path. The Prepare screen is the hero.

## World materials

Candy corn itself: three stacked bands, white tip, orange middle, yellow base, a soft waxy matte surface, a rounded triangle silhouette. A paper journal. A waiting room chair. A quiet voice memo. The three bands are the design's whole color story and they map to real product meaning below. Nothing in the app depicts Halloween, pumpkins, bats, candy piles, or a bag of sweets.

## Palette stance: chromatic, three roles, candy corn everywhere

The operator wants candy corn colors on every screen, not as a subtle hint. The way to do that without turning the app into a Halloween brand is to give each band a job and use it wherever that job appears.

| Token | Value | Job |
|---|---|---|
| canvas | #FFFFFF | The white tip. Page background. Pure white, never cream. |
| surface | #FFFFFF | Cards sit on white with a warm hairline, or on a warm wash; see depth. |
| surfaceWarm | #FFF4E8 | Warm wash for grouped regions and selected rows. |
| orange | #F28A3C | The middle band. Primary actions, selected states, the recording control, and everything the user said or chose. |
| orangePressed | #D9732F | Pressed state of orange. |
| yellow | #F4C95D | The base band. Progress, mood and energy fills, highlights, and everything Candy Corn noticed or suggested. |
| yellowDeep | #E0AE3A | Yellow on white for text-sized marks where #F4C95D would fail contrast. |
| cocoa | #2D2825 | Primary text, and everything the provider said. |
| cocoaSoft | #766D67 | Secondary text and captions. Never lighter than this for text. |
| hairline | #EBE2D8 | Borders and dividers. |
| sage | #8FA58B | Completed, saved, safe. |
| rose | #C9877C | Warnings and the stop-recording confirmation. |

The three provenance voices the spec makes non-negotiable are the three bands:

- You said or chose: orange.
- Provider said: cocoa, always with its source timestamp.
- Candy Corn noticed or suggested: yellow, always labeled as a suggestion.

These never swap roles anywhere in the app. That single rule is what makes the palette read as one system instead of decoration.

Contrast: body text is cocoa on white. Orange and yellow are used as fills, glyphs, and large marks, not as small text on white. White text on orange is allowed only at 17px semibold or larger on the primary button.

## Signature element: the kernel

One candy corn kernel silhouette, a rounded triangle about 1.3 times taller than wide, filled solid in one of the three voice colors. It is the provenance glyph in front of every goal, talking point, summary line, and memory card, and it is the app mark. The same silhouette, re-skinned by color only, is the whole illustration system; there are no other illustrations.

Checkable claim: every goal row, talking point row, brief line, and journal suggestion carries a kernel glyph between 16 and 20px tall, filled orange for user, cocoa for provider, or yellow for Candy Corn, followed by a sentence-case source line such as "You chose this", "Therapist assigned this on Sep 2 at 42:18", or "Candy Corn suggested this". A screen with provenance content and no kernel glyphs fails.

Second checkable claim, the mood object on Today and the check-in: three horizontal bands stacked in candy corn order (yellow, orange, white with a hairline) at least 70 percent of content width, each band a 1 to 10 fill for anxiety, mood, and energy, with tabular numerals at the right edge. It reads as a kernel lying on its side. It appears on Today, on the check-in, and as a small version on each history day header. It never appears as a generic progress bar.

## Reference system: skeleton, never skin

Borrow composition mechanics from these real products. Evidence with canonical Mobbin URLs and observed mechanics is in `references.json`.

- Today and Settings: Apple Health Summary. Large left title, section headers on the canvas, white cards with a category label at top left and a date at top right, one large tabular number, floating bottom tab bar.
- Check-in: Liven. The question is the page title; the answer control is the object under it.
- Talk and Record: Apple Notes recording sheet and Quo. Edge-to-edge waveform band, very large tabular timer, one round control, nothing else.
- Journal result: Fabric and ABY Journal. Text tabs over calm prose; the AI content sits in its own clearly bounded region below or in a sheet, never interleaved with the original.
- Session detail: Otter. Speaker name in color with timestamp on one line, paragraph beneath, playback scrubber pinned at the bottom.
- Goals: Asana and Attio. Collapsible cadence sections with counts, hairline rows, a second metadata line for provenance.
- History: stoic. and Bloom. Day headers on the canvas, compact entry rows with a type glyph.
- Consent: X and Wispr Flow. A full-craft permission sheet: glyph, title, one sentence of reason, an explicit acknowledgement, one full-width button.
- Prepare: Hers. The brief is prose. Large heading sentence, short statements, the patient's own data highlighted inline with a soft tint, one pinned action.

Never take any of their colors, logos, imagery, mascots, or copy voice.

## Typography and voice

Avenir Next, falling back to the system sans stack. Weights: body and secondary 400, labels and chrome 500, row titles and buttons 600, page titles 700. Nothing heavier. Tabular numerals wherever digits sit in a column or update in place: the recording timer, mood numbers, timestamps.

Sentence case everywhere, including headings. No all-caps labels anywhere, so the spec's ORIGINAL, CLEANED, SUMMARY become Original, Cleaned, Summary. No eyebrow tags or kicker capsules above headings. Copy is concrete and honest: "Saved on this device", not "Securely stored".

## Depth and shape

One recipe: white cards with a 1px hairline and a 20px radius on the white canvas, plus the warm wash (surfaceWarm) for grouped regions and selected rows. No drop shadows heavier than 0 2px 8px at 6 percent. Primary buttons are 56px tall rounded rectangles with a 16px radius, not pills. Compact pills only for the History filter and the appointment type picker, where the shape is a real selectable filter. Tap targets 44px minimum.

## Motion

120 to 220ms ease-out transitions on navigation and state. Nothing pulses. The recording state is shown by a moving waveform, a filled orange stop control, the running timer, and the word "Recording" in cocoa. No red dot, no blinking.

## Attention budget per key screen

- Today: dominant region is the mood bands with "How are you doing?" as the page question; supporting regions are the three action buttons (Talk, Write, Record appointment) and the next appointment card. Bring up next time and goals follow below the fold. Maximum three decisions visible at once.
- Talk: dominant region is the timer and waveform; the only decision is Stop. After stop: "Saved on this device" and two choices, Transcribe or Keep audio only.
- Journal result: dominant region is the Original text. Cleaned and Summary are tabs. Suggestions sit below in a yellow-voiced region with per-item add controls.
- Prepare: dominant region is the brief itself as readable prose. One pinned action: Edit brief. A patient reads this in the waiting room.
- Session detail: dominant region is the speaker-separated transcript or the summary, switched by tabs; summary lines link to timestamps.
- Privacy and AI status: this screen is product value, not boilerplate. A short list of rows, each with a kernel glyph and a plain status: "Stored on this device", "Journal intelligence: Cloud (router) for the first version", "Voice transcription: Cloud (router)", "Cloud upload: only when AI is on", "Raw audio retention: you decide". Truthful for the first version per `docs/decisions/0001-first-version-ai-provider.md`, with an AI provider setting offering Off, Organizer, and Reflection modes and a provider picker (On-device when available, Router, Off).

## Screens to build

All 23 screens in spec section 50 plus one: Photograph a journal page (camera frame, then the extracted text shown beside the photo with the photo kept as the original). Onboarding can be the four short privacy pages plus "Create my vault". Every screen has seeded, realistic, non-clinical content in the voice of a single fictional patient whose thread runs through the whole app (the football and guilt storyline in the spec is fine to use).

## Non-negotiables from the operator's taste

- No cream, beige, or off-white canvas. White.
- No serif or novelty type. No template webfonts.
- No all-caps text anywhere. No eyebrow tags.
- No pulsing or blinking indicators.
- No one-sided colored card borders.
- No glass, glow, gradients, or purple "AI" treatment. Candy Corn's AI looks like a quiet utility in yellow.
- No lorem, placeholders, or empty states above the fold.
- One job per screen. Detail lives a tap deeper.
- Bold anchors only: if everything is 700, it is wrong.

## Two tests before pinning any frame

1. Noun replacement: rename the product and swap the nouns. If the screen still fits an unrelated app, it is not specific enough.
2. Notes and Settings: if a screen is only headings, hairlines, prose, and stock controls with no kernel, no bands, and no product object, it fails no matter how clean it is.

## Deliverables

- `apps/candycorn-prototype/` builds clean with no console errors.
- `apps/candycorn-prototype/design/sheet.html` and pinned renders in `design/sheet/*.png`: the accepted concept sheet, produced before the screens and used as the contract.
- Screenshots of every screen at 390 by 844 in `apps/candycorn-prototype/screenshots/`.
- A README listing every route.
- Deployed to Cloudflare Pages as project `candy-corn-mvp-prototype` using the credential in the operator's secret vault, injected into the environment only, never printed, logged, or written to any file.
