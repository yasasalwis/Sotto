# Security

## Reporting

Email contact@eonix.lk with steps to reproduce. Please don't open public issues for vulnerabilities. You'll get an acknowledgement within 3 working days.

## Security model

Sotto is a single-user, offline-first app with **no server, no account and no telemetry**. The assets are the user's conversations, personas and model files on their own device.

| Area | What's in place |
|---|---|
| Network | Four paths can reach the network, all user-initiated: catalog downloads, the optional weekly catalog check (off by default), the Google search tool (off until the user adds their own credentials), and any HTTPS tool the user creates. Every byte sent is counted and shown in Settings › Privacy. Apple's FoundationModels framework runs on-device and offers no off-device route to third-party apps. |
| Tool credentials | An API key typed into a tool is written to the keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, no iCloud sync), never to the database, an export or the log. The approval card for a search shows the query, not the key. "Erase all data" removes the keychain items too. |
| Tools | Tools are off for a model unless enabled, and a master switch disables the feature outright. A new tool defaults to disabled and to "ask every time", which shows the exact URL or command before anything runs. HTTPS tools are restricted to `https` and their argument values are percent-encoded so a model cannot append parameters or change the path. Shell tools are compiled out of App Store builds entirely (`SOTTO_SHELL_TOOL`; see [APP_REVIEW.md](APP_REVIEW.md)) and the executor refuses a persisted one rather than trusting the UI to hide it. Where they are compiled in, they are macOS-only, run under `/bin/zsh` with the user's own privileges, are capped at 20 seconds, and single-quote every substituted argument so an argument is data rather than syntax. Results are truncated to 4,000 characters and a reply may make at most four calls, so a model cannot loop. The calculator parses arithmetic with a hand-written recursive-descent evaluator rather than `NSExpression`, which raises uncatchable Objective-C exceptions on malformed input. |
| Sandbox | macOS: App Sandbox with `com.apple.security.files.user-selected.read-write` and `com.apple.security.network.client` only, synthesised from the target's build settings. The write half is what lets **Export all conversations** save to the file you pick in the save panel; Sotto reaches nothing you have not chosen there, and a model import is copied into the container rather than written back. iOS: standard container. No app groups, no iCloud, no push — the Xcode template's unused CloudKit and push entitlements file has been deleted. |
| Storage | SwiftData store in the app container. iOS: `NSFileProtectionCompleteUntilFirstUserAuthentication` on the store and its WAL/SHM files. macOS: relies on FileVault. Model weights are excluded from backups. |
| App lock | Optional `LAContext` `.deviceOwnerAuthentication` gate; locks on backgrounding. |
| Input validation | GGUF files are validated by magic bytes before copy and by header parse (llama.cpp's `gguf` reader with `no_alloc`) before registration. Attachments are size-capped (25 MB) and character-capped (60k). Persona names/prompts and tool names, descriptions and parameter counts have length limits. Catalog URLs are pinned in the bundle and enforced at decode time by `ModelCatalog.validate()` to be `https://huggingface.co` (or a subdomain), so a tampered or future remote catalog cannot redirect a download. Tool arguments chosen by a model are checked against the declared parameters before the tool runs. |
| Downloads | Background `URLSession`, resume data persisted, completed files validated as GGUF before entering the library. Free-space check before starting. |
| Logging | `os.Logger` with no prompt, completion or file contents. Only lifecycle events, counts, durations and error descriptions. |
| Crash diagnostics | Opt-in MetricKit payloads written to the container; the user reviews and shares them manually. Nothing is uploaded automatically. |
| Supply chain | llama.cpp is pinned to tag `b10759`; the release archive's SHA-256 is verified by `Scripts/fetch-llama.sh`. Fonts are pinned copies from the google/fonts repository under OFL. No other third-party code. |
| Memory safety | All llama.cpp calls are serialized on one dispatch queue per model; buffers are sized from the API's own length reports; UTF-8 is assembled before it reaches the UI. |

## Out of scope

- Protection against a compromised OS or an attacker with physical access to an unlocked device.
- Judging whether a tool the user creates is itself safe. A shell tool runs with the user's own privileges: Sotto blocks argument injection, not a command the user chose to add.
- Reviewing, filtering or fact-checking what a model writes. Sotto does not do this and says so in the app; see [PRIVACY.md](PRIVACY.md).
- Confidentiality of model weights (they're public files).
