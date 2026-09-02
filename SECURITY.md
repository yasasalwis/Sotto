# Security

## Reporting

Email yasaslive@gmail.com with steps to reproduce. Please don't open public issues for vulnerabilities. You'll get an acknowledgement within 3 working days.

## Security model

Sotto is a single-user, offline-first app with **no server, no account and no telemetry**. The assets are the user's conversations, personas and model files on their own device.

| Area | What's in place |
|---|---|
| Network | Only two paths reach the network: catalog downloads the user starts, and the optional weekly catalog check (off by default). Both are HTTPS to `huggingface.co`. Every byte sent is counted and shown in Settings › Privacy. Apple's FoundationModels framework runs on-device and offers no off-device route to third-party apps, so the Private Cloud Compute switch is deliberately disabled and explained. |
| Sandbox | macOS: App Sandbox with `com.apple.security.files.user-selected.read-only` and `com.apple.security.network.client` only. iOS: standard container. No app groups, no iCloud (the template's CloudKit and push entitlements are not used by any code and should be removed before shipping; see BLUEPRINT). |
| Storage | SwiftData store in the app container. iOS: `NSFileProtectionCompleteUntilFirstUserAuthentication` on the store and its WAL/SHM files. macOS: relies on FileVault. Model weights are excluded from backups. |
| App lock | Optional `LAContext` `.deviceOwnerAuthentication` gate; locks on backgrounding. |
| Input validation | GGUF files are validated by magic bytes before copy and by header parse (llama.cpp's `gguf` reader with `no_alloc`) before registration. Attachments are size-capped (25 MB) and character-capped (60k). Persona names/prompts have length limits. Catalog URLs are pinned in the bundle and required to be `https://huggingface.co`. |
| Downloads | Background `URLSession`, resume data persisted, completed files validated as GGUF before entering the library. Free-space check before starting. |
| Logging | `os.Logger` with no prompt, completion or file contents. Only lifecycle events, counts, durations and error descriptions. |
| Crash diagnostics | Opt-in MetricKit payloads written to the container; the user reviews and shares them manually. Nothing is uploaded automatically. |
| Supply chain | llama.cpp is pinned to tag `b10759`; the release archive's SHA-256 is verified by `Scripts/fetch-llama.sh`. Fonts are pinned copies from the google/fonts repository under OFL. No other third-party code. |
| Memory safety | All llama.cpp calls are serialized on one dispatch queue per model; buffers are sized from the API's own length reports; UTF-8 is assembled before it reaches the UI. |

## Out of scope

- Protection against a compromised OS or an attacker with physical access to an unlocked device.
- Confidentiality of model weights (they're public files).
