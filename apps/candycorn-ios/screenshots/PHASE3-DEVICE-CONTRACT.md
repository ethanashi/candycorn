# Phase 3 real-device verification contract

Status on September 3, 2026: Not run. These checks require a signed build on a real iPhone, a disposable OpenRouter key, real camera hardware, and an operator-controlled provider account. The automated Phase 3 lane did not sign, install to a device, access a key, or make a live request.

## Evidence record

Complete one record for a single test session. Record pass or fail and content-free observations only.

| Field | Value |
| --- | --- |
| App commit |  |
| Device model |  |
| iOS version |  |
| Network class |  |
| OpenRouter model configuration |  |
| Tester date |  |

Do not record the API key, patient content, prompt or completion text, screenshots that expose the key, content-bearing filenames, database paths, attachment paths, or provider response bodies.

## Required checks

| Check | Procedure | Pass condition | Result |
| --- | --- | --- | --- |
| Disposable key entry | In AI and processing settings, choose Organizer, open the key sheet, enter a disposable OpenRouter key, and save. Keep any screen recording stopped while typing. | Router becomes available. The saved key is never displayed again and does not appear in console output, exports, screenshots, launch arguments, or the bundle. | Not run |
| Keychain relaunch and reboot | Terminate and relaunch. Reboot the iPhone, unlock it once, and relaunch again. | Router remains available after relaunch and after the first unlock following reboot. Before first unlock, protected access remains unavailable as expected. | Not run |
| Remove key | Tap Remove key and confirm. Relaunch the app. | Router becomes unavailable immediately, active Router selection switches to Off, and the key remains absent after relaunch. Manual capture and editing still work. | Not run |
| Delete everything | Save a new disposable key, then complete the typed Delete everything flow with disposable app data. Relaunch. | The key and model overrides are removed, Router is unavailable, and the replacement vault is empty and usable. | Not run |
| Fictional text request | Save a fresh disposable key. Create one fictional text journal, request one organizer action, inspect the disclosure ledger, then tap Send once. | The ledger names only the selected fictional entry with its exact `String.count`, one provider request occurs only after Send, the configured organizer model is used, and the original journal remains unchanged. | Not run |
| Fictional photo request | Capture a fictional handwritten journal page with the real camera, save it, request photo to text, inspect the image disclosure, then tap Send once. Review the later organizer disclosure separately. | The first ledger reports zero characters and one image. The vision model is used. Extracted text is stored as a separate Candy Corn artifact, and organizer calls use that text with its exact character count. The original photo remains unchanged. | Not run |
| Provider accounting and privacy | After the fictional text and photo requests, inspect the configured model IDs in the app, OpenRouter activity, app privacy logs, and provider usage or billing. | The configured model IDs and expected request count agree. Usage is attributable without prompt, completion, journal, transcript, note, filename, path, key, or image content appearing in app logs. | Not run |
| Connectivity loss | In airplane mode, start a fictional organizer send after reviewing its disclosure. Restore connectivity only after the request has finished failing. | The app reports a short safe failure after bounded retry behavior, keeps source content intact, allows retry, and does not expose a provider body or key. | Not run |
| Photo extraction failure | Capture and save a fictional photo, then force extraction failure through connectivity loss or a disposable invalid key. | The immutable photo remains available and unchanged. No empty or partial extracted-text artifact replaces it. | Not run |
| No audio upload | Record or open fictional journal and appointment audio, then inspect AI and processing status and available send flows. | Voice transcription reads `Not yet available`. No disclosure offers audio and no network request contains audio or a transcript derived from it. | Not run |

## Completion rule

Phase 3 real-device acceptance passes only when every row above has an explicit Pass result with the device metadata completed. A Fail or Not run result keeps device acceptance open. Do not weaken a failed result because simulator or unit evidence covers adjacent behavior.
