# Sotto — Blueprint, threat model and decisions

This document records what was decided while turning the design canvas (15 screens, macOS + iOS) into a working app, including the places where the platform could not deliver what the mock implies.

## Product

A local-first chat client. Two engines: Apple's on-device foundation model (`FoundationModels`) and imported/downloaded GGUF weights (llama.cpp). Screens: onboarding, new chat, chat + inspector, model library (installed / downloading / catalog), side-by-side compare, presets & personas, settings & privacy, with iOS equivalents.

## Stack

| Layer | Choice | Why |
|---|---|---|
| UI | SwiftUI, one codebase, `#if os()` for layout | Design is native on both platforms; shared components keep the token palette exact. |
| Persistence | SwiftData, in the app container | Zero-config, local, supports the in-memory mode behind "Store conversations". |
| Apple model | `LanguageModelSession` + `Transcript` replay, streamed snapshots | Official on-device API; transcripts let each conversation rebuild its own session. |
| Open models | llama.cpp `b10759` xcframework via a local Swift package (`Packages/LlamaKit`) | Only production-grade GGUF runtime with Metal. Pinned + checksummed; Simulator slice built from source because upstream doesn't ship one. |
| Downloads | Background `URLSession`, resume data persisted in SwiftData | Multi-GB files must survive backgrounding and relaunch. |
| Fonts | Geist + IBM Plex Mono bundled (OFL) | The design's type is part of its identity. |
| Logging | `os.Logger`, subsystem `lk.eonix.Sotto` | Unified log, no prompt contents. |

## Threat model

**Assets**: conversations and attachments (may contain anything the user pastes), personas, model files, preferences.
**Trust boundaries**: app ↔ file system (user-picked files), app ↔ huggingface.co (downloads, optional catalog check), app ↔ FoundationModels system service.

| STRIDE | Risk | Mitigation |
|---|---|---|
| Spoofing | A malicious "GGUF" file | Magic-byte check, header parse with `no_alloc`, size and free-space checks before copy; llama.cpp validates tensors on load. |
| Tampering | Modified download | HTTPS to a pinned host; file validated as GGUF before install. (No upstream hashes are published per file; a future catalog version could carry SHA-256s.) |
| Repudiation | n/a (single user) | — |
| Information disclosure | Conversations leaving the device | No network path carries user text. PCC is disabled because the OS offers none. Bytes sent are counted and shown. Logs never include content. iOS file protection on the store; optional biometric lock. |
| Denial of service | Huge attachments or prompts exhausting memory | Attachment caps (25 MB / 60k chars), prompt trimming to the context window, memory fit check before loading a model, cooperative cancellation with llama.cpp abort callback. |
| Elevation of privilege | Sandbox escape via file access | macOS App Sandbox with read-only user-selected files and network client only; imports are copied into the container and the source is never written. |

Highest-risk surfaces: (1) GGUF parsing in native code — mitigated by validation and pinning a recent llama.cpp; (2) background downloads writing to disk — validated before entering the library; (3) attachments read from arbitrary files — text-only extraction, capped.

## Design-to-platform gaps (honest list)

1. **Private Cloud Compute switch** appears in five screens of the design. Apple's FoundationModels framework runs only on device for third-party apps; there is no API to route to PCC, so a switch that can never be turned on was misleading and has been removed from every screen at the owner's request. The persona "local only" flag survives with a real meaning: that persona may only call tools that run on this device.
2. **"Encrypted with your login keychain"** (Settings copy) — SwiftData has no keychain-bound encryption. The store is protected by iOS Data Protection (`completeUntilFirstUserAuthentication`) and, on macOS, by FileVault. Copy was changed to say so.
3. **Apple model context** is shown as 8K in the design; the real window is 4,096 tokens and the app shows the real number. Apple's model reports no token counts, so its counter and tok/s are estimates (≈4 chars/token) and labelled `~`.
4. **Crash reports** — there is no server to send to. The toggle enables MetricKit collection to the app container; users review and share manually.
5. **Catalog "Browse"** is a curated, bundled list (10 models, sizes verified) rather than a live Hugging Face search; the optional weekly check refreshes file lists for those repositories.
6. **iOS "swipe to swap models"** in the compare mock is implemented as tapping either model name to swap.
7. **Dark mode** is not in the design; the app pins a light appearance.
8. **visionOS** was in the template's supported platforms but not in the design; it was removed because llama.cpp's binary has no visionOS slice.
9. **CloudKit / push entitlements** from the Xcode template are gone. `Sotto.entitlements` was never referenced by the target (`CODE_SIGN_ENTITLEMENTS` is unset; App Sandbox, read-only user-selected files and the network client are synthesised from build settings) and has been deleted, along with its unused `aps-environment` and its CloudKit service declared against an empty container array — the latter would have failed App Store validation had anyone wired the file up. No `UIBackgroundModes` is set.
10. **App Store readiness** is tracked separately in [APP_REVIEW.md](../APP_REVIEW.md): the icon set, `PrivacyInfo.xcprivacy`, export-compliance and in-place document keys, the generated-text notice, and the removal of the shell tool from store builds under guideline 2.5.2.

## Data model

- `Conversation` (id, title, timestamps, modelRef, personaID, sampling overrides, allowsPrivateCloudCompute) 1→many `Message` (role, text, state, metrics, attachments, cascade delete).
- `Persona` (name, summary, system prompt ≤ 8k chars, model, temperature, topP, maxTokens, localOnly, shortcut slot 1–9, usage count).
- `InstalledModel` (file name in the models dir, size, quant, params, architecture, context, measured tok/s, source, catalog id).
- `ModelDownload` (catalog id, url, bytes, state, resume data, error).
- Preferences in `UserDefaults` (see `SettingsStore.Key`); privacy-affecting keys default to off.

## macOS menu bar

`MenuBarExtra` (window style) hosts a field, the five most recent chats and the window shortcuts.
It deliberately does **not** stream a reply: a prompt typed there is stored on `AppState.quickPrompt`
by `AppServices.startQuickPrompt`, which also creates (or reuses) an empty chat, and `MainView` sends
it once that chat's `ChatSession` exists. Keeping generation in one place means tool approval,
attachments, retries and the transcript have a single implementation, and a prompt survives the
window being closed.

Two consequences worth naming:

- **Residency.** `SottoMacAppDelegate.applicationShouldTerminateAfterLastWindowClosed` returns false
  while `showMenuBarExtra` is on, so the icon always has an app behind it. With the preference off the
  app quits on close as before. A closed window is re-created through `MainWindow.show`, which prefers
  the `NSWindow` recorded by `MainWindowTracker` and falls back to `openWindow(id:)`.
- **The lock.** The panel shows chat titles, so it renders a locked notice instead whenever
  `AppLock.status != .unlocked`, and offers no prompt field until onboarding is done.

## Build phases (as delivered)

1. Foundation: package + vendoring script, design tokens, fonts, models, settings, logging, persistence, CI.
2. Engines: Apple Intelligence, llama.cpp wrapper, runtime, prompt trimming.
3. Chat: sidebar, composer, streaming, retry, try-on, attachments, inspector.
4. Library: import, drag/drop, catalog downloads with pause/resume, delete, storage.
5. Compare, personas, settings, onboarding, app lock, export, erase.
6. Verification: unit tests (LlamaKit + app), integration tests (real inference), UI tests, manual runs on macOS and the iOS Simulator.

## Tools (added after the first build)

A model may call tools. Twenty-five built-ins run on device, in five groups:

| Group | Tools |
|---|---|
| Original | `current_datetime`, `calculate`, `convert_units`, `text_statistics`, `search_conversations` |
| Calendar | `date_difference`, `date_shift`, `time_in_zone`, `calendar_facts` |
| Text | `transform_text`, `replace_text`, `extract_matches`, `sort_lines`, `word_frequency`, `compare_texts` |
| Data | `format_json`, `query_json`, `summarize_csv`, `describe_numbers`, `percentage`, `convert_base` |
| Encoding | `encode_text`, `hash_text`, `random_number`, `estimate_tokens` |

Users can add HTTPS-request tools (URL template with `{argument}` placeholders, optional JSON dot-path into the answer) and, on macOS, shell-command tools.

| Concern | Decision |
|---|---|
| Two engines, one protocol | Apple's model gets native tool calling: each definition is bridged to a `Tool` whose parameters come from a `DynamicGenerationSchema`. llama.cpp has no tool protocol, so tools are described in the system prompt and the reply is scanned for a call block. |
| Stripped tags | Qwen and friends hold `<tool_call>` in the vocabulary as a special token, which llama.cpp does not render into text. The scanner therefore also treats a reply that is nothing but a JSON object with `name` and `arguments` as a call, tracking brace depth across chunks and ignoring braces inside strings. |
| Approval | Per tool: ask every time (a card in the chat showing the exact URL or command) or run automatically. "Always allow" flips the tool to automatic. Built-in read-only tools default to automatic; chat search asks. |
| Injection | HTTPS argument values are percent-encoded with `&=+?#/` removed, so a model cannot add parameters. Shell arguments are single-quoted with embedded quotes escaped. |
| Runaway loops | Four tool calls per reply, 20 second timeout each, results truncated at 4,000 characters. |
| Which built-ins ship on | Four: date and time, calculator, unit converter and chat search. The twenty added later ship off to stay inside the context budget, and text statistics was switched off after the system model called it for "say hello in one word" — a word count is noise there. Seeding never flips a switch the user has set. |
| Google search | A first-class tool kind rather than a generic HTTPS tool, because the useful output is a short list of titles, snippets and links rather than the raw JSON, and because the credentials deserve a real setup panel. It ships disabled and unusable until the user supplies a key and engine id. The key lives in the keychain keyed by the tool's id. |
| Persona scope | A persona exposes all tools, a chosen few, or none. `localOnly`, previously decorative, now means the persona never sees a tool that uses the network. |
| Calculator safety | `NSExpression` raises Objective-C exceptions Swift cannot catch, so arithmetic uses a hand-written recursive-descent parser supporting `+ - * / % ^`, unary minus and parentheses. |
| No model-supplied patterns | `replace_text` matches literally and `extract_matches` offers eight fixed, audited patterns rather than accepting a regular expression. Built-ins run without the shell tool's timeout, so a pattern that backtracks catastrophically would hang the reply with nothing able to stop it. This is the same reasoning as the calculator row above. |
| Tool count is bounded by the window | Every offered tool's description and schema is read into the model's context before the conversation, and Apple's system model has a fixed 4,096 tokens. Measured on iOS 26.5: twenty tools answered and called the right one; twenty-four failed outright with a bare `GenerationError` before running anything; and at two fifths of the window the session managed four tool calls before the accumulated results overflowed it. So the twenty tools added after the original five **ship switched off** — turning them all on by default would have broken the app's own model on first launch — and `AppleIntelligenceEngine` trims whatever is enabled to a quarter of the window, keeping the user's order, skipping what will not fit and logging what it left out. A smaller menu also makes a 3B model choose better: with fifteen tools offered it looped between two of them, with ten it made one correct call. |

## Known limitations / next phase

- Two GGUF models in Compare run one after the other (one loaded model at a time); Apple + GGUF run concurrently.
- Titles come from the first message rather than a model summary (keeps the first response fast).
- No conversation search; no iCloud sync (by design).
- Tool calls are not replayed when a conversation is retried; the record of the earlier call stays on the message it belonged to.
- A model may call at most four tools per reply, and they run one at a time.
- Candidates for the next version: per-file SHA-256 in the catalog, conversation search, multiple loaded models on machines with headroom, LoRA adapters, image input for multimodal GGUFs, and sharing a tool as a file others can import.
