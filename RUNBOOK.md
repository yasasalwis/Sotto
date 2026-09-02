# Runbook

Sotto has no servers. "Operating" it means building, shipping and helping users on their own devices.

## Build & ship

1. `Scripts/fetch-llama.sh` (once per checkout, or after bumping `LLAMA_TAG`).
2. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in the Sotto target.
3. `xcodebuild -scheme Sotto -destination 'platform=macOS,arch=arm64' test` and the iOS equivalent must be green.
4. Archive from Xcode (Product › Archive) for macOS and iOS; distribute through TestFlight / App Store or Developer ID.
5. Tag the commit `vX.Y.Z`.

Rollback: re-submit the previous archive. There is no data migration to undo unless a release changed the SwiftData schema; keep schema changes additive (new optional fields) so older builds still open the store.

## Updating llama.cpp

1. Pick a release tag from https://github.com/ggml-org/llama.cpp/releases that ships `llama-<tag>-xcframework.zip`.
2. Download it, compute `shasum -a 256`, update `LLAMA_TAG` and `LLAMA_ZIP_SHA256` in `Scripts/fetch-llama.sh`.
3. Run the script, then `cd Packages/LlamaKit && swift test`. Check `llama.h` for signature changes (the wrapper touches: model/context params, tokenize, chat template, sampler chain, memory clear, abort callback).
4. Build both platforms and run one real generation on each.

## Updating the catalog

Edit `Sotto/Resources/Catalog/models.json`. Every entry needs a working `https://huggingface.co/.../resolve/main/<file>.gguf` URL and the exact `Content-Length` (check with `curl -sIL <url>`). `CatalogTests.bundledCatalogDecodes` enforces the invariants.

## Diagnosing user reports

- Logs: `log stream --predicate 'subsystem == "lk.eonix.Sotto"' --level info` (or Console.app). Categories: app, chat, models, downloads, engine, persistence, privacy, security, llama.cpp.
- Model won't load: look for `Failed to load` in `engine`; the message includes llama.cpp's reason. Common: unsupported architecture in this llama.cpp tag, or memory.
- Download failures: category `downloads`. Resume data survives relaunch; "Retry" restarts from the resume point.
- Store won't open: the app falls back to an in-memory store and shows an alert. The store is at `~/Library/Containers/lk.eonix.Sotto/Data/Library/Application Support/Sotto/Sotto.store` (macOS). Move it aside to recover.
- Crash diagnostics: only if the user enabled Crash reports; JSON files in `.../Sotto/Diagnostics/`, listed in Settings › Advanced.

## Rotating secrets

There are none. The app has no API keys, tokens or service credentials.

## Erasing data

Settings › Privacy › Erase all data removes conversations, personas (re-seeded), models, downloads, diagnostics and preferences. Users can also delete the app container.

## Incident checklist

1. Reproduce with the log stream above.
2. If it's a llama.cpp crash, capture the model name/quant and the `llama.cpp` category output; test the same file with the upstream `llama-cli` at the pinned tag.
3. Fix, add a regression test, ship a point release.
