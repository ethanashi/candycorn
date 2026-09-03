# 0001. First version AI provider: hosted router first, Apple Intelligence as the designed-for default

Date: 2026-09-02
Status: accepted

## Context

The specification prefers on-device Apple Intelligence (SystemLanguageModel, SpeechAnalyzer, FluidAudio) as the default AI route. Getting Foundation Models working on a real device is an unknown amount of integration work, and the first version has to visibly work on day one: summarize a rant, find candidate goals, turn a photographed handwritten page into text, and propose things to bring up at the next TMS or therapy appointment.

## Decision

- The first working version routes language tasks through a hosted model router (OpenRouter; the account key already lives in the operator's secret vault, never in the repo) behind the `CandyCornLanguageModel` protocol. Transcription and photo-to-text may also use a cloud provider in the first version.
- The architecture still centers on the protocols in spec section 23. The router is one `CandyCornLanguageModel` implementation; `AppleFoundationModelProvider` is added later without touching product code.
- Every AI artifact stores provider and model metadata (spec sections 9 and 28), so switching routes later is auditable.
- The privacy status screen tells the truth for whichever route is active: in the first version it reads "Journal intelligence: Cloud (router)", not "On-device".
- Photo journaling (photograph a handwritten page, extract text, keep the photo as the source) moves from P1 into the first version.

## Model routing for the first version

| Task | Route | Model |
|---|---|---|
| Session transcript (after diarization) to structured summary, homework, goals, talking points | OpenRouter | `deepseek/deepseek-v4-flash-0731` |
| Journal rant to cleaned text, summary, candidate goals, talking points | OpenRouter | `deepseek/deepseek-v4-flash-0731` |
| Appointment prep brief | OpenRouter | `deepseek/deepseek-v4-flash-0731` |
| Photographed handwritten journal page to text | OpenRouter | leading candidate `deepseek/deepseek-v4-flash-vision-exp` (text and image input, about 3.4 times the flash price, experimental); fall back to a Claude Haiku class vision model if its handwriting accuracy is poor. The extracted text is then handed to the flash model |
| Speech to text and speaker separation | On-device where available (SpeechAnalyzer, FluidAudio), cloud transcription fallback | n/a |

Verified 2026-09-02 from the build Mac: the vault key reaches OpenRouter, `deepseek/deepseek-v4-flash-0731` is listed (text only, 1.3M context, about $0.065 per million prompt tokens and $0.18 per million completion tokens), and a live journal rewrite returned faithful first-person text for about $0.00014. The model reasons before answering by default (237 reasoning tokens on a two-sentence rewrite), so the client must set a generous completion budget or request a reasoning cap; an 80-token budget returned empty content.

Model ids are configuration, not code (spec section 40). Every artifact records the provider and model that produced it. Distress support classification stays on its own interface and policy layer (spec section 23) and is not routed through the organizer model by default.

## Consequences

- Day one works on any iPhone, not only Apple Intelligence devices.
- Journal text leaves the device when AI is on. The AI mode switch (Off, Organizer, Reflection) and the "what leaves this device" preview in spec section 14.5 become first-version requirements rather than later polish.
- No key is ever bundled in the app. Use spec section 39 option A (laptop dev gateway) or option B (bring your own key stored in Keychain) for the personal test.
