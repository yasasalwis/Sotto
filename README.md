# Sotto

A local-first chat client for Apple's on-device foundation model and imported open-source weights (GGUF). Nothing leaves the machine unless you start a model download.

- **macOS 26.5+ and iOS 26.5+**, SwiftUI + SwiftData, Swift 6 toolchain (Xcode 26.6).
- **Two inference engines**: Apple Intelligence through the `FoundationModels` framework, and any GGUF file through llama.cpp (Metal on device, CPU in the Simulator).
- **No accounts, no server, no analytics.** The only network calls are catalog downloads and the optional weekly catalog check, both off by default or user-initiated. Bytes sent are counted and shown on the Privacy page.

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

Sotto also registers the `sotto://` URL scheme for Shortcuts and the command line: `sotto://new`, `sotto://library`, `sotto://compare`, `sotto://personas`, `sotto://settings`.

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
  Services/     settings, model store, download manager, attachment reader, diagnostics, app lock, export
  Features/     Onboarding, Chat, Sidebar, Inspector, Library, Compare, Personas, Settings
  Resources/    Geist + IBM Plex Mono (OFL), curated model catalog JSON, licences
Packages/LlamaKit/   Swift wrapper over the llama.cpp C API + the vendored xcframework
Scripts/             fetch-llama.sh
```

Data lives in the app container under `Library/Application Support/Sotto/` (`Sotto.store`, `Models/`, `Staging/`, `Diagnostics/`). The macOS app is sandboxed with user-selected read-only file access and outgoing network only.

See [docs/BLUEPRINT.md](docs/BLUEPRINT.md) for the design decisions, threat model and the design-to-platform gaps, [SECURITY.md](SECURITY.md) for the security model, and [RUNBOOK.md](RUNBOOK.md) for operations.

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
