# Sotto

A local-first chat client for Apple's on-device foundation model and imported open-source weights (GGUF). Nothing leaves the machine unless you start a model download.

- **macOS 26.5+ and iOS 26.5+**, SwiftUI + SwiftData, Swift 6 toolchain (Xcode 26.6).
- **Two inference engines**: Apple Intelligence through the `FoundationModels` framework, and any GGUF file through llama.cpp (Metal on device, CPU in the Simulator).
- **Tools the model can call**: twenty-five built-ins that run entirely on device — dates and time zones, arithmetic and units, percentages and number bases, text rewriting, find-and-replace, extraction, sorting, word counts and diffs, JSON and CSV, descriptive statistics, encoding, hashing, random numbers and a chat search — plus your own Google-search and HTTPS-request tools, each with its own approval rule. Four are on out of the box; the rest are one switch away in Tools, because Apple's on-device model has a 4,096-token window and every offered tool spends some of it. A macOS shell-command tool exists for builds distributed outside the App Store.
- **A menu bar item on macOS**: type a question in the status bar and it opens in a chat, plus your last five chats and every window one click away. Sotto keeps running when you close its window so the icon still works; one switch in Settings › General removes it and restores quit-on-close.
- **No accounts, no server, no analytics.** The only network calls are catalog downloads, the optional weekly catalog check, and any HTTPS tool you create yourself. Bytes sent are counted and shown on the Privacy page.
- **Free.** No in-app purchases, no subscription, no ads, no paid tier.

## Requirements

| Tool | Version |
|---|---|
| Xcode | 26.6 (build 17F113) or newer |
| macOS | 26.5 with Apple Intelligence enabled for the system model |
| CMake | any recent (only for the iOS Simulator slice of llama.cpp) |

## Setup

```bash
git clone <this repo> Sotto && cd Sotto
Scripts/fetch-llama.sh            # vendors llama.cpp b10759 into Packages/LlamaKit (verifies SHA-256)
open Sotto.xcodeproj
```

`fetch-llama.sh` downloads the official prebuilt `llama.xcframework` (macOS + iOS device) and, when `cmake` is on your `PATH`, builds the iOS Simulator slice from the same tag. Without cmake the Simulator build of the app fails to link; pass `--no-sim` to skip it knowingly. The framework is ~430 MB with debug symbols and is git-ignored.

Signing uses the team already set in the project. Change `DEVELOPMENT_TEAM` and `PRODUCT_BUNDLE_IDENTIFIER` in the target's build settings if you fork.

## Run

- macOS: select the **Sotto** scheme, destination **My Mac**, ⌘R.
- iOS: select an iPhone or iPad simulator (or device), ⌘R.

Command line equivalents:

```bash
xcodebuild -project Sotto.xcodeproj -scheme Sotto -destination 'platform=macOS,arch=arm64' build
xcodebuild -project Sotto.xcodeproj -scheme Sotto -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Double-clicking a `.gguf` file (macOS) or "Open in Sotto" from Files (iOS) imports the model.

On macOS, Sotto also sits in the menu bar. Clicking the icon opens a small panel: a field that takes a
question and hands it to a new chat in the main window, the five most recent chats, and shortcuts to
the library, compare, tools, presets and settings windows. Because the icon has to have an app behind
it, closing the last window leaves Sotto running rather than quitting — the panel's **Quit Sotto**, ⌘Q
and the Dock's Quit all still work, and turning **Show in menu bar** off in Settings › General puts the
old quit-on-close behaviour back.

Sotto also registers the `sotto://` URL scheme for Shortcuts and the command line: `sotto://new`, `sotto://library`, `sotto://compare`, `sotto://personas`, `sotto://tools`, `sotto://settings`.

## Tools

Open **Tools** (⇧⌘T) to see what a model may call. Twenty-five built-ins run entirely on device. Four ship enabled — date and time, calculator, unit converter and chat search — and the rest ship switched off, because every offered tool costs room in the model's context window (see below). You can add two more kinds:

| Kind | What it does | Notes |
|---|---|---|
| Google search | Searches the web through Google's Programmable Search and returns titles, snippets and links | Needs your own API key and search-engine id; ships disabled |
| HTTPS request | Calls a URL you write, with `{argument}` placeholders, and returns the body or a value from it | `https` only; argument values are percent-encoded so they cannot add parameters |
| Shell command | Runs a command with `/bin/zsh` as you | macOS only, **and not in App Store builds** — see below. Arguments are single-quoted before insertion, 20 second limit |

### The shell tool is not in App Store builds

App Review guideline 2.5.2 does not allow an app to execute code that introduces or changes its
functionality, and under App Sandbox a command would be confined to Sotto's own container
anyway. So the shell tool is compiled in only when `SOTTO_SHELL_TOOL` is defined, which the
**Debug** configuration does. Release builds — the ones you archive for the store — have no
shell tool: it is absent from the kind picker, and the executor refuses a shell tool left in
the database by an earlier build.

To ship it in a Developer ID build distributed outside the store, add `SOTTO_SHELL_TOOL` to
`SWIFT_ACTIVE_COMPILATION_CONDITIONS` in that build's Release configuration. Never add it to a
build destined for App Store Connect.

### Why most built-ins ship switched off

Every tool you enable is described to the model, with its parameters, before the conversation
starts. Apple's on-device model has a fixed 4,096-token window, and past roughly twenty offered
tools it stops answering at all rather than answering worse. Sotto keeps the offered list inside a
quarter of that window and skips anything that does not fit, so switching on a handful of tools you
actually use works better than switching on everything.

Text statistics ships off for a second reason: the system model reached for it on prompts like
"say hello in one word", where a word count is noise rather than help.

### Turning on Google search

Sotto ships a **Google search** tool, switched off because it needs two things of your own:

1. A Programmable Search Engine at [programmablesearchengine.google.com](https://programmablesearchengine.google.com/controlpanel/create), set to search the whole web. Copy its **search engine id** (`cx`).
2. An API key from the [Google Cloud console](https://console.cloud.google.com/apis/credentials) with the **Custom Search API** enabled.

Paste both into Tools › Google search, press **Run once** to check them, then switch the tool on. The free tier allows 100 searches a day. The key is stored in your keychain rather than Sotto's database, so it never appears in an export, and only the words the model searches for are sent to Google.

Each tool has a description (what the model reads), typed parameters, and an approval rule: **ask every time**, which shows a card in the chat before anything runs, or **run automatically**. "Try it" runs the tool immediately with no model involved. Personas can expose all tools, a chosen few, or none; a local-only persona never sees a tool that uses the network. One switch in Tools turns the whole feature off.

Apple's model calls tools through the Foundation Models framework. Imported GGUF models are offered the tools in their system prompt and answer with a tool-call block, which Sotto intercepts before it reaches the transcript.

## App icon

The icon is generated from the same mark the app draws in `LogoMark`, so the two cannot drift:

```bash
swift Scripts/make-app-icon.swift
```

It writes the iOS 1024² light, dark and tinted images (opaque, no alpha, full-bleed) and the
macOS 16–512 @1x/2x images (rounded, with alpha) into `Sotto/Assets.xcassets/AppIcon.appiconset`
and rewrites that catalog's `Contents.json`. Change `accent` in the script, or the letter, to
change the mark.

## Test

```bash
# llama.cpp wrapper (fast, no app)
cd Packages/LlamaKit && swift test

# App unit tests + UI tests
xcodebuild -project Sotto.xcodeproj -scheme Sotto -destination 'platform=macOS,arch=arm64' test
xcodebuild -project Sotto.xcodeproj -scheme Sotto -destination 'platform=iOS Simulator,name=iPhone 17' test
```

UI tests launch with `-hasCompletedOnboarding NO -storeConversations NO` so they never touch your real data.

## Architecture

```
Sotto/
  App/          entry point, services container, app state, root + main window, menu commands
  Design/       design tokens (colours, type, radii), bundled font registration, shared components
  Models/       SwiftData models (Conversation, Message, Persona, InstalledModel, ModelDownload)
  Domain/       pure types: ModelRef, formatters, catalog, token estimator, sampling resolution
  Engines/      InferenceEngine protocol, Apple Intelligence engine, GGUF engine, model runtime, prompt builder
  Engines/Tools/  tool execution, prompt-based tool calling, the Apple tool bridge, the calculator's parser
  Services/     settings, model store, download manager, attachment reader, diagnostics, app lock, export
  Features/     Onboarding, Chat, Sidebar, Inspector, Library, Compare, Personas, Tools, Settings
  Resources/    Geist + IBM Plex Mono (OFL), curated model catalog JSON, licences
  PrivacyInfo.xcprivacy   required-reason API declarations for App Store submission
Packages/LlamaKit/   Swift wrapper over the llama.cpp C API + the vendored xcframework
Scripts/             fetch-llama.sh, make-app-icon.swift
```

Data lives in the app container under `Library/Application Support/Sotto/` (`Sotto.store`, `Models/`, `Staging/`, `Diagnostics/`). The macOS app is sandboxed with user-selected read-only file access and outgoing network only.

See [docs/BLUEPRINT.md](docs/BLUEPRINT.md) for the design decisions, threat model and the design-to-platform gaps, [SECURITY.md](SECURITY.md) for the security model, [RUNBOOK.md](RUNBOOK.md) for operations, and [APP_REVIEW.md](APP_REVIEW.md) for the App Store submission checklist. User-facing pages: [PRIVACY.md](PRIVACY.md) and [SUPPORT.md](SUPPORT.md).

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Link error `no library for this platform` when building for the Simulator | The xcframework lacks a Simulator slice. Install cmake and re-run `Scripts/fetch-llama.sh`. |
| "Turn on Apple Intelligence in System Settings" | The system model needs Apple Intelligence enabled on a supported device. Imported GGUF models still work. |
| Simulator: Apple Intelligence unavailable | The Simulator only exposes the system model when the host Mac has Apple Intelligence on. |
| Model won't load: "not enough memory" | The estimate is weights + KV cache. Lower the context length in Settings › Models or pick a smaller quantization. |
| Download stuck at "waiting to start" on iPhone | "Downloads on Wi-Fi only" is on and you're on cellular. |
| Fonts look like system fonts | Font registration failed at launch; check the `fonts` category in Console. |

## Licence

Application code © 2026 Yasas Alwis. Bundled fonts are under the SIL Open Font License (see `Sotto/Resources/Licenses`). llama.cpp is MIT-licensed.
